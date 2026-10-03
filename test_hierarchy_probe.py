#!/usr/bin/env python3
"""Record native hierarchy state and AX output without claiming an adapter."""

import argparse
import ctypes
import uuid
import hashlib
import json
import platform
from pathlib import Path
import subprocess
import sys
import time

from build_component import BUILD

def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return None


def finish_run(process, resources, run_id, report, report_path, checks_finished):
    """Close only the owned process and persist success only after clean shutdown."""
    errors = []
    try:
        if process.poll() is None:
            try:
                (resources / "close.json").write_text("{}")
                process.wait(timeout=20)
            except (OSError, subprocess.TimeoutExpired) as error:
                errors.append(str(error))
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
    except (OSError, subprocess.TimeoutExpired) as error:
        errors.append(str(error))
    finally:
        report["exitCode"] = process.returncode
        report["closed"] = read_json(resources / "closed.json")
        if (resources / "error.json").exists():
            report["finalError"] = read_json(resources / "error.json") or "Unreadable error marker"
        report["shutdownErrors"] = errors
        report["passed"] = bool(checks_finished and process.returncode == 0
            and isinstance(report["closed"], dict) and report["closed"].get("runId") == run_id
            and not report.get("finalError") and not errors)
        if report["passed"]:
            report["checks"].append("Owned process exits zero with a matching close marker and no error")
        report_path.write_text(json.dumps(report, indent=2) + "\n")


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parent / "tests"))
    import mac_ax as ax
    from fixture_desktop import activate_fixture, wait_for_start

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--commands", action="store_true", help="Probe public mutations and native keyboard event delivery separately")
    parser.add_argument("--grouped-states", action="store_true", help="Observe grouped selection and latent disclosure prerequisites; no adapter acceptance")
    parser.add_argument("--grouped-inputs", action="store_true", help="Probe visible later/nested break center clicks and native keyboard disclosure; selection-preserving disclosure remains unvalidated")
    args = parser.parse_args()
    if args.grouped_inputs and (not args.commands or args.grouped_states):
        parser.error("--grouped-inputs requires --commands and cannot combine with --grouped-states")
    if not args.run:
        parser.error("--run is required for the owned desktop probe")
    if args.grouped_states and not args.commands:
        parser.error("--grouped-states requires --commands")
    if args.grouped_states:
        from PIL import Image, ImageChops
    ax.require_test_input()
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    fixture = BUILD / "hierarchy-probe"
    project = fixture / "Project/Hierarchy.4DProject"
    resources = fixture / "Resources"
    compile_report = json.loads((BUILD / "hierarchy-probe-compile.json").read_text())
    assert compile_report["passed"]
    assert compile_report["preparerSHA256"] == hashlib.sha256((Path(__file__).parent / "prepare_hierarchy_probe.py").read_bytes()).hexdigest()
    for name, expected in compile_report["sources_sha256"].items():
        assert hashlib.sha256((fixture / name).read_bytes()).hexdigest() == expected, name
    for name in ("state.json", "close.json", "closed.json", "error.json", "request.json"):
        (resources / name).unlink(missing_ok=True)
    run_id = (resources / "run-id.txt").read_text()
    def read(name):
        return read_json(resources / name)
    def state():
        error = read("error.json")
        assert not error, error
        value = read("state.json")
        return value if value and value.get("runId") == run_id else None
    report = {"passed": False, "compiled": args.compiled, "runId": run_id,
        "scope": "Native state/geometry probe. No hierarchy accessibility adapter or action acceptance."}
    report["sourceCommit"] = compile_report.get("sourceCommit")
    report["environment"] = {"macOS": platform.mac_ver()[0], "hostArchitecture": platform.machine()}
    report["preparerSHA256"] = compile_report["preparerSHA256"]
    report["preparedSourceSHA256"] = compile_report["sources_sha256"]
    report["driverSHA256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report["compileReportSHA256"] = hashlib.sha256(
        (BUILD / "hierarchy-probe-compile.json").read_bytes()).hexdigest()
    mode = "compiled" if args.compiled else "interpreted"
    prefix = "hierarchy-input-probe-" if args.grouped_inputs else "hierarchy-probe-"
    report_path = BUILD / (prefix + mode + ".json")
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    checks_finished = False
    with (BUILD / (prefix + mode + ".log")).open("w") as log:
        process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D",
            "--project", str(project), "--dataless", "--opening-mode", mode,
            "--webadmin-auto-start", "false"], stdout=log, stderr=log)
        try:
            ready, _ = wait_for_start(process, project, state, BUILD)
            assert ready["compiled"] is args.compiled
            app, window = activate_fixture(process, project, "AX native hierarchy probe")
            report["window"] = {"position": window.read("AXPosition"), "size": window.read("AXSize")}
            diagnostic_hash = compile_report.get("diagnosticNativeSHA256")
            if diagnostic_hash:
                native = fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
                assert hashlib.sha256(native.read_bytes()).hexdigest() == diagnostic_hash
                mapped = subprocess.check_output(
                    ["lsof", "-Fn", "-p", str(process.pid)], text=True).splitlines()
                candidates = {Path(line[1:]).resolve() for line in mapped
                    if line.startswith("n") and line.endswith("AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}
                assert candidates == {native.resolve()}, candidates
                report["diagnosticNativeSHA256"] = diagnostic_hash
                report["uniqueMappedDiagnostic"] = True
            time.sleep(0.5)
            observed = ax.wait_for(state, "Native hierarchy state missing")
            assert observed["beforeA"] == observed["afterA"]
            assert observed["beforeB"] == observed["afterB"]
            def preserved_group(snapshot):
                assert snapshot["beforeGroup"] == snapshot["afterGroup"]
                assert snapshot["groupSentinelBefore"] == snapshot["groupSentinelAfter"]
                assert snapshot["groupSentinelBefore"]["ok"] == 0
            preserved_group(observed)
            assert observed["focus"] == observed["focusAfter"]
            assert observed["okPreserved"]
            topology = observed["topology"]
            assert topology["valid"], topology
            assert len(topology["rows"]) == 62
            branch = topology["rows"][0]
            assert branch["ref"] == 101 and not branch["expanded"]
            nested = branch["topology"]["rows"][0]
            assert nested["ref"] == 201 and nested["expanded"]
            assert [(item["ref"], item["label"]) for item in nested["topology"]["rows"]] == [(-301, "Deep leaf 🎹"), (-302, "")]
            assert branch["topology"]["disclosedCount"] == 4
            assert topology["rows"][1]["topology"]["rows"] == []
            assert observed["grouped"]["levels"] == 3
            report["checks"] = ["Both representations, selection, focus and OK preserved", "All root and latent descendants read without expanding", "Negative references and blank leaf preserved", "Empty branch retained", "Three hierarchy pointers returned"]
            report["state"] = observed
            if diagnostic_hash:
                assert "paintCalls" in observed["native"] and "cellPaints" in observed["native"]
            visited = []
            def tree(element, depth=0):
                if depth > 20 or len(visited) >= 2000 or any(element.same_as(x) for x in visited):
                    return {"truncated": True}
                visited.append(element)
                result = {name: element.read(name) for name in
                    ("AXRole", "AXSubrole", "AXDescription", "AXTitle", "AXValue", "AXIdentifier", "AXPosition", "AXSize")}
                result["actions"] = element.actions()
                result["children"] = [tree(x, depth+1) for x in element.read("AXChildren") or [] if isinstance(x, ax.Element)]
                return result
            report["nativeAX"] = tree(window)
            ax.capture_window(process.pid, BUILD / (prefix + mode + ".png"))
            if args.commands:
                report["commandProbes"] = []
                def command(operation, **payload):
                    identifier = uuid.uuid4().hex
                    (resources / "request.json").write_text(json.dumps({"id": identifier, "operation": operation, **payload}))
                    observed = ax.wait_for(lambda: (value if value and value.get("command", {}).get("id") == identifier else None) if (value := state()) else None,
                                           "Native probe request did not finish: " + operation)
                    time.sleep(0.4)
                    observed = state()
                    assert observed and not observed["command"].get("error")
                    assert observed["beforeA"] == observed["afterA"] and observed["beforeB"] == observed["afterB"]
                    preserved_group(observed)
                    report["commandProbes"].append({"operation": operation, "payload": payload, "state": observed})
                    return observed
                for operation in ("treeExpand", "treeCollapse", "treeSelect", "groupCollapse", "groupExpand", "groupSelect", "treeCollapse", "treeSelectRoot", "focusTree"):
                    command(operation)
                graphics = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
                create = ax.signature(graphics, "CGEventCreateKeyboardEvent", ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool)
                flags = ax.signature(graphics, "CGEventSetFlags", None, ctypes.c_void_p, ctypes.c_uint64)
                post = ax.signature(graphics, "CGEventPostToPid", None, ctypes.c_int, ctypes.c_void_p)
                def native_key(label, key, focus):
                    ax.require_test_input()
                    assert state()["focus"] == focus and app.read("AXFrontmost") is True
                    assert app.read("AXFocusedWindow").same_as(window)
                    before = state()
                    for down in (True, False):
                        event = create(None, key, down); flags(event, 0); post(process.pid, event); ax.release(event)
                    time.sleep(0.7)
                    after = state()
                    entry = {"operation": label, "before": before, "state": after}
                    report["commandProbes"].append(entry)
                    return entry
                tree_baselines = {}
                for label, key in (("nativeRight", 124), ("nativeLeft", 123), ("nativeDown", 125)):
                    tree_baselines[label] = native_key(label, key, "TreeA")
                assert tree_baselines["nativeRight"]["state"]["beforeA"]["rows"][0]["expanded"]
                assert not tree_baselines["nativeLeft"]["state"]["beforeA"]["rows"][0]["expanded"]
                assert tree_baselines["nativeDown"]["state"]["beforeA"]["selected"] == [102]
                for label, expected_event in (("nativeRight", 43), ("nativeLeft", 44), ("nativeDown", 31)):
                    reference = tree_baselines[label]
                    events = reference["state"]["events"][len(reference["before"]["events"]):]
                    assert sum(event["event"] == expected_event for event in events) == 1, (label, events)
                for operation in ("treeCollapse", "treeSelectRoot", "focusTree"):
                    command(operation)
                for operation, baseline in (("treePostRight", "nativeRight"),
                                            ("treePostLeft", "nativeLeft"),
                                            ("treePostDown", "nativeDown")):
                    before = state()
                    assert before["focus"] == "TreeA" and app.read("AXFrontmost") is True
                    observed = command(operation)
                    reference = tree_baselines[baseline]
                    actual_events = observed["events"][len(before["events"]):]
                    expected_events = reference["state"]["events"][len(reference["before"]["events"]):]
                    assert actual_events == expected_events, (operation, actual_events, expected_events)
                    for field in ("selected", "current", "rows"):
                        assert observed["beforeA"][field] == reference["state"]["beforeA"][field], (operation, field)
                    assert observed["beforeB"] == before["beforeB"]
                report["checks"].append("Process-targeted POST KEY matches native tree arrows and original handler sequences")
                for operation in ("groupCollapse", "groupSelectRoot", "focusGrouped"):
                    command(operation)
                for label, key in (("groupNativeRight", 124), ("groupNativeLeft", 123), ("groupNativeDown", 125)):
                    native_key(label, key, "Grouped")
                command("groupCollapse")
                get_pid = ax.signature(ax.AX, "AXUIElementGetPid", ctypes.c_int,
                    ctypes.c_void_p, ctypes.POINTER(ctypes.c_int))
                class Point(ctypes.Structure):
                    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]
                mouse = ax.signature(graphics, "CGEventCreateMouseEvent", ctypes.c_void_p,
                    ctypes.c_void_p, ctypes.c_uint32, Point, ctypes.c_uint32)
                post_mouse = ax.signature(graphics, "CGEventPost", None, ctypes.c_uint32, ctypes.c_void_p)
                clicks = ax.signature(graphics, "CGEventSetIntegerValueField", None,
                    ctypes.c_void_p, ctypes.c_uint32, ctypes.c_longlong)
                for expected_event in (43, 44):
                    before = state()
                    assert before["grouped"]["disclosurePointHit"] == [1, 1]
                    x, y = before["grouped"]["disclosureTestPoint"]
                    wx, wy = window.read("AXPosition")
                    ww, wh = window.read("AXSize")
                    assert wx <= x < wx + ww and wy <= y < wy + wh
                    assert app.read("AXFrontmost") is True and app.read("AXFocusedWindow").same_as(window)
                    owner = ctypes.c_int()
                    hit = ax.system().at_position(x, y)
                    assert get_pid(hit.pointer, ctypes.byref(owner)) == 0 and owner.value == process.pid
                    ax.require_test_input()
                    for kind in (5, 1, 2):
                        event = mouse(None, kind, Point(x, y), 0)
                        flags(event, 0); clicks(event, 1, 1); post_mouse(1, event); ax.release(event)
                        time.sleep(0.1)
                    def target_event(event):
                        return (event["event"] == expected_event and event["name"] == "Grouped"
                            and event["row"] == 1 and event["column"] == 1)
                    after = ax.wait_for(lambda: value if (value := state()) and
                        any(target_event(e) for e in value["events"][len(before["events"]):]) else None,
                        "Grouped mouse disclosure did not run its original handler")
                    events = after["events"][len(before["events"]):]
                    disclosure_events = [e for e in events if e["event"] in (43, 44)]
                    assert len(disclosure_events) == 1 and target_event(disclosure_events[0]), events
                    def leaf_visible(snapshot):
                        frame = next(cell["frame"] for cell in snapshot["grouped"]["coordinates"]
                            if cell["row"] == 1 and cell["column"] == 3)
                        return frame[2] > frame[0] and frame[3] > frame[1]
                    assert leaf_visible(before) is (expected_event == 44)
                    assert leaf_visible(after) is (expected_event == 43)
                    report["commandProbes"].append({"operation": "groupMouseExpand" if expected_event == 43 else "groupMouseCollapse",
                        "point": [x, y], "ownerVerified": True, "before": before, "state": after})
                report["checks"].append("Native grouped mouse disclosure targets the verified break, runs its handler once and changes descendant geometry")
                if args.grouped_states:
                    report["groupedStates"] = {"scope": "Synthetic repeated groups, programmatic selection/disclosure, blank backing row and empty list. No loaded-empty/lazy branch or adapter acceptance.", "snapshots": []}
                    window_list = ax.signature(graphics, "CGWindowListCopyWindowInfo", ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32)
                    dictionary_value = ax.signature(ax.CF, "CFDictionaryGetValue", ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
                    def raw_value(dictionary, name):
                        key = ax.make_string(None, name.encode(), ax.UTF8)
                        try:
                            return dictionary_value(dictionary, key)
                        finally:
                            ax.release(key)
                    def capture_probe_window(path):
                        windows = window_list(1, 0)
                        assert windows
                        candidates = []
                        try:
                            for index in range(ax.array_count(windows)):
                                candidate = ax.array_value(windows, index)
                                def value(name):
                                    pointer = raw_value(candidate, name)
                                    return ax.convert(pointer) if pointer else None
                                if value("kCGWindowOwnerPID") != process.pid or value("kCGWindowLayer") != 0:
                                    continue
                                if value("kCGWindowName") != window.read("AXTitle"):
                                    continue
                                bounds = raw_value(candidate, "kCGWindowBounds")
                                assert bounds
                                x, y, width, height = [ax.convert(raw_value(bounds, key)) for key in ("X", "Y", "Width", "Height")]
                                if (x, y) == report["window"]["position"] and (width, height) == report["window"]["size"]:
                                    candidates.append({"number": int(value("kCGWindowNumber")), "title": value("kCGWindowName"), "position": [x, y], "size": [width, height], "pidVerified": True})
                            assert len(candidates) == 1, candidates
                            selected = candidates[0]
                            subprocess.run(["/usr/sbin/screencapture", "-x", "-o", "-l", str(selected["number"]), str(path)], check=True, timeout=10)
                            assert window.read("AXPosition") == report["window"]["position"] and window.read("AXSize") == report["window"]["size"]
                            return selected
                        finally:
                            ax.release(windows)
                    def grouped(operation, **payload):
                        before = state()
                        observed = command(operation, **payload)
                        assert observed["beforeA"] == before["beforeA"] and observed["beforeB"] == before["beforeB"]
                        snapshot = observed["afterGroup"]
                        index = len(report["groupedStates"]["snapshots"])
                        focused = app.read("AXFocusedWindow")
                        assert app.read("AXFrontmost") is True and isinstance(focused, ax.Element) and focused.same_as(window)
                        assert window.read("AXPosition") == report["window"]["position"] and window.read("AXSize") == report["window"]["size"]
                        image_path = BUILD / ("grouped-state-" + mode + "-" + str(index) + ".png")
                        captured_window = capture_probe_window(image_path)
                        report["groupedStates"]["snapshots"].append({"operation": operation, "payload": payload, "state": snapshot,
                            "image": image_path.name, "imageSHA256": hashlib.sha256(image_path.read_bytes()).hexdigest(), "capturedWindow": captured_window})
                        return snapshot
                    def image_difference(first, second, allowed_rows=()):
                        images = [Image.open(BUILD / report["groupedStates"]["snapshots"][index]["image"]).convert("RGBA") for index in (first, second)]
                        assert images[0].size == images[1].size
                        wx, wy = report["window"]["position"]; ww, wh = report["window"]["size"]
                        sx, sy = images[0].width / ww, images[0].height / wh
                        assert sx == sy
                        regions = []
                        for row in allowed_rows:
                            cell = next(c for c in report["groupedStates"]["snapshots"][first]["state"]["coordinates"] if c["row"] == row and c["column"] == 1)
                            assert cell["positive"] and cell["hit"] == [1, row]
                            l, t, r, b = cell["screenFrame"]
                            rect = [(l-wx)*sx, (t-wy)*sy, (r-wx)*sx, (b-wy)*sy]
                            assert 0 <= rect[0] < rect[2] <= images[0].width and 0 <= rect[1] < rect[3] <= images[0].height
                            regions.append(rect)
                        changed = 0
                        for index, (a, b) in enumerate(zip(images[0].get_flattened_data(), images[1].get_flattened_data())):
                            if a != b:
                                changed += 1
                                if regions:
                                    x, y = index % images[0].width, index // images[0].width
                                    assert any(l <= x < r and t <= y < b for l, t, r, b in regions), (x, y, regions)
                        return {"changedPixels": changed, "differenceBounds": ImageChops.difference(*images).convert("RGB").getbbox(), "allowedBreakRegions": regions, "wholeWindow": True, "mask": False}
                    def frame(snapshot, row, column):
                        return next(cell["frame"] for cell in snapshot["coordinates"]
                            if cell["row"] == row and cell["column"] == column)
                    def positive(rect):
                        return rect[2] > rect[0] and rect[3] > rect[1]
                    repeated = grouped("groupCase", name="repeated")
                    assert repeated["case"] == "repeated" and repeated["rows"] == 8
                    assert repeated["levels"][0]["values"] == ["A", "A", "A", "B", "B", "A", "A", "C"]
                    assert repeated["keys"] == list(range(1, 9)) and not any(repeated["selection"])
                    assert all(length == 8 for length in repeated["arrayLengths"].values())
                    assert repeated["focus"] == "Close" and positive(frame(repeated, 1, 3))
                    no_selection = grouped("groupCollapseAll")
                    baseline_index = len(report["groupedStates"]["snapshots"])-1
                    break_selected = grouped("groupSelectRoot")
                    first_index = len(report["groupedStates"]["snapshots"])-1
                    later = grouped("groupSelectLaterBreak")
                    later_index = len(report["groupedStates"]["snapshots"])-1
                    grouped("groupCase", name="repeated")
                    reset = grouped("groupCollapseAll")
                    reset_index = len(report["groupedStates"]["snapshots"])-1
                    assert no_selection == reset
                    assert all(s["focus"] == "Close" and s["scroll"] == no_selection["scroll"] for s in (break_selected, later, reset))
                    report["groupedStates"]["selectionImages"] = {
                        "baselineToFirst": image_difference(baseline_index, first_index, (1,)),
                        "baselineToLater": image_difference(baseline_index, later_index, (6,)),
                        "firstToLater": image_difference(first_index, later_index, (1, 6)),
                        "baselineToReset": image_difference(baseline_index, reset_index)}
                    assert report["groupedStates"]["selectionImages"]["baselineToFirst"]["changedPixels"] > 0
                    assert report["groupedStates"]["selectionImages"]["baselineToLater"]["changedPixels"] > 0
                    assert report["groupedStates"]["selectionImages"]["firstToLater"]["changedPixels"] > 0
                    assert report["groupedStates"]["selectionImages"]["baselineToReset"]["changedPixels"] == 0
                    grouped("groupSelectRoot")
                    break_expanded = grouped("groupExpandAll")
                    assert positive(frame(break_expanded, 1, 3))
                    leaves_selected = grouped("groupSelectFirstLeaves")
                    expected_selection = [True] * 3 + [False] * 5
                    assert leaves_selected["selection"] == expected_selection
                    assert len(break_selected["selection"]) == 8
                    report["groupedStates"]["firstBreakMembership"] = [1, 2, 3]
                    report["groupedStates"]["noSelectionVersusFirstBreakReadbackEqual"] = no_selection == break_selected
                    report["groupedStates"]["laterBreakMembership"] = [6, 7]
                    report["groupedStates"]["firstVersusLaterBreakReadbackEqual"] = break_selected == later
                    report["groupedStates"]["breakVersusAllLeavesReadbackEqual"] = break_expanded == leaves_selected
                    report["groupedStates"]["selectionObservationEqual"] = all(break_expanded[key] == leaves_selected[key]
                        for key in ("selection", "selectionSlotZero", "levels"))
                    report["groupedStates"]["expandedSelectionComparisonScope"] = "Select first break then expand all versus select backing rows 1, 2 and 3. Retained break highlight after expansion was not separately verified."
                    report["checks"].append("Repeated-label first-break and same-member leaf command sequences compared without assuming selection flags")
                    grouped("groupCase", name="repeated")
                    nested_collapsed = grouped("groupCollapseNested")
                    assert not positive(frame(nested_collapsed, 1, 3)) and positive(frame(nested_collapsed, 1, 2))
                    collapsed_parent_and_child = grouped("groupCollapse")
                    reopened_collapsed_child = grouped("groupExpand")
                    assert positive(frame(reopened_collapsed_child, 1, 2)) and not positive(frame(reopened_collapsed_child, 1, 3))
                    nested_expanded = grouped("groupExpandNested")
                    assert positive(frame(nested_expanded, 1, 3))
                    collapsed_parent_expanded_child = grouped("groupCollapse")
                    assert not positive(frame(collapsed_parent_and_child, 1, 3)) and not positive(frame(collapsed_parent_expanded_child, 1, 3))
                    report["groupedStates"]["latentNestedReadbackEqual"] = collapsed_parent_and_child == collapsed_parent_expanded_child
                    reopened_expanded_child = grouped("groupExpand")
                    assert positive(frame(reopened_expanded_child, 1, 3))
                    report["groupedStates"]["oppositeLatentChildStatesConfirmedByReopen"] = True
                    report["checks"].append("Paired collapsed ancestors retain known opposite latent child states; public readback ambiguity recorded")
                    grouped("groupCase", name="repeated")
                    hidden = grouped("groupHideFirst")
                    assert hidden["control"] == [1] * 3 + [0] * 5
                    assert not positive(frame(hidden, 1, 1))
                    shown = grouped("groupShowAll")
                    assert shown["control"] == [0] * 8 and positive(frame(shown, 1, 3))
                    report["checks"].append("Hidden-descendant controls remain distinct from collapsed state")
                    blank = grouped("groupCase", name="placeholder")
                    assert blank["rows"] == 1 and blank["levels"][1]["values"] == [""] and blank["levels"][2]["values"] == [""]
                    empty = grouped("groupCase", name="empty")
                    assert empty["rows"] == 0 and empty["coordinates"] == [] and not empty["selection"]
                    assert all(length == 0 for length in empty["arrayLengths"].values())
                    report["checks"].append("Blank backing row and empty list read safely without claiming lazy or loaded-empty branches")
                    report["checks"].append("Full grouped reader preserves independently captured selection, focus, scroll and OK")
                ax.capture_window(process.pid, BUILD / (("hierarchy-input-commands-" if args.grouped_inputs else "hierarchy-commands-") + mode + ".png"))
            if args.grouped_inputs:
                report["groupedInputScope"] = "Exploratory native later/nested group keyboard routing. No adapter or VoiceOver acceptance."
                command("groupCase", name="repeated")
                command("groupCollapseAll")
                reference = state()
                def sample_cell(snapshot, row, column):
                    return next(c for c in snapshot["afterGroup"]["coordinates"] if c["row"] == row and c["column"] == column)
                def is_positive(snapshot, row, column):
                    return sample_cell(snapshot, row, column)["positive"]
                def group_click(row, column):
                    before = state()
                    cell = sample_cell(before, row, column)
                    assert cell["positive"] and cell["hit"] == [column, row], cell
                    l, t, r, b = cell["screenFrame"]
                    x, y = (l+r)/2, (t+b)/2
                    wx, wy = window.read("AXPosition"); ww, wh = window.read("AXSize")
                    assert wx <= x < wx+ww and wy <= y < wy+wh
                    assert app.read("AXFrontmost") is True and app.read("AXFocusedWindow").same_as(window)
                    owner = ctypes.c_int()
                    hit = ax.system().at_position(x, y)
                    assert get_pid(hit.pointer, ctypes.byref(owner)) == 0 and owner.value == process.pid
                    def send_mouse(kind):
                        event = mouse(None, kind, Point(x, y), 0)
                        try:
                            flags(event, 0); clicks(event, 1, 1); post_mouse(1, event)
                        finally:
                            ax.release(event)
                    send_mouse(5)
                    time.sleep(0.1)
                    fresh = state()
                    assert sample_cell(fresh,row,column) == cell
                    assert window.read("AXPosition") == report["window"]["position"] and window.read("AXSize") == report["window"]["size"]
                    assert app.read("AXFrontmost") is True and app.read("AXFocusedWindow").same_as(window)
                    hit = ax.system().at_position(x,y)
                    assert get_pid(hit.pointer,ctypes.byref(owner)) == 0 and owner.value == process.pid
                    ax.require_test_input()
                    try:
                        send_mouse(1)
                        time.sleep(0.1)
                    finally:
                        send_mouse(2)
                    after = ax.wait_for(lambda: value if (value := state()) and value["focus"] == "Grouped" and len(value["events"]) > len(before["events"]) else None, "Native group click did not finish")
                    events = after["events"][len(before["events"]):]
                    target_clicks = [e for e in events if e["event"] == 4]
                    assert len(target_clicks) == 1 and target_clicks[0]["name"] == "Grouped" and target_clicks[0]["row"] == row and target_clicks[0]["column"] == column, events
                    assert not any(e["event"] in (43,44) for e in events), events
                    assert after["beforeA"] == before["beforeA"] == reference["beforeA"] and after["beforeB"] == before["beforeB"] == reference["beforeB"]
                    for field in ("levels","keys","control","arrayLengths"):
                        assert after["afterGroup"][field] == before["afterGroup"][field] == reference["afterGroup"][field]
                    preserved_group(after)
                    assert before["afterGroup"]["coordinates"] == after["afterGroup"]["coordinates"]
                    report["commandProbes"].append({"operation": "nativeGroupClick", "target": [column, row], "point": [x,y], "ownerVerified": True, "before": before, "state": after})
                    return after
                def verify_key(label, key, expected_event, row, column, opened):
                    before = state()
                    for member in (6,7):
                        assert is_positive(before,member,column) is (not opened)
                    ancestor_column = column-1
                    ancestor_before = [sample_cell(before,member,ancestor_column) for member in (6,7)]
                    assert all(c["positive"] for c in ancestor_before)
                    entry = native_key(label, key, "Grouped")
                    events = entry["state"]["events"][len(entry["before"]["events"]):]
                    disclosure = [e for e in events if e["event"] in (43,44)]
                    assert len(disclosure) == 1 and disclosure[0]["event"] == expected_event and disclosure[0]["name"] == "Grouped", events
                    for member in (6,7):
                        assert is_positive(entry["state"],member,column) is opened
                    assert [sample_cell(entry["state"],member,ancestor_column) for member in (6,7)] == ancestor_before
                    for other in (1,4,8):
                        assert not is_positive(entry["state"], other, 2)
                    assert entry["state"]["beforeA"] == reference["beforeA"] and entry["state"]["beforeB"] == reference["beforeB"]
                    assert entry["state"]["afterGroup"]["levels"] == reference["afterGroup"]["levels"]
                    assert entry["state"]["afterGroup"]["keys"] == reference["afterGroup"]["keys"]
                    preserved_group(entry["state"])
                    report["checks"].append(label + " changes its intended branch and runs one native disclosure handler")
                group_click(6,1)
                verify_key("laterRootRight",124,43,6,2,True)
                assert not is_positive(state(),6,3)
                group_click(6,2)
                verify_key("laterNestedRight",124,43,6,3,True)
                verify_key("laterNestedLeft",123,44,6,3,False)
                group_click(6,1)
                verify_key("laterRootLeft",123,44,6,2,False)
            checks_finished = True
        except BaseException as error:
            report["failure"] = repr(error)
            raise
        finally:
            finish_run(process, resources, run_id, report, report_path, checks_finished)
    assert report["passed"], report.get("shutdownErrors") or report.get("finalError") or report["closed"]
    print("PASS: native probe checks and owned-process shutdown")


if __name__ == "__main__":
    main()
