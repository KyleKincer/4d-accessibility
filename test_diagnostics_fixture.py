#!/usr/bin/env python3
"""Verify public coverage reports across live nested form changes."""
import argparse
import json
import subprocess
import sys

from build_component import sha
import doctor
from prepare_diagnostics_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, Accessibility permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before launching this owned fixture")
    compiled = json.loads((BUILD / "diagnostics-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected
    assert sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge") == compiled["native_sha256"]
    assert sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ") == compiled["component_sha256"]
    status, closed = FIXTURE / "Resources/status.json", FIXTURE / "Resources/closed.json"
    status.unlink(missing_ok=True)
    closed.unlink(missing_ok=True)
    checks = []
    report = {"passed": False, "checks": checks, **{k: compiled[k] for k in ["native_sha256", "component_sha256"]}}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def state():
        assert process.poll() is None, "Owned fixture exited"
        try:
            value = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        assert not any(value.get(k) for k in ["error", "bridgeError", "failure"]), value
        return value

    def issues():
        return state().get("diagnostics", {}).get("issues", [])

    def descendants(element):
        for child in element.read("AXChildren") or []:
            yield child
            yield from descendants(child)

    project = FIXTURE / "Project/Diagnostics.4DProject"
    with (BUILD / "diagnostics-desktop.log").open("w") as log:
        process = subprocess.Popen(["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", "interpreted", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
    try:
        ready, report["notice"] = wait_for_start(process, project, state, BUILD)
        check(ready["start"]["ok"], "ordinary root starts without a diagnostics hook")
        app = ax.application(process.pid)
        window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None), "Diagnostics window missing")

        def press(label):
            button = next(e for e in descendants(window) if e.read("AXDescription") == label and e.read("AXRole") == "AXButton")
            check(button.press() == 0, "invoke existing control: " + label)

        ax.wait_for(lambda: state().get("diagnostics", {}).get("ready") and len(issues()) == 4, "Nested diagnostics missing")
        report["initial"] = state()["diagnostics"]
        expected = {((), "UnsupportedTab", "providerPending"), ((), "Missing", "missingLabel"), (("Details",), "Missing", "missingLabel"), (("Details", "Inner"), "Missing", "missingLabel")}
        check({(tuple(i["path"]), i["object"], i["reason"]) for i in issues()} == expected, "one root report identifies unsupported controls and exact repeated child paths")
        check(state()["diagnostics"] == state()["afterMutation"], "mutating a returned report cannot change bridge state")
        check("private" not in json.dumps(state()["diagnostics"]), "coverage metadata contains no editor or business values")
        check(state()["diagnostics"]["revision"] > 0 and state()["diagnostics"]["nodeCount"] > 0, "report identifies the published revision and node count")
        press("Toggle details")
        ax.wait_for(lambda: len(issues()) == 2, "Hidden child diagnostics were retained")
        check(all(not issue["path"] for issue in issues()), "hidden descendants retire from the report")
        press("Toggle tabs")
        ax.wait_for(lambda: len(issues()) == 1, "Hidden unsupported control remained in report")
        check(issues()[0]["reason"] == "missingLabel", "hidden unsupported control no longer appears as a coverage gap")
        press("Toggle details")
        ax.wait_for(lambda: len(issues()) == 3, "Returning nested child diagnostics missing")
        check(True, "showing nested children restores their current coverage issues")
        press("Name inputs")
        ax.wait_for(lambda: state().get("diagnostics", {}).get("ready") and not issues(), "Correct labels did not clear reports after restart")
        check(True, "root and child metadata resolve missing labels without per-control handlers")
        report["resolved"] = state()["diagnostics"]
        press("Close")
        process.wait(timeout=10)
        check(process.returncode == 0, "owned diagnostics fixture closes normally")
        check(json.loads(closed.read_text(encoding="utf-8-sig")) == {"ok": False, "error": "unregisteredWindow"}, "stopped form cannot return an obsolete coverage report")
        report["passed"] = True
    finally:
        if process.poll() is None:
            try:
                report["last_state"] = state()
            except Exception as error:
                report["captureError"] = str(error)
            process.terminate()
            process.wait(timeout=10)
        (BUILD / "diagnostics-runtime-report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
