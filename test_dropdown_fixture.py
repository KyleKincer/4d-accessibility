#!/usr/bin/env python3
"""Exercise typed and hierarchical dropdowns through their native menus."""

import argparse
import json
import subprocess
import sys
import time

from build_component import sha
import doctor
from prepare_dropdown_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, AX permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before launching the owned fixture")
    compiled = json.loads((BUILD / "dropdown-controls-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected
    for key, relative in [
        ("native_sha256", "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
        ("component_sha256", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"),
    ]:
        assert sha(FIXTURE / relative) == compiled[key]
    report = {"passed": False, "checks": [], "compiled": compiled}

    def check(condition, message):
        report["checks"].append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    status = FIXTURE / "Resources/status.json"
    status.unlink(missing_ok=True)
    (FIXTURE / "Resources/command.json").unlink(missing_ok=True)
    project = FIXTURE / "Project/DropdownControls.4DProject"
    with (BUILD / "dropdown-controls-desktop.log").open("w") as log:
        process = subprocess.Popen([
            "/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D",
            "--project", str(project), "--dataless", "--opening-mode", "interpreted",
            "--webadmin-auto-start", "false",
        ], stdout=log, stderr=log)

    def state():
        assert process.poll() is None, "Owned fixture exited"
        try:
            result = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        assert not any(result.get(k) for k in ["error", "bridgeError", "failure"]), result
        return result

    def descendants(element):
        return [e for child in element.read("AXChildren") or [] for e in [child, *descendants(child)]]

    try:
        ready, report["notice"] = wait_for_start(process, project, state, BUILD)
        check(ready["start"]["ok"], "automatic bridge starts with typed dropdowns")
        app = ax.application(process.pid)
        window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None), "Owned window missing")
        root = ax.wait_for(lambda: next((e for e in descendants(window) if (e.read("AXIdentifier") or "").startswith("axb.window.")), None), "Bridge group missing")

        def control(name):
            return next(e for e in root.read("AXChildren") or [] if e.read("AXDescription") == name)

        def settle():
            ax.wait_for(lambda: root.read("AXHelp") not in ["Action queued", "Waiting for the application to complete the action"], "Action did not settle")

        def open_menu(name):
            settle()
            check(control(name).press() == 0, name + " opens through AXPress")
            return ax.wait_for(lambda: next((e for e in window.read("AXChildren") or [] if e.read("AXRole") == "AXMenu"), None), "Native menu missing")

        expected = {
            "Numbers": "1.5", "Integers": "10", "Dates": "9/24/26", "Times": "09:00:00",
            "ObjectChoice": "Maple", "NumberChoice": "4.5", "ValueChoice": "Red",
            "ReferenceChoice": "Red", "Hierarchical": "Default", "Placeholder": "Choose one",
            "Disabled": "Fixed",
        }
        for name, value in expected.items():
            check(control(name).read("AXRole") == "AXPopUpButton" and control(name).read("AXValue") == value, name + " exposes its displayed choice")
        check(control("Disabled").read("AXEnabled") is False, "disabled dropdown exposes its disabled state")
        control("Disabled").press()
        time.sleep(.3)
        check(not state()["events"] and not any(e.read("AXRole") == "AXMenu" for e in window.read("AXChildren") or []), "disabled dropdown cannot open a menu or call its handler")
        check(state()["diagnostics"]["issues"] == [{"path": [], "object": "Unhandled", "reason": "popupValueTypePending"}], "unsupported binding is diagnosed without false issues for supported menus")
        published = [{key: e.read(key) for key in ["AXDescription", "AXValue", "AXHelp"]} for e in descendants(root)]
        check("must-not-be-published" not in json.dumps(published), "backing object private properties are absent from AX")

        for name in ["Numbers", "Integers", "Dates", "Times", "ObjectChoice", "NumberChoice", "ValueChoice", "ReferenceChoice", "Placeholder"]:
            before = len(state()["events"])
            menu = open_menu(name)
            items = menu.read("AXChildren") or []
            text = items[1].read("AXTitle")
            check(items[1].press() == 0, name + " accepts a real native menu choice")
            ax.wait_for(lambda: control(name).read("AXValue") == text, "Selected display did not update for " + name)
            ax.wait_for(lambda: len(state()["events"]) >= before + 2, "Existing handlers did not run")
            check(state()["events"][before:] == [{"object": name, "event": 4}, {"object": name, "event": 20}], name + " calls each existing handler once")
        check(state()["referenceValue"] == 202 and state()["textValue"] == "Blue" and state()["numberIndex"] == 2, "native choices preserve each binding's storage semantics")
        menu = open_menu("Hierarchical")
        sizes = next(e for e in menu.read("AXChildren") or [] if e.read("AXTitle") == "Sizes")
        check(sizes.press() == 0, "native hierarchical menu opens its submenu")
        large = ax.wait_for(lambda: next((e for e in descendants(window) if e.read("AXRole") == "AXMenuItem" and e.read("AXTitle") == "Large"), None), "Native submenu choices missing")
        check(large.press() == 0, "native hierarchical child is selectable")
        ax.wait_for(lambda: control("Hierarchical").read("AXValue") == "Large" and state()["hierarchy"]["reference"] == 402, "Hierarchical selection was not preserved")
        check(True, "hierarchical popup publishes the selected child's label")
        settle()
        expanded = state()["hierarchy"]["expanded"]
        time.sleep(.5)
        check(state()["hierarchy"]["expanded"] == expanded, "discovery does not change shared list expansion")
        (FIXTURE / "Resources/command.json").write_text(json.dumps({"action": "replace", "sequence": 1}))
        ax.wait_for(lambda: state()["sequence"] == 1 and control("ObjectChoice").read("AXValue") == "Birch", "Rebound object was not discovered")
        check(True, "existing application replacement refreshes the displayed choice")

        if args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / "dropdown-controls-voiceover", BUILD / "read-fixture-screen")
            report["voiceover"] = vo.steps
            try:
                vo.start()
                caption = vo.key("home")
                check("Numbers" in caption and "2.5" in caption, "VoiceOver reads numeric selected value")
                vo.key("space")
                caption = vo.key("down", voiceover=False)
                report["choiceSpeech"] = caption
                check("3.5" in caption, "VoiceOver speaks the next native choice")
                vo.key("return", voiceover=False)
                ax.wait_for(lambda: control("Numbers").read("AXValue") == "3.5", "VoiceOver choice did not commit")
                check(True, "VoiceOver commits through the existing native menu")
            finally:
                vo.stop()
        settle()
        check(control("Note").set_string("AXValue", "Still editable") == 0, "ordinary editor remains operable alongside dropdowns")
        ax.wait_for(lambda: control("Note").read("AXValue") == "Still editable", "Ordinary edit did not complete")
        settle()
        check(control("Close").press() == 0, "normal Close requested")
        process.wait(timeout=10)
        check(process.returncode == 0, "owned dropdown fixture closes normally")
        report["passed"] = True
    finally:
        if process.poll() is None:
            try:
                report["lastState"] = state()
                ax.capture_window(process.pid, BUILD / "dropdown-controls-failure.png")
            finally:
                process.terminate()
                process.wait(timeout=10)
        (BUILD / ("dropdown-controls-voiceover-report.json" if args.voiceover else "dropdown-controls-runtime-report.json")).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
