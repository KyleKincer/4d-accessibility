#!/usr/bin/env python3
"""Verify that an accessibility replacement reaches a timed search intact."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from build_component import sha
from prepare_large_form import BUILD, FIXTURE, ROOT, TITLE
import doctor

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, Accessibility permission and an unlocked desktop are required")
    assert subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode != 0
    prepared = json.loads((BUILD / "large-form-compile-report.json").read_text())
    assert prepared["passed"] and prepared["debounced"]
    for name, digest in prepared["sources_sha256"].items():
        assert sha(FIXTURE / name) == digest
    for key, relative in [
        ("native_sha256", "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
        ("component_sha256", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"),
    ]:
        assert sha(FIXTURE / relative) == prepared[key]
    project = FIXTURE / "Project/LargeForm.4DProject"
    status = FIXTURE / "Resources/status.json"
    status.unlink(missing_ok=True)
    report = {"passed": False, "compiled": args.compiled, "checks": [], "sources_sha256": prepared["sources_sha256"], "native_sha256": prepared["native_sha256"], "component_sha256": prepared["component_sha256"]}
    def check(value, name):
        report["checks"].append({"name": name, "passed": bool(value)})
        print(("PASS: " if value else "FAIL: ") + name, flush=True)
        assert value, name
    def state():
        if process.poll() is not None:
            raise AssertionError("Owned fixture exited unexpectedly")
        for _ in range(30):
            try:
                value = json.loads(status.read_text(encoding="utf-8-sig"))
                assert not any(value.get(k) for k in ("error", "bridgeError", "failure")), value
                return value
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(.02)
        return {}
    with (BUILD / "debounced-input-desktop.log").open("w") as log:
        process = subprocess.Popen(["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
    close = None
    try:
        ready, _ = wait_for_start(process, project, state, BUILD)
        check(ready["start"]["ok"] and ready["compiled"] is args.compiled, "Timed search starts in the requested execution mode")
        app, window = activate_fixture(process, project, TITLE)
        time.sleep(1)
        def group():
            return next((e for e in window.read("AXChildren") or [] if str(e.read("AXIdentifier")).startswith("axb.window.")), None)
        g = ax.wait_for(group, "Form not published", timeout=20)
        controls = {e.read("AXDescription"): e for e in g.read("AXChildren") or []}
        close = controls["Close"]
        field = controls["Large note"]
        check(field.set_boolean("AXFocused", True) == 0, "Search focus is requested")
        ax.wait_for(lambda: field.read("AXFocused") and state().get("editor") is not None, "Search editor did not focus", timeout=15)
        ax.wait_for(lambda: "queued" not in str(g.read("AXHelp")) and "Waiting" not in str(g.read("AXHelp")), "Focus confirmation did not complete", timeout=15)
        check(field.set_text("1050") == 0, "AX replacement is delivered")
        try:
            result = ax.wait_for(lambda: state() if state().get("submitted") is not None else None, "Search timer did not execute", timeout=25)
        finally:
            report["receipt"] = g.read("AXHelp")
            report["finalState"] = state()
        report["submitted"] = result["submitted"]
        report["beforeCount"] = result["beforeCount"]
        check(result["submitted"] == "1050", "One-second search timer receives the complete requested value")
        report["passed"] = True
    finally:
        if process.poll() is None:
            report["lastState"] = state()
            if "g" in locals():
                report["lastReceipt"] = g.read("AXHelp")
        if process.poll() is None:
            if close is not None:
                close.press()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)
        (BUILD / ("debounced-input-compiled.json" if args.compiled else "debounced-input-interpreted.json")).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
