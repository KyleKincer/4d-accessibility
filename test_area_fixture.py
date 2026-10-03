#!/usr/bin/env python3
"""Exercise area-owned root/child lifecycle through the external AX interface."""
import argparse
import json
import subprocess
import sys
import time
from prepare_area_fixture import BUILD, FIXTURE, ROOT, TITLE
from build_component import sha

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run the owned 4D desktop under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Read and activate the compound form through VoiceOver")
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error("--run and Accessibility permission are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the owned fixture")
    compiled = json.loads((BUILD / "area-compile-report.json").read_text())
    if args.voiceover and not compiled.get("compound"):
        parser.error("--voiceover currently requires a --compound fixture")
    if not compiled["passed"] or compiled["baseline"]:
        parser.error("Prepare and compile the area fixture first")
    for path, expected in compiled["sources_sha256"].items():
        if sha(FIXTURE / path) != expected:
            parser.error("Source changed after compilation: " + path)
    for key, path, absent in (
        ("native_sha256", FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge", compiled.get("noPlugin")),
        ("component_sha256", FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ", compiled.get("noComponent")),
    ):
        if not absent and compiled.get(key) and sha(path) != compiled[key]:
            parser.error("Runtime package changed after compilation: " + key)
    run_id = (FIXTURE / "Resources/run.txt").read_text()
    status = FIXTURE / "Resources/state.json"
    status.unlink(missing_ok=True)
    closed = FIXTURE / "Resources/closed.json"
    closed.unlink(missing_ok=True)
    close_request = FIXTURE / "Resources/close.json"
    close_request.unlink(missing_ok=True)
    report = {"passed": False, "compiled": args.compiled, "checks": [], "compile_report_sha256": sha(BUILD / "area-compile-report.json"), "nonblocking": compiled.get("nonblocking", False), "generated": compiled.get("generated", False)}
    def state():
        try:
            result = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        if result.get("error"):
            raise AssertionError(result)
        return result if result.get("runId") == run_id else {}
    def check(value, name):
        report["checks"].append({"name": name, "passed": bool(value)})
        print(("PASS: " if value else "FAIL: ") + name, flush=True)
        if not value:
            raise AssertionError(name)
    project = FIXTURE / "Project/Area.4DProject"
    with (BUILD / "area-desktop.log").open("w") as log:
        command = ["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
        if args.intel:
            command = ["arch", "-x86_64", *command]
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            if compiled.get("closeDuringLoad"):
                process.wait(timeout=30)
                closure = json.loads(closed.read_text(encoding="utf-8-sig"))
                check(closure["compiled"] is args.compiled, "requested desktop execution mode")
                check(closure["areas"] == 0 and closure["roots"] == 0, "closing before first idle retires reserved lifetimes")
                check(process.returncode == 0 and closure["name"] == "After initialization" and closure["childName"] == "Child", "early ordinary close preserves initialized data")
                report["closure"] = closure
                report["passed"] = True
                return
            ready, _ = wait_for_start(process, project, state, BUILD)
            check(ready["compiled"] is args.compiled, "requested desktop execution mode")
            report["architecture"] = ax.process_architecture(process.pid)
            check(report["architecture"].upper().replace("-", "").replace("_", "").startswith("X8664" if args.intel else "ARM64"), "requested desktop architecture")
            check(all(ready["preparation"].values()), "generated form preparation preserves source and rejects conflicts before mutation")
            app, window = activate_fixture(process, project, TITLE)
            if compiled.get("noPlugin"):
                check(state()["areas"]["areas"] == [], "absent native plugin delivers no area callbacks")
                check(state()["dependencies"].get("error") == "dependencyUnavailable" and not state()["dependencies"]["native"], "dependency check identifies missing native plugin")
                check(not any((x.read("AXIdentifier") or "").startswith("axb/") for x in window.read("AXChildren") or []), "absent native plugin exposes no false provider")
                ticks = state()["ticks"]
                ax.wait_for(lambda: state().get("ticks", 0) > ticks, "Business timer stopped without the native plugin")
                close_request.write_text("{}")
                process.wait(timeout=15)
                check(process.returncode == 0, "ordinary form closes normally with the native plugin absent")
                report["passed"] = True
                return
            if compiled.get("noComponent") or compiled.get("configuration") in ("disabled", "invalid", "error"):
                expected = "disabled" if compiled.get("configuration") == "disabled" else "failed"
                record = ax.wait_for(lambda: next((x for x in state().get("areas", {}).get("areas", []) if x["state"] == expected), None), "Startup did not expose its failure/opt-out state")
                check(not record["registered"], "failed or disabled startup creates no active registration")
                check(not any((x.read("AXIdentifier") or "").startswith("axb/") for x in window.read("AXChildren") or []), "failed or disabled startup exposes no false accessibility provider")
                error = "dependencyUnavailable" if compiled.get("noComponent") else "areaCallbackError" if compiled["configuration"] == "error" else "invalidLabel"
                check(expected == "disabled" or record.get("failure", {}).get("error") == error, "diagnostics identify the actual startup failure")
                if error == "areaCallbackError":
                    check(record["failure"].get("method") == "AXB_Configure" and record["failure"].get("line", 0) > 0, "configuration exception retains method and line")
                check(state().get("handlerRestored"), "area callback restores the application's error handler")
                ticks = state()["ticks"]
                ax.wait_for(lambda: state().get("ticks", 0) > ticks, "Business timer stopped after startup failure")
                check(state()["name"] == "After initialization", "ordinary form data remains initialized")
                close_request.write_text("{}")
                process.wait(timeout=15)
                closure = json.loads(closed.read_text(encoding="utf-8-sig"))
                check(closure["areas"] == 0 and closure["roots"] == 0 and process.returncode == 0, "normal close cleans up failed/disabled area lifetimes")
                report["passed"] = True
                return
            ax.wait_for(lambda: state().get("diagnostics", {}).get("ready"), "Bridge did not start: " + str(state()), timeout=15)
            group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb/")), None), "No area-owned provider")
            def find(label, role=None):
                return ax.wait_for(lambda: next((x for x in group.read("AXChildren") or [] if x.read("AXDescription") == label and (role is None or x.read("AXRole") == role)), None), "Missing " + label)
            def receipt():
                ax.wait_for(lambda: group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"), "No completion receipt", timeout=15)
            root_label = "Name" if compiled.get("configuration") in ("absent", "null") else "Root name"
            root_name = find(root_label, "AXTextField")
            child_name = find("Child: Name", "AXTextField")
            if compiled.get("sharedPointerGuard"):
                ax.wait_for(lambda: state().get("focus", {}).get("error") == "ambiguousFocus", "Shared native pointer was incorrectly accepted", timeout=15)
                check(root_name.read("AXFocused") is not True and child_name.read("AXFocused") is not True, "two native pointer owners publish no guessed editor focus")
                check(find("Remember root", "AXButton").perform("AXPress") == 0, "unambiguous native button accepts AX activation")
                ax.wait_for(lambda: state().get("clicks") == 1 and state().get("focusedObject") == "Name" and state().get("focus", {}).get("error") == "ambiguousFocus", "Native child focus did not remain guarded after the original handler", timeout=15)
                check(root_name.read("AXFocused") is not True and child_name.read("AXFocused") is not True, "forwarded child event and shared pointers cannot claim the parent editor")
                close_request.write_text("{}")
                process.wait(timeout=15)
                closure = json.loads(closed.read_text(encoding="utf-8-sig"))
                check(closure["areas"] == 0 and closure["roots"] == 0 and process.returncode == 0, "guarded compound form closes and retires ownership")
                report["passed"] = True
                return
            check(root_name.read("AXValue") == "After initialization", "area starts after business initialization")
            areas = state()["areas"]["areas"]
            expected_states = ["existingRegistration"] if compiled.get("earlyManualStart") else ["child", "existingRegistration"] if compiled.get("manual") else ["active"] if compiled.get("rootOnlyArea") else ["active", "child"]
            check(sorted(x["state"] for x in areas) == expected_states, "child area cannot claim the root window")
            if not (compiled.get("manual") or compiled.get("earlyManualStart")):
                check(any(x.get("configured") is (compiled.get("configuration") != "absent") and x.get("registered") for x in areas), "optional configuration discovery matches the installed application method")
                check(any(x.get("registered") and x.get("configuration") == "Root" for x in areas), "central configuration sees the derived root name rather than its shared base or child")
            initial_field = compiled.get("nonblocking") and compiled.get("initialFocus") in ("field", "explicit-field")
            if compiled.get("nonblocking"):
                initial_control = root_name if initial_field else find("Remember root", "AXButton")
                ax.wait_for(lambda: initial_control.read("AXFocused") is True and (focused := app.read("AXFocusedUIElement")) and focused.same_as(initial_control), "Initial native focus did not settle", timeout=15)
                check(True, "ordinary initial focus is published before testing editor actions")
            check(state()["ticks"] > 0, "existing business timer runs")
            issues = state()["diagnostics"].get("issues", [])
            check(not any(x.get("object", "").startswith("__AXB_Bridge") for x in issues), "infrastructure area produces no coverage warning")
            if compiled.get("configuration") not in ("absent", "null"):
                check(issues == [], "configured form has complete ordinary-control coverage")
            # A yielding load can finish before deferred native publication.
            # Wait for a stable live target before submitting the first action.
            previous_initial = None
            initial_changed_at = time.monotonic()
            def settled_initial():
                nonlocal previous_initial, initial_changed_at
                current = (state()["diagnostics"]["revision"], root_name.read("AXValue"), root_name.read("AXPosition"), root_name.read("AXSize"), root_name.read("AXEnabled"), root_name.read("AXFocused"))
                if current != previous_initial:
                    previous_initial, initial_changed_at = current, time.monotonic()
                return current if time.monotonic() - initial_changed_at >= 0.5 else None
            ax.wait_for(settled_initial, "Initial publication did not settle", timeout=15)
            try:
                ax.capture_window(process.pid, BUILD / "area-original.png")
            except (RuntimeError, subprocess.SubprocessError) as capture_error:
                report["captureError"] = str(capture_error)
            report["initialFocus"] = {"root": root_name.read("AXFocused"), "child": child_name.read("AXFocused"), "enabled": root_name.read("AXEnabled"), "help": group.read("AXHelp"), "focusedIdentifiers": [e.read("AXIdentifier") for e in group.read("AXChildren") or [] if e.read("AXFocused") is True]}
            check(root_name.read("AXEnabled") is True, "root editor is enabled in the active window")
            if initial_field:
                check(root_name.read("AXFocused") is True, "original first editor retains native focus")
                initial = state()
                report["initialFocus"].update(logicalPath=initial.get("focus", {}).get("node", {}).get("automationPath"), observedID=initial.get("observedID"), native=initial.get("nativeFocus"), issues=initial["diagnostics"].get("issues", []))
                check(report["initialFocus"]["logicalPath"] == ["Name"] and not any(x.get("reason") == "ambiguousFocus" for x in report["initialFocus"]["issues"]), "initial focus identifies the root path without ambiguity")
                if compiled.get("compound") and not compiled.get("pointerFocus"):
                    check(initial.get("observedID") == initial["focus"]["node"]["id"], "early real event identifies the initial physical editor")
            else:
                check(root_name.set_boolean("AXFocused", True) == 0, "root focus accepts AX request")
                ax.wait_for(lambda: root_name.read("AXFocused") is True and "focus confirmed" in (group.read("AXHelp") or "").lower(), "Root focus was not confirmed", timeout=15)
            check(root_name.set_string("AXValue", "Edited through accessibility") == 0, "root editor accepts AX request")
            ax.wait_for(lambda: root_name.read("AXValue") == "Edited through accessibility", "Root editor did not receive complete text", timeout=15)
            ax.wait_for(lambda: group.read("AXHelp") == "Text entered in the editor; normal validation runs when editing ends", "Root edit did not finish", timeout=15)
            check(find("Remember root", "AXButton").perform("AXPress") == 0, "root business action accepts AX request")
            ax.wait_for(lambda: state().get("name") == "Edited through accessibility" and state().get("clicks") == 1, "Root business result did not commit", timeout=15)
            receipt()
            if compiled.get("compound"):
                old_group = group
                old_root = root_name
                (FIXTURE / "Resources/restart.json").write_text("{}")
                ax.wait_for(lambda: state().get("restarted"), "Compound root did not restart", timeout=15)
                group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb/") and not x.same_as(old_group) and any(n.read("AXDescription") == root_label for n in x.read("AXChildren") or [])), None), "Restart did not publish the replacement compound provider", timeout=15)
                root_name = find(root_label, "AXTextField")
                child_name = find("Child: Name", "AXTextField")
                check(old_root.read("AXEnabled") is not True, "compound restart retires the previous native lifetime")
                check(root_name.set_boolean("AXFocused", True) == 0, "restarted root focus accepts AX request")
                ax.wait_for(lambda: root_name.read("AXFocused") is True and state().get("focus", {}).get("node", {}).get("automationPath") == ["Name"] and "focus confirmed" in (group.read("AXHelp") or "").lower(), "Restart lost compound focus ownership", timeout=15)
                check(root_name.read("AXValue") == "Edited through accessibility", "compound restart preserves the native editor value")
                check(not any(x.get("reason") == "ambiguousFocus" for x in state()["diagnostics"].get("issues", [])), "compound restart preserves observer participation or exact pointer ownership")
                check(child_name.set_boolean("AXFocused", True) == 0, "old child focus accepts AX request")
                def observed_child():
                    current = state()
                    focused = current.get("focus", {}).get("node", {})
                    exact = compiled.get("pointerFocus") or current.get("observedID") == focused.get("id")
                    return current if child_name.read("AXFocused") is True and focused.get("automationPath") == ["Child", "Name"] and exact else None
                old_focus = ax.wait_for(observed_child, "Old child event ownership was not confirmed", timeout=15)
                old_observed_id = old_focus.get("observedID")
                if compiled.get("pointerFocus"):
                    check(old_focus["focus"]["node"]["automationPath"] == ["Child", "Name"], "unique native pointer identifies the unobserved child")
                else:
                    check(old_observed_id == old_focus["focus"]["node"]["id"], "real child event identifies the old physical editor")
                (FIXTURE / "Resources/replace.json").write_text("{}")
                ax.wait_for(lambda: state().get("replaced") and any(x["state"] == "child" for x in state()["areas"]["areas"]), "Replacement child did not become ready", timeout=15)
                check(child_name.read("AXEnabled") is not True, "replacement retires the retained child editor")
                child_name = ax.wait_for(lambda: find("Child: Name", "AXTextField"), "Replacement child editor missing")
                # A normal replacement can complete before all deferred native
                # refreshes arrive. Settle publication before submitting input.
                previous_target = None
                target_changed_at = time.monotonic()
                def stable_target():
                    nonlocal previous_target, target_changed_at
                    current = (state()["diagnostics"]["revision"], child_name.read("AXValue"), child_name.read("AXPosition"), child_name.read("AXSize"), child_name.read("AXEnabled"), child_name.read("AXFocused"))
                    if current != previous_target:
                        previous_target, target_changed_at = current, time.monotonic()
                    return current if time.monotonic() - target_changed_at >= 0.5 else None
                ax.wait_for(stable_target, "Replacement publication did not settle", timeout=15)
                if not compiled.get("pointerFocus"):
                    check(state().get("observedID") != old_observed_id, "replacement retires the old observed focus identity")
                check(root_name.read("AXValue") == "Edited through accessibility", "child replacement preserves the root editor value")
            check(child_name.set_boolean("AXFocused", True) == 0, "child focus accepts AX request")
            ax.wait_for(lambda: child_name.read("AXFocused") is True and "focus confirmed" in (group.read("AXHelp") or "").lower(), "Child focus was not confirmed", timeout=15)
            check(child_name.set_string("AXValue", "Accessible child") == 0, "child editor accepts AX request")
            ax.wait_for(lambda: child_name.read("AXValue") == "Accessible child", "Child edit not applied", timeout=15)
            ax.wait_for(lambda: group.read("AXHelp") == "Text entered in the editor; normal validation runs when editing ends", "Child edit did not finish", timeout=15)
            check(find("Child: Remember child", "AXButton").perform("AXPress") == 0, "child business action accepts AX request")
            ax.wait_for(lambda: state().get("child", {}).get("name") == "Accessible child" and state().get("child", {}).get("clicks") == 1, "Child business result did not commit", timeout=15)
            receipt()
            if compiled.get("nonblocking"):
                if args.voiceover:
                    from voiceover import VoiceOver
                    vo = VoiceOver(process, project, TITLE, BUILD / "compound-voiceover", BUILD / "read-fixture-screen")
                    report["voiceover"] = vo.steps
                    try:
                        vo.start()
                        caption = vo.key("home", command=True)
                        for _ in range(10):
                            if "close button" in caption.lower().replace(",", ""):
                                break
                            caption = vo.key("home", command=True)
                        check("close button" in caption.lower().replace(",", ""), "VoiceOver reaches the owned window")
                        for _ in range(12):
                            caption = vo.key("right")
                            if "Area lifecycle" in caption and "group" in caption.lower():
                                break
                        check("Area lifecycle" in caption and "group" in caption.lower(), "VoiceOver reaches the compound form group")
                        vo.key("down", shift=True)
                        caption = vo.key("home")
                        read_root = read_child = False
                        for _ in range(12):
                            check("not responding" not in caption.lower(), "compound form responds to VoiceOver")
                            read_root |= "Root name" in caption and "Edited through accessibility" in caption
                            read_child |= "Name" in caption and "Accessible child" in caption
                            if read_root and read_child and "Remember child" in caption:
                                break
                            caption = vo.key("right")
                        check(read_root and read_child, "VoiceOver reads both duplicate-named editors and their values")
                        check("Remember child" in caption, "VoiceOver reaches the replacement child's business action")
                        vo.key("space")
                        ax.wait_for(lambda: state().get("child", {}).get("clicks") == 2, "VoiceOver did not run the original child action", timeout=15)
                        check(state()["name"] == "Edited through accessibility" and state()["child"]["name"] == "Accessible child", "VoiceOver activation preserves both committed values")
                    finally:
                        vo.stop()
                if compiled.get("compound"):
                    close_request.write_text("{}")
                else:
                    check(find("Close", "AXButton").perform("AXPress") == 0, "nonblocking close accepts AX action")
                process.wait(timeout=15)
                closure = json.loads(closed.read_text(encoding="utf-8-sig"))
                check(closure["areas"] == 0 and closure["roots"] == 0, "nonblocking close retires area and root ownership")
                check(closure["name"] == "Edited through accessibility" and closure["childName"] == "Accessible child", "nonblocking close preserves both committed editor results")
                check(process.returncode == 0, "nonblocking compound form closes normally")
                report["passed"] = True
                return
            first_id = root_name.read("AXIdentifier")
            previous_group_id = group.read("AXIdentifier")
            check(find("Restart", "AXButton").perform("AXPress") == 0, "intentional application restart accepts AX request")
            group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb/") and not x.same_as(group) and any(n.read("AXDescription") == root_label for n in x.read("AXChildren") or [])), None), "Restart did not publish the replacement root provider", timeout=15)
            restarted = find(root_label, "AXTextField")
            check(restarted.read("AXIdentifier") == first_id and root_name.read("AXEnabled") is not True, "intentional restart retires the previous lifetime")
            root_name = restarted
            first_id = root_name.read("AXIdentifier")
            ax.wait_for(lambda: state().get("diagnostics", {}).get("ready"), "Restart did not publish diagnostics")
            check(find("Close", "AXButton").perform("AXPress") == 0, "close follows normal action path")
            ax.wait_for(lambda: closed.is_file(), "First dialog did not close")
            closure = json.loads(closed.read_text(encoding="utf-8-sig"))
            check(closure["areas"] == 0 and closure["roots"] == 0, "area deinitialization retires host ownership without On Unload hooks")
            window = ax.wait_for(lambda: next((x for x in app.read("AXWindows") or [] if x.read("AXTitle") == TITLE), None), "Dialog did not reopen")
            group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb/")), None), "Reopened dialog has no provider")
            fresh = find(root_label, "AXTextField")
            check(fresh.read("AXIdentifier") == first_id and root_name.read("AXEnabled") is not True, "reopening creates a new lifetime and retires retained AX references")
            check(find("Close", "AXButton").perform("AXPress") == 0, "reopened dialog closes through AX")
            process.wait(timeout=15)
            check(process.returncode == 0, "ordinary application exits cleanly")
            report["passed"] = True
        finally:
            try:
                report["finalState"] = state()
            except (AssertionError, OSError, ValueError) as state_error:
                report["stateError"] = str(state_error)
                report["passed"] = False
            if 'group' in locals():
                report["lastReceipt"] = group.read("AXHelp")
            if process.poll() is None:
                try:
                    ax.capture_window(process.pid, BUILD / "area-last.png")
                except (RuntimeError, subprocess.SubprocessError):
                    pass
                finally:
                    process.terminate()
                    process.wait(timeout=10)
            suffix = "-missing-plugin" if compiled.get("noPlugin") else "-missing-component" if compiled.get("noComponent") else "-inherited" if compiled.get("inherited") else "-manual" if compiled.get("manual") else "-" + compiled.get("configuration", "normal")
            report["configuration"] = compiled.get("configuration")
            report["inherited"] = compiled.get("inherited")
            if compiled.get("nonblocking"):
                suffix += "-nonblocking"
            if compiled.get("generated"):
                suffix += "-generated"
            if compiled.get("rootOnlyArea"):
                suffix += "-root-only-area"
            if compiled.get("compound"):
                suffix += "-compound"
            if compiled.get("pointerFocus"):
                suffix += "-pointer"
            if compiled.get("earlyManualStart"):
                suffix += "-existing-registration"
            if compiled.get("sharedPointerGuard"):
                suffix += "-shared-pointer-guard"
            if compiled.get("closeDuringLoad"):
                suffix += "-close-during-load"
            if args.voiceover:
                suffix += "-voiceover"
            if args.intel:
                suffix += "-intel"
            if compiled.get("nonblocking") and compiled.get("initialFocus") in ("field", "explicit-field"):
                suffix += "-initial-" + compiled["initialFocus"]
            (BUILD / ("area-runtime" + suffix + ("-compiled.json" if args.compiled else "-interpreted.json"))).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
