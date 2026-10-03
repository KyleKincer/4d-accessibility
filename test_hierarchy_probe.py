#!/usr/bin/env python3
"""Record native hierarchy state and AX output without claiming an adapter."""

import argparse
import ctypes
import uuid
import hashlib
import json
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
    args = parser.parse_args()
    if not args.run:
        parser.error("--run is required for the owned desktop probe")
    ax.require_test_input()
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    fixture = BUILD / "hierarchy-probe"
    project = fixture / "Project/Hierarchy.4DProject"
    resources = fixture / "Resources"
    compile_report = json.loads((BUILD / "hierarchy-probe-compile.json").read_text())
    assert compile_report["passed"]
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
    report["driverSHA256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report["compileReportSHA256"] = hashlib.sha256(
        (BUILD / "hierarchy-probe-compile.json").read_bytes()).hexdigest()
    mode = "compiled" if args.compiled else "interpreted"
    report_path = BUILD / ("hierarchy-probe-" + mode + ".json")
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    checks_finished = False
    with (BUILD / ("hierarchy-probe-" + mode + ".log")).open("w") as log:
        process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D",
            "--project", str(project), "--dataless", "--opening-mode", mode,
            "--webadmin-auto-start", "false"], stdout=log, stderr=log)
        try:
            ready, _ = wait_for_start(process, project, state, BUILD)
            assert ready["compiled"] is args.compiled
            app, window = activate_fixture(process, project, "AX native hierarchy probe")
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
            ax.capture_window(process.pid, BUILD / ("hierarchy-probe-" + mode + ".png"))
            if args.commands:
                report["commandProbes"] = []
                def command(operation):
                    identifier = uuid.uuid4().hex
                    (resources / "request.json").write_text(json.dumps({"id": identifier, "operation": operation}))
                    observed = ax.wait_for(lambda: (value if value and value.get("command", {}).get("id") == identifier else None) if (value := state()) else None,
                                           "Native probe request did not finish: " + operation)
                    time.sleep(0.4)
                    observed = state()
                    assert observed and not observed["command"].get("error")
                    assert observed["beforeA"] == observed["afterA"] and observed["beforeB"] == observed["afterB"]
                    report["commandProbes"].append({"operation": operation, "state": observed})
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
                ax.capture_window(process.pid, BUILD / ("hierarchy-commands-" + mode + ".png"))
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
