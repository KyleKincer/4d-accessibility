#!/usr/bin/env python3
"""Exercise only the disposable optional-host fixture through external macOS AX.

The invoking agent/terminal needs existing Accessibility permission. Uses no
AreaList license, coordinate input, extra app identity, or production data.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time
import uuid

from prepare_host_fixture import BUILD, FIXTURE, ROOT, TITLE
from build_component import sha

sys.path.insert(0, str(ROOT / "tests"))
from mac_ax import application, trusted, wait_for


def pids():
    result = subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True)
    return [int(line) for line in result.stdout.splitlines()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Launch and exercise the prepared disposable fixture")
    parser.add_argument("--mode", required=True, choices=("interpreted", "compiled"))
    parser.add_argument("--dynamic", action="store_true", help="Open the JSON-generated version of the form")
    parser.add_argument("--attach", action="store_true", help="Exercise an untouched fixture already launched with its exact --project path")
    parser.add_argument("--client", type=Path, default=Path("/Applications/4D/4D.app"))
    args = parser.parse_args()
    if not args.run:
        parser.error("--run is required to launch the disposable fixture")
    if not trusted():
        parser.error("The invoking process needs Accessibility permission")
    existing = pids()
    if existing and not args.attach:
        parser.error("Close existing 4D sessions before this isolated test")
    if args.attach:
        if len(existing) != 1:
            parser.error("--attach requires exactly one 4D process")
        command = subprocess.run(["ps", "-p", str(existing[0]), "-o", "command="], capture_output=True, text=True, check=True).stdout
        if str(FIXTURE / "Project/HostAPIProbe.4DProject") not in command or "--project" not in command:
            parser.error("--attach only accepts a process launched with this disposable fixture's --project path")
    info = plistlib.loads((args.client / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4D":
        parser.error("--client must identify the 4D desktop application")
    compile_report = json.loads((BUILD / "host-api-compile-report.json").read_text())
    if compile_report.get("passed") is not True:
        parser.error("Prepare and compile the host fixture first")
    for relative, expected in compile_report["sources_sha256"].items():
        if sha(FIXTURE / relative) != expected:
            parser.error("Fixture source changed after compilation")
    if sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ") != compile_report["component_sha256"]:
        parser.error("Fixture component changed after compilation")
    runtime = FIXTURE / "Resources/runtime-status.json"
    if args.attach:
        config = json.loads((FIXTURE / "Resources/launch.json").read_text())
        if config.get("dynamic") is not args.dynamic:
            parser.error("The running fixture uses a different form construction path")
        run_id = config["runId"]
    else:
        run_id = uuid.uuid4().hex
        config = {"runId": run_id, "dynamic": args.dynamic}
        (FIXTURE / "Resources/launch.json").write_text(json.dumps(config) + "\n")
        runtime.write_text(json.dumps({"phase": "launching", **config}) + "\n")
    report_path = BUILD / f"host-api-{'dynamic' if args.dynamic else 'static'}-{args.mode}-report.json"
    report = {"passed": False, "state": "running", "mode": args.mode, **config, "checks": [],
              "scope": "External AX on optional host basic controls; synthetic basic-control workflow"}
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    owned_pid = None

    def check(condition, description):
        report["checks"].append({"name": description, "passed": bool(condition)})
        print(f"{'PASS' if condition else 'FAIL'}: {description}", flush=True)
        if not condition:
            raise AssertionError(description)

    def state():
        try:
            value = json.loads(runtime.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        if value.get("phase") == "failed":
            raise AssertionError(f"Fixture runtime failed: {value}")
        return value

    try:
        if not args.attach:
            subprocess.run(["/usr/bin/open", "-n", str(args.client), "--args", "--project",
                            str(FIXTURE / "Project/HostAPIProbe.4DProject"), "--dataless",
                            "--opening-mode", args.mode, "--webadmin-auto-start", "false"], check=True, timeout=10)
        processes = wait_for(pids, "4D did not start", 15)
        check(len(processes) == 1, "one isolated 4D process available")
        owned_pid = processes[0]
        ready = wait_for(lambda: state() if state().get("phase") == "ready" else None,
                         "Fixture did not become ready", 30)
        check(ready.get("runId") == run_id, "runtime belongs to this launch")
        check(ready.get("compiled") is (args.mode == "compiled"), "actual host mode matches request")
        component = ready.get("componentInfo", {})
        check(component.get("compiled") is True and component.get("hostAPI") == 1, "compiled component confirms the optional API in the live form")
        check(component.get("hostCompiled") is (args.mode == "compiled"), "component confirms the actual host execution mode")
        report["componentInfo"] = component
        check(ready.get("dynamic") is args.dynamic, "requested form construction path executed")
        for assertion in ready.get("checks", []):
            check(assertion.get("passed") is True, assertion["name"])
        check(len(ready.get("checks", [])) == 3, "all internal host API guards exercised")
        wait_for(lambda: state().get("timerFirings") == 1, "Host timer did not fire")
        app = application(owned_pid)

        def fixture_window():
            windows = [window for window in (app.read("AXWindows") or []) if window.read("AXTitle") == TITLE]
            if len(windows) > 1:
                raise AssertionError("Ambiguous fixture window")
            return windows[0] if windows else None

        window = wait_for(fixture_window, "Disposable fixture AX window not found")
        field = wait_for(lambda: window.find(".name"), "Name field not published")
        submit = wait_for(lambda: window.find(".submit"), "Submit not published")
        allowed = wait_for(lambda: window.find(".allowed"), "Checkbox not published")
        status = wait_for(lambda: window.find(".status"), "Status not published")
        check(field.read("AXValue") == "Fixture tester" and status.read("AXValue") == "Ready", "fixture starts untouched")

        def status_is(text):
            return status.read("AXValue") == text

        check(field.read("AXRole") == "AXTextField", "input exposed with text-field semantics")
        check(submit.read("AXRole") == "AXButton", "button exposed with button semantics")
        check(field.set_text("AX café 日本語 🎸") == 0, "Unicode edit submitted through AX")
        wait_for(lambda: status_is("Name accepted") and field.read("AXValue") == "AX café 日本語 🎸", "Unicode edit not accepted")
        check(True, "4D handler accepted and published Unicode value")
        check(field.set_text("") == 0, "invalid edit submitted through AX")
        wait_for(lambda: status_is("Name must contain 1 to 40 characters"), "Validation rejection not published")
        check(field.read("AXValue") == "AX café 日本語 🎸", "rejected edit preserves the accepted value")
        check(allowed.press() == 0, "checkbox change requested through AX")
        wait_for(lambda: allowed.read("AXValue") == False and submit.read("AXEnabled") == False and status_is("Permission changed"), "Submit did not disable")
        unchanged = status.read("AXValue")
        submit.press()
        time.sleep(0.3)
        check(status.read("AXValue") == unchanged, "disabled action does not reach the handler")
        check(allowed.press() == 0, "checkbox re-enabled through AX")
        wait_for(lambda: submit.read("AXEnabled"), "Submit did not re-enable")
        check(submit.press() == 0, "submit requested through AX")
        wait_for(lambda: status_is("Submissions: 1"), "Submission did not complete")
        check(True, "application completed exactly one submission")
        hide = window.find(".hide")
        check(hide is not None and hide.press() == 0, "hide requested through AX")
        wait_for(lambda: window.find(".name") is None, "Hidden input remained in AX tree")
        check(True, "hidden input is removed from AX")
        check(hide.press() == 0, "show requested through AX")
        field = wait_for(lambda: window.find(".name"), "Input did not return")
        check(field.read("AXValue") == "AX café 日本語 🎸", "show preserves accepted data")
        identifier = field.read("AXIdentifier")
        restart = window.find(".restart")
        check(restart is not None and restart.press() == 0, "session replacement requested through AX")

        def replacement():
            candidate = window.find(".name")
            return candidate if candidate and candidate.read("AXIdentifier") != identifier else None

        replacement_field = wait_for(replacement, "Fresh session identity not published")
        status = wait_for(lambda: window.find(".status"), "Replacement status missing")
        wait_for(lambda: status_is("Bridge restarted"), "Replacement did not complete")
        field.set_text("Stale edit")
        submit.press()
        time.sleep(0.3)
        check(replacement_field.read("AXValue") == "AX café 日本語 🎸" and status_is("Bridge restarted"),
              "retained old-session controls cannot change replacement state")
        submit = window.find(".submit")
        check(submit is not None and submit.press() == 0, "replacement session accepts a fresh action")
        wait_for(lambda: status_is("Submissions: 2"), "Fresh replacement action failed")
        check(state().get("timerFirings") == 1, "host timer remains one-shot while AX actions continue")
        close = window.read("AXCloseButton")
        check(close is not None and close.press() == 0, "native window closure requested through AX")
        wait_for(lambda: owned_pid not in pids(), "4D fixture did not exit", 10)
        check(True, "4D completed form unload and process shutdown")
        owned_pid = None
        report.update(passed=True, state="finished")
    except Exception as error:
        report.update(state="failed", error=str(error))
        raise
    finally:
        if owned_pid is not None and owned_pid in pids():
            # Only the fresh process launched after the empty-process precheck.
            os.kill(owned_pid, signal.SIGTERM)
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"PASS: {len(report['checks'])} external host API checks; {report_path}")


if __name__ == "__main__":
    main()
