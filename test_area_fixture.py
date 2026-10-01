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
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error("--run and Accessibility permission are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the owned fixture")
    compiled = json.loads((BUILD / "area-compile-report.json").read_text())
    if not compiled["passed"] or compiled["baseline"]:
        parser.error("Prepare and compile the area fixture first")
    for path, expected in compiled["sources_sha256"].items():
        if sha(FIXTURE / path) != expected:
            parser.error("Source changed after compilation: " + path)
    run_id = (FIXTURE / "Resources/run.txt").read_text()
    status = FIXTURE / "Resources/state.json"
    status.unlink(missing_ok=True)
    closed = FIXTURE / "Resources/closed.json"
    closed.unlink(missing_ok=True)
    close_request = FIXTURE / "Resources/close.json"
    close_request.unlink(missing_ok=True)
    report = {"passed": False, "compiled": args.compiled, "checks": [], "compile_report_sha256": sha(BUILD / "area-compile-report.json")}
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
        process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
        try:
            ready, _ = wait_for_start(process, project, state, BUILD)
            check(ready["compiled"] is args.compiled, "requested desktop execution mode")
            check(all(ready["preparation"].values()), "generated form preparation preserves source and rejects conflicts before mutation")
            app, window = activate_fixture(process, project, TITLE)
            if compiled.get("noPlugin"):
                check(state()["areas"]["areas"] == [], "absent native plugin delivers no area callbacks")
                check(state()["dependencies"].get("error") == "dependencyUnavailable" and not state()["dependencies"]["native"], "dependency check identifies missing native plugin")
                check(not any((x.read("AXIdentifier") or "").startswith("axb.window.") for x in window.read("AXChildren") or []), "absent native plugin exposes no false provider")
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
                check(not any((x.read("AXIdentifier") or "").startswith("axb.window.") for x in window.read("AXChildren") or []), "failed or disabled startup exposes no false accessibility provider")
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
            group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb.window.")), None), "No area-owned provider")
            def find(label, role=None):
                return ax.wait_for(lambda: next((x for x in group.read("AXChildren") or [] if x.read("AXDescription") == label and (role is None or x.read("AXRole") == role)), None), "Missing " + label)
            def receipt():
                ax.wait_for(lambda: group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"), "No completion receipt", timeout=15)
            root_label = "Name" if compiled.get("configuration") in ("absent", "null") else "Root name"
            root_name = find(root_label, "AXTextField")
            child_name = find("Child: Name", "AXTextField")
            check(root_name.read("AXValue") == "After initialization", "area starts after business initialization")
            areas = state()["areas"]["areas"]
            expected_states = ["child", "existingRegistration"] if compiled.get("manual") else ["active", "child"]
            check(sorted(x["state"] for x in areas) == expected_states, "child area cannot claim the root window")
            if not compiled.get("manual"):
                check(any(x.get("configured") is (compiled.get("configuration") != "absent") and x.get("registered") for x in areas), "optional configuration discovery matches the installed application method")
                check(any(x.get("registered") and x.get("configuration") == "Root" for x in areas), "central configuration sees the derived root name rather than its shared base or child")
            check(state()["ticks"] > 0, "existing business timer runs")
            issues = state()["diagnostics"].get("issues", [])
            check(not any(x.get("object", "").startswith("__AXB_Bridge") for x in issues), "infrastructure area produces no coverage warning")
            if compiled.get("configuration") not in ("absent", "null"):
                check(issues == [], "configured form has complete ordinary-control coverage")
            try:
                ax.capture_window(process.pid, BUILD / "area-original.png")
            except (RuntimeError, subprocess.SubprocessError) as capture_error:
                report["captureError"] = str(capture_error)
            check(root_name.set_boolean("AXFocused", True) == 0, "root focus accepts AX request")
            ax.wait_for(lambda: root_name.read("AXFocused") is True and "focus confirmed" in (group.read("AXHelp") or "").lower(), "Root focus was not confirmed", timeout=15)
            check(root_name.set_string("AXValue", "Edited through accessibility") == 0, "root editor accepts AX request")
            ax.wait_for(lambda: root_name.read("AXValue") == "Edited through accessibility", "Root editor did not receive complete text", timeout=15)
            ax.wait_for(lambda: group.read("AXHelp") == "Text entered in the editor; normal validation runs when editing ends", "Root edit did not finish", timeout=15)
            check(find("Remember root", "AXButton").perform("AXPress") == 0, "root business action accepts AX request")
            ax.wait_for(lambda: state().get("name") == "Edited through accessibility" and state().get("clicks") == 1, "Root business result did not commit", timeout=15)
            receipt()
            check(child_name.set_boolean("AXFocused", True) == 0, "child focus accepts AX request")
            ax.wait_for(lambda: child_name.read("AXFocused") is True and "focus confirmed" in (group.read("AXHelp") or "").lower(), "Child focus was not confirmed", timeout=15)
            check(child_name.set_string("AXValue", "Accessible child") == 0, "child editor accepts AX request")
            ax.wait_for(lambda: child_name.read("AXValue") == "Accessible child", "Child edit not applied", timeout=15)
            ax.wait_for(lambda: group.read("AXHelp") == "Text entered in the editor; normal validation runs when editing ends", "Child edit did not finish", timeout=15)
            check(find("Child: Remember child", "AXButton").perform("AXPress") == 0, "child business action accepts AX request")
            ax.wait_for(lambda: state().get("child", {}).get("name") == "Accessible child" and state().get("child", {}).get("clicks") == 1, "Child business result did not commit", timeout=15)
            receipt()
            first_id = root_name.read("AXIdentifier")
            previous_group_id = group.read("AXIdentifier")
            check(find("Restart", "AXButton").perform("AXPress") == 0, "intentional application restart accepts AX request")
            group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb.window.") and x.read("AXIdentifier") != previous_group_id and any(n.read("AXDescription") == root_label for n in x.read("AXChildren") or [])), None), "Restart did not publish the replacement root provider", timeout=15)
            restarted = find(root_label, "AXTextField")
            check(restarted.read("AXIdentifier") != first_id and root_name.read("AXEnabled") is not True, "intentional restart retires the previous lifetime")
            root_name = restarted
            first_id = root_name.read("AXIdentifier")
            ax.wait_for(lambda: state().get("diagnostics", {}).get("ready"), "Restart did not publish diagnostics")
            check(find("Close", "AXButton").perform("AXPress") == 0, "close follows normal action path")
            ax.wait_for(lambda: closed.is_file(), "First dialog did not close")
            closure = json.loads(closed.read_text(encoding="utf-8-sig"))
            check(closure["areas"] == 0 and closure["roots"] == 0, "area deinitialization retires host ownership without On Unload hooks")
            window = ax.wait_for(lambda: next((x for x in app.read("AXWindows") or [] if x.read("AXTitle") == TITLE), None), "Dialog did not reopen")
            group = ax.wait_for(lambda: next((x for x in window.read("AXChildren") or [] if (x.read("AXIdentifier") or "").startswith("axb.window.")), None), "Reopened dialog has no provider")
            fresh = find(root_label, "AXTextField")
            check(fresh.read("AXIdentifier") != first_id and root_name.read("AXEnabled") is not True, "reopening creates a new lifetime and retires retained AX references")
            check(find("Close", "AXButton").perform("AXPress") == 0, "reopened dialog closes through AX")
            process.wait(timeout=15)
            check(process.returncode == 0, "ordinary application exits cleanly")
            report["passed"] = True
        finally:
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
            (BUILD / ("area-runtime" + suffix + ("-compiled.json" if args.compiled else "-interpreted.json"))).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
