#!/usr/bin/env python3
"""Validate the development grouped provider through live 4D and AX.

Native commands in the owned fixture change disclosure. Leaves are selected from
the keyboard through the list box's own events, by AX and by VoiceOver navigation.
This does not accept AX disclosure, editing, lazy data, hidden rows or Symphony workflows.
"""
import argparse
import ctypes as c
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
import uuid

from build_component import BUILD, ROOT, sha
from test_hierarchy_probe import finish_run, read_json
from prepare_hierarchy_probe import canonical_sources

TITLE = "AX native hierarchy probe"
DRIVER_SOURCES = ("test_grouped_outline.py", "test_hierarchy_probe.py", "build_component.py", "tests/mac_ax.py", "tests/fixture_desktop.py",
                  "tests/voiceover.py", "tests/ReadScreen.swift")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    parser.add_argument("--native-baseline", action="store_true", help="Compare unchanged native UI with the owned plugin temporarily absent")
    args = parser.parse_args()
    if args.native_baseline and args.voiceover:
        parser.error("Native baseline cannot run VoiceOver against the absent provider")
    mode = "compiled" if args.compiled else "interpreted"
    path = BUILD / ("grouped-outline-" + mode + ("-baseline" if args.native_baseline else "-voiceover" if args.voiceover else "") + ".json")
    report = {"passed": False, "checks": [], "states": [], "compiled": args.compiled, "scope": __doc__.strip()}
    path.write_text(json.dumps(report) + "\n")
    report["driverSourceSHA256"] = {name: sha(ROOT / name) for name in DRIVER_SOURCES}
    report["environment"] = {"macOS": platform.mac_ver()[0], "hostArchitecture": platform.machine()}
    sys.path.insert(0, str(ROOT / "tests"))
    import mac_ax as ax
    from fixture_desktop import activate_fixture, capture_fixture_window, wait_for_start
    ax.require_test_input()
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    fixture = BUILD / "hierarchy-probe"
    project = fixture / "Project/Hierarchy.4DProject"
    resources = fixture / "Resources"
    compile_path = BUILD / "hierarchy-probe-compile.json"
    prepared = json.loads(compile_path.read_text())
    assert prepared["passed"] and prepared["bridge"]
    assert prepared["canonicalSourceSHA256"] == canonical_sources()
    assert prepared["preparerSHA256"] == sha(ROOT / "prepare_hierarchy_probe.py")
    assert {str(p.relative_to(fixture)): sha(p)
            for directory in (fixture / "Libraries", fixture / "Project/DerivedData/CompiledCode")
            for p in directory.rglob("*") if p.is_file()} == prepared["compiledHostSHA256"]
    for name, expected in prepared["sources_sha256"].items():
        assert sha(fixture / name) == expected, name
    native = fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
    component = fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"
    assert sha(native) == prepared["nativeSHA256"] and sha(component) == prepared["componentSHA256"]
    package = component.parent
    assert {str(p.relative_to(package)): sha(p) for p in package.rglob("*") if p.is_file()} == prepared["componentPackageSHA256"]
    for artifact in ("nativeSourceSHA256", "componentSourceSHA256"):
        for name, expected in prepared[artifact].items():
            assert sha(ROOT / name) == expected, name
    report.update({"preparedSourceSHA256": prepared["sources_sha256"], "compileReportSHA256": sha(compile_path),
                   "nativeSHA256": sha(native), "componentSHA256": sha(component), "driverSHA256": sha(Path(__file__))})
    report.update({name: prepared[name] for name in ("canonicalSourceSHA256", "nativeSourceSHA256", "componentSourceSHA256", "componentPackageSHA256")})
    report["compiledHostSHA256"] = prepared["compiledHostSHA256"]
    if prepared.get("subforms"):
        (resources / "launch-variant.txt").write_text("standalone")
    if prepared.get("disclosure"):
        (resources / "read-only.txt").write_text("The owning fixture has no disclosure controller for this run.\n")
    for name in ("state.json", "close.json", "closed.json", "error.json", "request.json"):
        (resources / name).unlink(missing_ok=True)
    run_id = (resources / "run-id.txt").read_text()
    report["runId"] = run_id

    def state():
        assert not (resources / "error.json").exists(), read_json(resources / "error.json")
        value = read_json(resources / "state.json")
        return value if value and value.get("runId") == run_id else None

    def check(condition, message):
        assert condition, message
        report["checks"].append(message)
        print("PASS:", message, flush=True)

    def attribute(element, name):
        key = ax.make_string(None, name.encode(), ax.UTF8)
        value = c.c_void_p()
        try:
            error = ax.copy_attribute(element.pointer, key, c.byref(value))
            return error, ax.convert(value.value) if value.value else None
        finally:
            if value.value:
                ax.release(value.value)
            ax.release(key)

    finished = False
    vo = heard = None
    bundle = fixture / "Plugins/AccessibilityBridge.bundle"
    held_bundle = BUILD / ("grouped-held-plugin-" + uuid.uuid4().hex + ".bundle")
    with (BUILD / ("grouped-outline-" + mode + ".log")).open("w") as log:
        process = None
        try:
            if args.native_baseline:
                bundle.rename(held_bundle)
            process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
                                        "--dataless", "--opening-mode", mode, "--webadmin-auto-start", "false"], stdout=log, stderr=log)
            report["pid"] = process.pid
            ready, report["modeNoticeAcknowledged"] = wait_for_start(process, project, state, BUILD)
            check(ready["compiled"] is args.compiled, "actual 4D execution mode matches the requested mode")
            app, window = activate_fixture(process, project, TITLE)
            report["window"] = {"title": window.read("AXTitle"), "position": window.read("AXPosition"), "size": window.read("AXSize")}

            def outline():
                pending = [window]
                while pending:
                    item = pending.pop()
                    if item.read("AXRole") == "AXOutline" and item.read("AXDescription") == "Grouped items":
                        return item
                    if item.read("AXRole") not in ("AXTable", "AXOutline"):
                        pending.extend(item.read("AXChildren") or [])

            if args.native_baseline:
                check(state()["info"] == {"ok": False, "error": "dependencyUnavailable", "native": False, "component": True},
                      "native baseline independently confirms the plugin is absent")
                check(outline() is None, "native baseline exposes no development outline")
            else:
                table = ax.wait_for(outline, "Development outline was not published", timeout=30)
                check("; nativeOutlines 1;" in state()["info"]["nativeStatus"], "loaded native package advertises the outline capability")
                check(any(area.get("registered") and area.get("configured") for area in state()["bridge"]["areas"]),
                      "parent lifecycle area starts the configured provider")

            def command(operation, **payload):
                identifier = uuid.uuid4().hex
                temporary = resources / "request.tmp"
                temporary.write_text(json.dumps({"id": identifier, "operation": operation, **payload}))
                temporary.replace(resources / "request.json")
                value = ax.wait_for(lambda: s if (s := state()) and s["command"]["id"] == identifier else None,
                                    "Native fixture command did not finish")
                time.sleep(0.3)
                value = state()
                assert value and value["command"]["id"] == identifier and not value["command"].get("error")
                assert value["capturePreservesOK"] and value["modelSentinelBefore"] == value["modelSentinelAfter"]
                assert value["beforeGroup"] == value["afterGroup"] and value["groupSentinelBefore"] == value["groupSentinelAfter"]
                report["states"].append({"operation": operation, "payload": payload, "state": value})
                image = BUILD / ("grouped-outline-" + mode + "-" + identifier + ".png")
                assert app.read("AXFrontmost") and app.read("AXFocusedWindow").same_as(window)
                captured = capture_fixture_window(process, window, image)
                report["states"][-1]["image"] = {"path": image.name, "sha256": sha(image), "capturedWindow": captured}
                return value

            def rows(current):
                return [row for start in range(0, current.count("AXRows"), 16)
                        for row in current.slice("AXRows", start, min(16, current.count("AXRows") - start))]

            retained = None
            for kind, count, levels in (("singleText", 12, {0, 1}), ("singleDate", 12, {0, 1}), ("repeated", 17, {0, 1, 2})):
                command("groupCase", name=kind)
                command("groupExpandAll")
                if args.native_baseline:
                    command("groupCollapseAll")
                    command("groupExpandAll")
                    check(True, kind + " native baseline captures the same original disclosure sequence")
                    continue
                table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == count else None,
                                    "Disclosed hierarchy did not publish")
                current_rows = rows(table)
                check({row.read("AXDisclosureLevel") for row in current_rows} == levels,
                      kind + " exposes exact native group and leaf levels")
                groups = [row for row in current_rows if attribute(row, "AXDisclosing")[1] is not None]
                roots = [row for row in groups if row.read("AXDisclosureLevel") == 0]
                check(len(roots) == 4 and len({row.read("AXIdentifier") for row in roots}) == 4,
                      kind + " repeated native labels have distinct group identities")
                check(all(row.read("AXParent").same_as(table) for row in current_rows), kind + " structural row parents remain the outline")
                leaves = [row for row in current_rows if attribute(row, "AXDisclosing")[1] is None]
                check(all(not row.is_settable("AXSelected") for row in groups) and all(row.is_settable("AXSelected") for row in leaves)
                      and table.is_settable("AXSelectedRows"),
                      kind + " leaves are selectable and group rows, which have no selection element, are not")
                check(all("AXPress" not in row.actions() and not row.is_settable("AXDisclosing") for row in groups),
                      kind + " disclosure without an application controller is not advertised")
                if kind in ("singleText", "repeated"):
                    # A leaf is selected from the keyboard through the list box's own events: the first
                    # leaf from the one below it, a later leaf from the one above, and the first leaf of
                    # the next group across the group row between them.
                    targets = [leaves[0], leaves[1], next(row for row in leaves[1:] if not row.read("AXDisclosedByRow").same_as(leaves[0].read("AXDisclosedByRow")))]
                    for number, target in enumerate(targets):
                        before = len(state()["events"])
                        identifier = target.read("AXIdentifier")
                        check(target.set_boolean("AXSelected", True) == 0, kind + f" selecting leaf {number + 1} is accepted")
                        value = ax.wait_for(lambda: v if (v := state()) and any(e["event"] == 31 for e in v["events"][before:]) and
                                            sum(v["afterGroup"]["selection"]) == 1 and
                                            any(r.read("AXSelected") is True and r.read("AXIdentifier") == identifier for r in rows(outline())) else None,
                                            "Leaf selection did not run or publish", timeout=15)
                        selected = value["afterGroup"]["selection"].index(True)
                        check(identifier.endswith("/row/l%3A" + str(value["afterGroup"]["keys"][selected])),
                              kind + f" leaf {number + 1} is the one selected array element, through On Selection Change")
                headers = table.read("AXColumnHeaderUIElements") or []
                check(headers and all("AXScrollToVisible" not in header.actions() and "AXPress" not in header.actions() for header in headers),
                      kind + " headers omit unsupported reveal and activation actions")
                first = current_rows[0]
                first_cell = table.cell(0, 0)
                check(first_cell.read("AXValue") and first_cell.read("AXValue") != "Loading" and len(first.read("AXChildren")) == 1,
                      kind + " group label is immediate and has one cell")
                check(first_cell.read("AXSize")[0] == first.read("AXSize")[0] and first.read("AXSize")[0] > 500,
                      kind + " group geometry spans the native row")
                for group in groups:
                    for child in group.read("AXDisclosedRows") or []:
                        check(child.read("AXDisclosedByRow").same_as(group) and child.read("AXDisclosureLevel") == group.read("AXDisclosureLevel") + 1,
                              kind + " disclosure relation identifies the exact immediate parent")
                last = current_rows[-1]
                last_cell = table.cell(2, count - 1)
                ax.wait_for(lambda: last_cell.read("AXValue") == "Leaf 8", "Final leaf value did not arrive")
                check(last.read("AXIndex") == count - 1 and last_cell.read("AXValue") == "Leaf 8",
                      kind + " final disclosed offscreen leaf retains its logical index and value")
                if kind.startswith("single"):
                    leaf_index = next(i for i, row in enumerate(current_rows) if row.read("AXDisclosureLevel") == 1)
                    blank = table.cell(0, leaf_index)
                    ax.wait_for(lambda: blank.read("AXValue") == "", "Native blank hierarchy leaf did not publish")
                    check(blank.read("AXValue") == "", kind + " first leaf column preserves the native blank value")
                if retained:
                    check(retained.read("AXRole") is None, kind + " changing hierarchy binding retires earlier row handles")
                retained = last
                root_ids = [row.read("AXIdentifier") for row in roots]
                command("groupCollapseAll")
                table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == 4 else None, "Collapse did not publish")
                check([row.read("AXIdentifier") for row in rows(table)] == root_ids and
                      all(row.read("AXDisclosing") is False and not row.read("AXDisclosedRows") for row in rows(table)),
                      kind + " collapse retains group identity and removes disclosed descendants")
                check(last.read("AXRole") is None, kind + " collapse retires retained leaf handles")
                command("groupExpandAll")
                table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == count else None, "Reopen did not publish")
                check(not rows(table)[-1].same_as(last), kind + " reopening requires fresh descendant handles")

            value = state()
            check("controlType" not in value["afterGroup"] and value["capture"]["ok"]
                  and value["capture"]["snapshot"]["flags"] == [0] * 8 and value["outline"]["ok"],
                  "absent native row-control array captures successfully with zero flags")
            if not args.native_baseline:
                check(table.cell(0, 0).read("AXValue") == "A", "hierarchy without row-control array retains native group labels")
            value = command("groupControlRestore")
            check(value["afterGroup"]["controlType"] == 16 and value["capture"]["ok"],
                  "attaching the row-control array preserves accepted capture")
            if not args.native_baseline:
                table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == 17 else None,
                                    "Attached row-control array did not publish")
                fault_state = command("groupFaultBinding")
                check([item["fault"] for item in fault_state["bindingFaults"]] ==
                      ["key", "keyType", "hierarchy", "selection", "missingHierarchy", "missingKey", "missingSelection", "missingControl", "controlType", "controlNull"]
                      and all(item["rejected"] and item["preservesOK"] and item["preservesState"] for item in fault_state["bindingFaults"]),
                      "stale or incomplete caller bindings reject while preserving sampled OK, focus, selection and scroll")
                for operation, message in (("groupFormatNested", "Formatted"), ("groupProtectNested", "Protected"), ("groupHideFirst", "Hidden")):
                    previous = table
                    previous_cell = table.cell(0, 0)
                    value = command(operation)
                    check(not value["capture"]["ok"] and message in value["capture"]["message"], operation + " rejects unavailable native caption authority")
                    ax.wait_for(lambda: outline() is None, "Rejected grouped binding retained its native outline")
                    check(previous.read("AXRole") is None and previous_cell.read("AXRole") is None, operation + " retires retained outline and cell handles")
                    command("groupRestoreCaption")
                    command("groupShowAll")
                    command("groupCase", name="repeated")
                    table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == 17 else None, "Grouped provider did not recover")
                    check(not table.same_as(previous), operation + " recovers with fresh outline handles")
                previous_group = rows(table)[0]
                value = command("groupCaseVariants")
                level = value["capture"]["snapshot"]["levels"][0]
                model = value["outline"]
                parent_one = model["outline"][model["outline"]["l:1"]["parent"]]["parent"]
                parent_two = model["outline"][model["outline"]["l:2"]["parent"]]["parent"]
                check(value["capture"]["ok"] and model["ok"] and level["values"][0] != level["values"][1]
                      and level["frames"][0] != level["frames"][1] and parent_one != parent_two
                      and model["outline"][parent_one]["label"] == "A" and model["outline"][parent_two]["label"] == "a",
                      "case variants follow the native partition and retain exact distinct captions")
                table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == 20 else None, "Native case-variant partition did not publish")
                check(previous_group.read("AXRole") is None, "changed group membership retires the previous group handle")
                command("groupCase", name="repeated")
                table = ax.wait_for(lambda: t if (t := outline()) and t.count("AXRows") == 17 else None, "Original grouped partition did not recover")

            if args.voiceover:
                import voiceover_session as vos
                assert not vos.running(), "Existing VoiceOver session belongs to the user"
                heard = vos.Listener()
                vos.start()
                heard.start()
                vo = vos
                # Keys reach whatever is frontmost; never post one into another application.
                vos.set_guard(vos.guard_frontmost(process.pid, ax))
                if app.read("AXFrontmost") is not True:
                    app.set_boolean("AXFrontmost", True)
                ax.wait_for(lambda: app.read("AXFrontmost") is True, "Fixture did not regain foreground", timeout=10)
                time.sleep(2)

                def say(key, modifiers=vos.VO):
                    mark = heard.mark()
                    vos.key(key, modifiers)
                    time.sleep(1.2)
                    return " ".join(p for _, p in heard.since(mark))

                # VoiceOver starts on the last control; search right, then left, for the outline.
                caption = say("home")
                spoken = [caption]
                for direction in ("right", "left"):
                    for _ in range(12):
                        if "Grouped items" in caption:
                            break
                        caption = say(direction)
                        spoken.append(caption)
                report["entryCaption"] = caption
                report["entrySpeech"] = spoken
                check("Grouped items" in caption, "VoiceOver reaches the actual 4D grouped provider")
                captions = [say("down", vos.VO + ("shift",))]
                for _ in range(12):
                    captions.append(say("right"))
                text = " ".join(captions)
                check(any("shared" in caption and "level 1" in caption for caption in captions) and
                      any("Leaf 1" in caption and "level 2" in caption for caption in captions),
                      "VoiceOver reads native nested labels, leaf values and levels")
                check("not responding" not in text.lower(), "VoiceOver remains responsive")
                caption = say("end")
                if "Leaf 8" not in caption:
                    final_cell = table.cell(2, table.count("AXRows") - 1)
                    report["initialEndAXValue"] = final_cell.read("AXValue")
                    ax.wait_for(lambda: final_cell.read("AXValue") == "Leaf 8", "Final VoiceOver cell value did not load", timeout=10)
                    report["loadedEndAXValue"] = final_cell.read("AXValue")
                    caption = ax.wait_for(lambda: p if "Leaf 8" in (p := vos.last_phrase()) else None,
                                          "VoiceOver did not announce the loaded final leaf", timeout=10)
                    report["loadedEndCaption"] = caption
                check("Leaf 8" in caption, "VoiceOver End reaches the last disclosed leaf")
                # VoiceOver selects an outline row as its cursor reaches it; for a leaf that runs
                # through the list box's own events, like the keyboard.
                selected_before = state()["afterGroup"]["selection"].index(True) if True in state()["afterGroup"]["selection"] else None
                before = len(state()["events"])
                caption = say("up")
                check("Leaf 7" in caption, "VoiceOver moves to the previous leaf")
                value = ax.wait_for(lambda: v if (v := state()) and any(e["event"] == 31 for e in v["events"][before:]) and
                                    sum(v["afterGroup"]["selection"]) == 1 and v["afterGroup"]["selection"].index(True) != selected_before else None,
                                    "VoiceOver did not select the leaf it reached", timeout=15)
                key = value["afterGroup"]["keys"][value["afterGroup"]["selection"].index(True)]
                check(ax.wait_for(lambda: any(r.read("AXSelected") is True and r.read("AXIdentifier").endswith("/row/l%3A" + str(key)) for r in rows(outline())),
                                  "Leaf selection not published", timeout=10),
                      "the leaf VoiceOver reaches is selected through the list box's own On Selection Change and published")
                report["speech"] = [p for _, p in heard.since(0)]
                heard.stop()
                vos.stop()
            report["finalState"] = state()
            check(report["driverSourceSHA256"] == {name: sha(ROOT / name) for name in DRIVER_SOURCES}
                  and prepared["canonicalSourceSHA256"] == canonical_sources(), "canonical helpers and desktop driver sources stay unchanged during acceptance")
            for artifact in ("nativeSourceSHA256", "componentSourceSHA256"):
                assert all(sha(ROOT / name) == expected for name, expected in prepared[artifact].items())
            finished = True
        except BaseException as error:
            report["failure"] = repr(error)
            raise
        finally:
            # Stop the listener first: its AppleScript polling would relaunch VoiceOver.
            if heard:
                heard.stop()
            if vo and vo.running():
                try:
                    vo.stop()
                except BaseException as error:
                    report["voiceoverCleanupFailure"] = repr(error)
                    finished = False
            if process:
                finish_run(process, resources, run_id, report, path, finished)
            if args.native_baseline:
                try:
                    if held_bundle.exists():
                        assert held_bundle.is_dir() and not bundle.exists()
                        held_bundle.rename(bundle)
                    assert sha(native) == prepared["nativeSHA256"]
                    report["packageRestored"] = True
                except BaseException as error:
                    report["packageRestoreFailure"] = repr(error)
                    report["passed"] = False
                path.write_text(json.dumps(report, indent=2) + "\n")
    assert report["passed"]


if __name__ == "__main__":
    main()
