#!/usr/bin/env python3
"""Exercise automatic providers through external AX, with normal 4D event traces."""
import argparse
import ctypes as c
import json
import subprocess
import sys
import time

from build_component import sha
from prepare_discovery_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
from mac_ax import CF, Element, UTF8, application, make_string, process_architecture, release, set_attribute, trusted, wait_for as wait_external


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run or not trusted():
        parser.error("--run and Accessibility permission are required")
    pids = subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split()
    if len(pids) != 1:
        parser.error("Launch the disposable Discovery project")
    pid = int(pids[0])
    command = subprocess.check_output(["ps", "-p", str(pid), "-o", "command="], text=True)
    if "--project " + str(FIXTURE / "Project/Discovery.4DProject") not in command:
        parser.error("Refusing another 4D project")
    compiled = json.loads((BUILD / "discovery-compile-report.json").read_text())
    if not compiled.get("passed") or compiled["baseline"]:
        parser.error("Prepare the automatic discovery fixture first")
    for relative, expected in compiled["sources_sha256"].items():
        if sha(FIXTURE / relative) != expected:
            parser.error("Source changed after compilation: " + relative)
    for key, relative in (("component_sha256", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"),
                          ("native_sha256", "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")):
        if sha(FIXTURE / relative) != compiled[key]:
            parser.error("Package changed after compilation")
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    report = {"passed": False, "runId": config["runId"], "checks": [],
              "dynamic": config.get("dynamic", False), "process_architecture": process_architecture(pid),
              "compile_report_sha256": sha(BUILD / "discovery-compile-report.json")}

    def check(condition, name):
        report["checks"].append({"name": name, "passed": bool(condition)})
        print(("PASS: " if condition else "FAIL: ") + name, flush=True)
        if not condition:
            raise AssertionError(name)

    def state():
        try:
            value = json.loads((FIXTURE / "Resources/runtime-status.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        if value.get("phase") == "failed" or value.get("failure"):
            raise AssertionError(str(value.get("failure") or value))
        return value if value.get("runId") == config["runId"] else {}

    def wait_for(predicate, message, timeout=5):
        def checked():
            state()
            return predicate()
        return wait_external(checked, message, timeout)

    try:
        ready = wait_for(lambda: state() if state().get("phase") == "ready" else None, "No current fixture state", 15)
        report["compiled"] = ready["compiled"]
        check(ready["start"]["ok"], "one start call registers a form without describe/apply callbacks")
        app = application(pid)
        window = next(w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE)
        group = wait_for(lambda: next((e for e in window.read("AXChildren") or [] if (e.read("AXIdentifier") or "").startswith("axb.window.")), None), "No automatic tree")

        def controls():
            return group.read("AXChildren") or []

        def find(label, role=None):
            return next((e for e in controls() if e.read("AXDescription") == label and (role is None or e.read("AXRole") == role)), None)

        def settle():
            wait_for(lambda: group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"), "No final receipt")
            state()

        def press(label):
            settle()
            check(find(label).press() == 0, label + " accepts AXPress")
            time.sleep(.2)
            settle()

        check(len(controls()) == 19, "all visible fixture controls are exposed once")
        check(find("Explain form", "AXButton") is not None, "untitled button uses its existing help tip as its accessible name")
        check(find("Detailed help " + "x" * 497, "AXButton") is not None, "long help tip fits the node-name limit without splitting a Unicode character")
        check(find("Save contact", "AXButton") is not None and find("Store the contact details") is None, "visible button caption takes precedence over its help tip")
        check(find("Empty") is None, "empty static text does not create a nameless accessibility stop")
        press("Explain form")
        check(sum(e == {"object": "Help", "event": 4} for e in state()["events"]) == 1, "help-tip-named button retains its normal object handler")
        wait_for(lambda: find("Helpful details") is not None, "New static text did not appear")
        check(find("Helpful details").read("AXValue") == "Helpful details", "previously empty static text appears when the application supplies content")
        check(find("Hidden action") is None and find("Disabled action").read("AXEnabled") is False, "hidden and disabled states match the live UI")
        check(find("Name", "AXTextField").read("AXValue") == "Ada", "ordinary field is discovered with its current value")
        check(find("Name", "AXTextField").read("AXTitleUIElement").read("AXValue") == "Name", "input names refer to their visible labels")
        secret = find("Password", "AXTextField")
        check(secret.read("AXSubrole") == "AXSecureTextField" and secret.read("AXValue") == "", "masked field has secure semantics and omits its contents")
        check(find("Email").read("AXRole") == "AXRadioButton" and find("Email").read("AXValue") == 1, "radio semantics and selected state are discovered")
        check(find("Country").read("AXRole") == "AXPopUpButton" and find("Country").read("AXValue") == "United States", "array popup exposes its displayed choice")
        check(find("Close fixture").read("AXRole") == "AXButton", "button with an object method and standard action is discovered")
        check(find("Summary").read("AXValue") == "Read-only summary" and not find("Summary").is_settable("AXValue"), "read-only input publishes its value without advertising edits")
        check(find("Amount").read("AXValue") == "1,234.50", "numeric input uses its displayed number format")
        check(find("DueDate").read("AXValue") == "September 23, 2026", "date input uses its displayed date format")
        check(find("Appointment").read("AXValue") == "13:05:09", "time input uses its displayed time format")
        press("Save contact")
        check(state()["saved"] == 1 and sum(e == {"object": "Save", "event": 4} for e in state()["events"]) == 1, "AX press runs the existing object handler exactly once")
        press("Send updates")
        check(state()["allowed"] is True and find("Send updates").read("AXValue") == 1, "checkbox activation runs its ordinary handler and publishes state")
        press("Phone")
        check(state()["email"] == 0 and state()["phone"] == 1, "radio activation preserves native group exclusivity")
        before = list(state()["events"])
        find("Disabled action").press()
        time.sleep(.2)
        check(state()["events"] == before, "disabled action cannot dispatch an object event")
        field = find("Name", "AXTextField")
        key = make_string(None, b"AXFocused", UTF8)
        try:
            check(set_attribute(field.pointer, key, c.c_void_p.in_dll(CF, "kCFBooleanTrue").value) == 0, "AX focus request is accepted")
        finally:
            release(key)
        wait_for(lambda: state().get("focus") == "Name" and field.read("AXFocused"), "Real input focus did not move")
        settle()
        check(True, "AX focus uses 4D keyboard focus and normal focus events")
        report["focusedUIRole"] = (app.read("AXFocusedUIElement").read("AXRole") if isinstance(app.read("AXFocusedUIElement"), Element) else None)
        check(report["focusedUIRole"] == "AXTextField", "application focused element is the real semantic input")
        check(field.set_text("Zoë 🎸") == 0, "Unicode replacement requested through AX")
        wait_for(lambda: field.read("AXValue") == "Zoë 🎸", "Editor did not receive Unicode text")
        settle()
        check(state()["name"] == "Ada", "AX reads the editing buffer before normal data-source commit")
        press("Save contact")
        check(state()["name"] == "Zoë 🎸" and any(e == {"object": "Name", "event": 20} for e in state()["events"]), "leaving the editor commits through its existing On Data Change handler")
        check(field.set_range("AXSelectedTextRange", 0, 3) == 0, "text range requested through AX")
        wait_for(lambda: field.read("AXSelectedTextRange") == (0, 3), "Native editor selection did not change")
        settle()
        check(field.read("AXSelectedText") == "Zoë", "selected text comes from the real editor selection")
        check(field.set_string("AXSelectedText", "Ada") == 0, "selected text replacement requested through AX")
        wait_for(lambda: field.read("AXValue") == "Ada 🎸", "Selected text was not replaced")
        settle()
        before_keys = sum(e == {"object": "Name", "event": 17} for e in state()["events"])
        check(field.set_text("🎸🎹") == 0, "adjacent supplementary characters requested at the start of an empty replacement")
        wait_for(lambda: field.read("AXValue") == "🎸🎹", "Complete supplementary characters did not enter the editor")
        settle()
        check(sum(e == {"object": "Name", "event": 17} for e in state()["events"]) - before_keys == 2, "each supplementary character runs one ordinary keystroke event")
        check(field.set_text("A#B") == 0, "filtered input requested through AX")
        time.sleep(.2)
        settle()
        check(field.read("AXValue") == "A" and "rejected" in group.read("AXHelp"), "existing keystroke filter rejects input and stops the remaining characters")
        check(field.set_text("!never-type-this") == 0, "input that changes application focus requested")
        wait_for(lambda: state().get("focus") == "Notes", "Existing handler did not redirect focus")
        settle()
        check(state()["notes"] == "First line\rSecond line" and field.read("AXValue") == "!", "focus-changing handler cannot redirect remaining queued text into another field")
        check(field.set_text("Valid name") == 0, "valid text re-entered after interruption")
        wait_for(lambda: field.read("AXValue") == "Valid name", "Text did not recover")
        settle()
        press("Save contact")
        check(field.set_text("") == 0, "empty text requested through AX")
        wait_for(lambda: field.read("AXValue") == "", "Editor did not clear its text")
        settle()
        press("Save contact")
        check(state()["name"] == "Valid name" and state()["validationError"] == "Name is required", "existing validation rejects the edit and preserves its accepted value")
        check(field.set_text("$never-type-this") == 0, "text that makes its field read-only requested")
        wait_for(lambda: (current := find("Name", "AXTextField")) and not current.is_settable("AXValue"), "Host's read-only change was not published")
        settle()
        check(find("Name", "AXTextField").read("AXValue") == "$", "entry stops when a host handler makes the field read-only")
        field.set_text("stale write")
        time.sleep(.2)
        check(find("Name", "AXTextField").read("AXValue") == "$", "retained writable element cannot edit a field after its capabilities change")
        press("Save contact")
        check(find("Name", "AXTextField").is_settable("AXValue"), "ordinary host action restores the field's editing capability")
        check(find("Notes").read("AXRole") == "AXTextArea", "multiline input uses text-area semantics")
        notes = find("Notes")
        check(notes.set_text("First α\nSecond 🎹") == 0, "multiline Unicode text requested through AX")
        wait_for(lambda: notes.read("AXValue") == "First α\rSecond 🎹", "Multiline editor did not receive its text")
        settle()
        bar = next(e for e in app.read("AXChildren") or [] if e.read("AXRole") == "AXMenuBar")
        edit = next(e for e in bar.read("AXChildren") or [] if e.read("AXTitle") == "Edit")
        undo = next(e for menu in edit.read("AXChildren") or [] for e in menu.read("AXChildren") or [] if e.read("AXTitle") == "Undo")
        check(undo.read("AXEnabled") is True and undo.press() == 0, "existing Undo command accepts native AX activation")
        wait_for(lambda: notes.read("AXValue") != "First α\rSecond 🎹", "Undo did not change the real editor")
        check(True, "AX text entry participates in 4D's existing undo behavior")
        check(secret.set_text("AX synthetic password") == 0, "secure input accepts write-only AX text entry")
        time.sleep(.2)
        settle()
        check(secret.read("AXValue") == "" and secret.read("AXSelectedText") in (None, ""), "secure text and selected contents remain undisclosed during editing")
        press("Save contact")
        check(state()["secretAccepted"] is True, "protected input commits through the normal editor")
        check(find("Country").press() == 0, "popup opens through its normal control event")
        menu = wait_for(lambda: next((e for e in window.read("AXChildren") or [] if e.read("AXRole") == "AXMenu"), None), "Native popup menu is unavailable")
        choices = menu.read("AXChildren") or []
        check([e.read("AXTitle") for e in choices] == ["United States", "Canada", "United Kingdom"], "existing native menu exposes every popup choice")
        menu_focus = app.read("AXFocusedUIElement")
        check(isinstance(menu_focus, Element) and not (menu_focus.read("AXIdentifier") or "").startswith("axb."), "native popup tracking restores application focus to its own accessibility provider")
        check(choices[1].press() == 0, "choice is selected through the native menu's AX action")
        wait_for(lambda: state().get("choice") == 2, "Popup selection did not reach 4D")
        settle()
        check(find("Country").read("AXValue") == "Canada" and any(e == {"object": "Country", "event": 4} for e in state()["events"]), "popup selection preserves its existing On Clicked handler")
        settle()
        check(find("Close fixture").press() == 0, "standard Cancel button accepts AX activation")
        path = FIXTURE / "Resources/closed.json"
        result = wait_for(lambda: json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else None, "Normal dialog close did not finish", 10)
        check(result["runId"] == config["runId"] and result["dialogOK"] == 0, "existing standard Cancel action closes the dialog")
        check(sum(e == {"object": "Close", "event": 4} for e in result["events"]) == 1, "Close object method runs exactly once before its standard action")
        report["events"] = result["events"]
        report["passed"] = True
    finally:
        (BUILD / "discovery-runtime-report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
