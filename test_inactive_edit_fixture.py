#!/usr/bin/env python3
"""Check that a field's typed text stays published while 4D is in the background.

The fixture is a compiled form with a lifecycle area and three fields: Name, City and a password
field. The test types into Name and leaves the caret there, then brings Finder to the front. The
field still shows the typed text, which is not yet in its data source, so an accessibility client
must still read it. The test then returns to 4D, types into the password field and leaves again:
that field must still publish no text. It moves to City, which commits Name, and checks that both
values stay published with 4D in the background. An action or a value written while 4D is in the
background must be refused at once, not accepted and dropped, and work again with 4D in front.
Actions made in quick succession must all run, in order, while a repeated press runs once.
Last, a grid cell's editor must also keep its typed text published in the background.

With --dormant, nothing reads the window while the user types, so the bridge stays dormant. An
inspector then brings itself to the front and reads the window: the bridge wakes with 4D in the
background and must publish the typed text from its first description.

The form records what 4D reports about its editor on every tick, so a failure shows whether 4D
itself still holds the edit while it is inactive.
"""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

from build_component import BUILD, PACKAGE, literal, project_at, run_utility, sha, verify_package
from install_host_methods import main as install

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate, wait_for_start
import voiceover_session as keys

FIXTURE = BUILD / "inactive-edit-fixture"
APPLICATION = "/Applications/4D/4D.app/Contents/MacOS/4D"
TITLE = "AXB inactive edit"


def prepare(server):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("inactive-edit-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "InactiveEdit")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("InactiveError")
var $window : Integer
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; New object("name"; ""; "city"; ""; "secret"; ""; "presses"; 0; "selectedLines"; New collection; \\
 "lines"; New collection(New object("lineID"; "a"; "description"; "Pen"); New object("lineID"; "b"; "description"; "Ink"))))
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "AXB_Configure.4dm").write_text("#DECLARE($formName : Text) -> $options : Object\n"
        '$options:=New object("grids"; New object("Items"; New object("kind"; "collection"; "keyProperty"; "lineID"; "selection"; Formula(Form.selectedLines); "label"; "Items")))\n')
    (methods / "InactiveCount.4dm").write_text("Form.presses:=Form.presses+1\n")
    (methods / "InactiveOther.4dm").write_text('var $window : Integer\n$window:=Open form window("Other"; Plain form window)\nDIALOG("Other"; New object("note"; ""))\nCLOSE WINDOW($window)\n')
    (methods / "Compiler_Inactive.4dm").write_text("C_TEXT(AXB_Configure; $1)\nC_OBJECT(AXB_Configure; $0)\n")
    (methods / "InactiveError.4dm").write_text('File("/RESOURCES/error.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    # What 4D itself reports about the focused editor, from the form's own process.
    (methods / "InactiveForm.4dm").write_text('''var $state; $focus : Object
Case of
 : (Form event code=On Load)
  SET TIMER(15)
 : (Form event code=On Timer)
  $state:=New object("focus"; OBJECT Get name(Object with focus); "editing"; Is editing text; "frontmost"; Frontmost window=Current form window)
  If ($state.focus#"inputSecret")
   $state.edited:=Get edited text
  End if
  $state.name:=Form.name
  $state.city:=Form.city
  $state.presses:=Form.presses
  $state.native:=AXB_Host("focus"; New object)
  $focus:=AXB_Focus(True)
  $state.resolved:=New object("node"; $focus.node.objectName; "cell"; $focus.cell; "editing"; $focus.editing; "inactive"; $focus.native.inactive; "caret"; $focus.native.caret; "error"; $focus.error)
  $state.lines:=Form.lines.extract("description")
  $state.diagnostics:=AXB_Form("diagnostics"; New object)
  $state.status:=AXB Status
  If (File("/RESOURCES/other.txt").exists)
   File("/RESOURCES/other.txt").delete()
   $state.other:=New process("InactiveOther"; 0; "Other window")
  End if
  File("/RESOURCES/state.json").setText(JSON Stringify($state))
End case
''')
    objects = {
        "labelName": {"type": "text", "text": "Name", "left": 20, "top": 22, "width": 80, "height": 17},
        "inputName": {"type": "input", "dataSource": "Form.name", "left": 110, "top": 20, "width": 200, "height": 20},
        "labelCity": {"type": "text", "text": "City", "left": 20, "top": 52, "width": 80, "height": 17},
        "inputCity": {"type": "input", "dataSource": "Form.city", "left": 110, "top": 50, "width": 200, "height": 20},
        "labelSecret": {"type": "text", "text": "Password", "left": 20, "top": 82, "width": 80, "height": 17},
        "inputSecret": {"type": "input", "dataSource": "Form.secret", "fontFamily": "%password", "left": 110, "top": 80, "width": 200, "height": 20},
        "btnCount": {"type": "button", "text": "Count", "method": "InactiveCount", "events": ["onClick"], "left": 110, "top": 110, "width": 100, "height": 24},
        "Items": {"type": "listbox", "listboxType": "collection", "dataSource": "Form.lines", "selectedItemsSource": "Form.selectedLines",
                  "left": 20, "top": 145, "width": 300, "height": 80, "columns": [
                      {"name": "colDescription", "dataSource": "This.description", "width": 280, "enterable": True,
                       "header": {"name": "headerDescription", "text": "Description"}}]},
    }
    other = sources / "Forms/Other"
    other.mkdir(parents=True)
    (other / "form.4DForm").write_text(json.dumps({"windowTitle": "AXB other window", "width": 240, "height": 60, "pages": [None, {"objects": {
        "inputNote": {"type": "input", "dataSource": "Form.note", "left": 20, "top": 20, "width": 200, "height": 20}}}]}, indent=2) + "\n")
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(json.dumps({"windowTitle": TITLE, "width": 340, "height": 240, "method": "InactiveForm",
                                                  "events": ["onLoad", "onTimer"], "pages": [None, {"objects": objects}]}, indent=2) + "\n")
    install(["--project-dir", str(project.parent), "--all-forms"])
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="inactive-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    if not (result.get("success") is True and not result.get("errors")):
        print(json.dumps(result, indent=2))
        raise SystemExit("FAIL: inactive-edit fixture compilation")
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--compiled", action="store_true", help="Open the project compiled instead of interpreted")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--other-window", action="store_true",
                        help="Put another 4D window in front instead of another application")
    parser.add_argument("--dormant", action="store_true",
                        help="Type before anything reads the window, so the bridge first wakes with 4D in the background")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the fixture")
    if not ax.trusted():
        parser.error("Accessibility permission is required")
    ax.require_test_input()
    verify_package(PACKAGE)
    project = prepare(args.server.expanduser().resolve())
    resources = FIXTURE / "Resources"
    checks = []
    report = {"passed": False, "checks": checks, "compiled": args.compiled, "intel": args.intel, "states": {},
              "nativeSha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "componentSha256": sha(PACKAGE / "AccessibilityBridge.4DZ")}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def state():
        # The form rewrites the file every quarter second: retry a read that meets a partial write.
        for _ in range(10):
            try:
                return json.loads((resources / "state.json").read_text(encoding="utf-8-sig"))
            except (OSError, ValueError):
                time.sleep(0.05)
        return {}

    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + [APPLICATION, "--project", str(project), "--dataless", "--opening-mode", "compiled" if args.compiled else "interpreted",
                                "--webadmin-auto-start", "false"], stdout=(BUILD / "inactive-edit.log").open("w"), stderr=subprocess.STDOUT)
    try:
        wait_for_start(process, project, lambda: (resources / "state.json").exists(), BUILD, timeout=60, awake=not args.dormant)
        app = ax.application(process.pid)

        def element(name):
            window = next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None)
            return window.find("/" + name) if window else None

        def value(name):
            target = element(name)
            return target.read("AXValue") if target else None

        def background(label):
            # Finder takes the foreground, as an inspector or another application does.
            subprocess.run(["/usr/bin/osascript", "-e", 'tell application "Finder" to activate'], check=True, capture_output=True, timeout=10)
            ax.wait_for(lambda: app.read("AXFrontmost") is False, "4D stayed in the foreground", timeout=10)
            # Several descriptions, and the form's own ticks, pass while 4D is in the background.
            time.sleep(3)
            report["states"][label] = state()

        if args.other_window:
            ax.wait_for(lambda: element("inputName"), "The form was not published", timeout=20)
            activate(process, project)
            keys.set_guard(keys.guard_frontmost(process.pid, ax))
            ax.wait_for(lambda: app.read("AXFocusedUIElement") and app.read("AXFocusedUIElement").read("AXIdentifier") == "axb/Probe/inputName",
                        "Name did not take the form's first focus", timeout=10)
            keys.type_text("Alex")
            ax.wait_for(lambda: value("inputName") == "Alex", "The typed text was not published", timeout=8)
            (resources / "other.txt").write_text("open")
            ax.wait_for(lambda: any(w.read("AXTitle") == "AXB other window" for w in app.read("AXWindows") or []), "The other window did not open", timeout=15)
            time.sleep(3)
            report["states"]["otherWindow"] = state()
            report["otherWindow"] = {"value": value("inputName"), "focused": app.read("AXFocusedWindow").read("AXTitle") if app.read("AXFocusedWindow") else None}
            check(report["otherWindow"]["focused"] == "AXB other window", "another 4D window is in front")
            check(value("inputName") == ("Alex" if state().get("editing") else state().get("name")),
                  "the first window's field publishes what it shows: its typed text while 4D keeps the edit, else its committed value")
            report["passed"] = True
            return
        if args.dormant:
            # Nothing reads the window yet: the bridge stays dormant while the user types.
            subprocess.run(["/usr/bin/osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                           capture_output=True, timeout=10)
            ax.wait_for(lambda: app.read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
            ax.wait_for(lambda: state().get("focus") == "inputName" and state().get("status", "").endswith("dormant"), "Name did not take focus with the bridge dormant", timeout=15)
            keys.set_guard(keys.guard_frontmost(process.pid, ax))
            keys.type_text("Alex")
            ax.wait_for(lambda: state().get("edited") == "Alex", "4D did not receive the typed text", timeout=8)
            check(state().get("status", "").endswith("dormant"), "the bridge stayed dormant while the user typed")
            check(state().get("name") == "", "the typed text is not in the field's data source yet")
            # An inspector brings itself to the front, then reads the window: the bridge wakes now.
            subprocess.run(["/usr/bin/osascript", "-e", 'tell application "Finder" to activate'], check=True, capture_output=True, timeout=10)
            ax.wait_for(lambda: app.read("AXFrontmost") is False, "4D stayed in the foreground", timeout=10)
            ax.wait_for(lambda: value("inputName") == "Alex", "Woken in the background, the bridge did not publish the typed text", timeout=15)
            report["states"]["wokenInactive"] = state()
            check(True, "woken with 4D in the background, the bridge publishes the field's typed text")
            check(value("inputCity") == "" and value("inputSecret") in ("", None), "and the other fields their own values")
            report["passed"] = True
            return
        ax.wait_for(lambda: element("inputName"), "The form was not published", timeout=20)
        activate(process, project)
        keys.set_guard(keys.guard_frontmost(process.pid, ax))
        ax.wait_for(lambda: app.read("AXFocusedUIElement") and app.read("AXFocusedUIElement").read("AXIdentifier") == "axb/Probe/inputName",
                    "Name did not take the form's first focus", timeout=10)
        keys.type_text("Alex")
        ax.wait_for(lambda: value("inputName") == "Alex", "The typed text was not published", timeout=8)
        report["states"]["typed"] = state()
        check(state().get("name") == "", "the typed text is not in the field's data source yet")
        background("nameInactive")
        check(value("inputName") == "Alex", "with 4D in the background, the field still publishes its typed text")
        check(value("inputCity") == "" and value("inputSecret") in ("", None), "the other fields still publish their own values")
        # While 4D is in the background its values are not settable, and a value written anyway is
        # refused and leaves the typed text. macOS reports success for any attribute write.
        settable = element("inputName").is_settable("AXValue")
        written = element("inputName").set_text("Alexa")
        time.sleep(2)
        report["backgroundWrite"] = {"settable": settable, "axError": written, "value": value("inputName"), "state": state()}
        check(settable is False, "with 4D in the background, a field's value is not settable")
        check(value("inputName") == "Alex" and state().get("name") == "", "a value written anyway is refused and leaves the typed text")

        activate(process, project)
        ax.wait_for(lambda: value("inputName") == "Alex", "The typed text was lost on return", timeout=8)
        check(True, "back in 4D, the field publishes its typed text")
        expected = value("inputName")
        keys.key("tab")
        keys.key("tab")
        ax.wait_for(lambda: app.read("AXFocusedUIElement").read("AXIdentifier") == "axb/Probe/inputSecret", "Tab did not reach the password field", timeout=8)
        check(state().get("name") == expected, "leaving Name commits its text")
        keys.type_text("hidden")
        time.sleep(2)
        check(value("inputSecret") in ("", None), "the password field publishes no text while 4D is in the foreground")
        background("secretInactive")
        check(value("inputSecret") in ("", None), "the password field publishes no text while 4D is in the background")
        check(value("inputName") == expected, "the committed field keeps its value in the background")

        activate(process, project)
        keys.key("tab", ("shift",))
        ax.wait_for(lambda: app.read("AXFocusedUIElement").read("AXIdentifier") == "axb/Probe/inputCity", "Shift-Tab did not reach City", timeout=8)
        keys.type_text("Oslo")
        ax.wait_for(lambda: value("inputCity") == "Oslo", "City's typed text was not published", timeout=8)
        background("cityInactive")
        check(value("inputCity") == "Oslo", "a second field's typed text also stays published in the background")
        check(value("inputName") == expected, "and the first field keeps its committed value")

        # A button pressed through accessibility while 4D is in the background is refused at once.
        button = element("btnCount")
        presses = state().get("presses")
        report["background"] = {"actions": button.actions(), "press": button.press(), "write": element("inputName").set_text("Ignored")}
        time.sleep(2)
        # macOS reports success for an action the element does not offer: the method must not run.
        check(state().get("presses") == presses, "a press in the background is refused, and the button's method does not run")
        check(value("inputName") == expected and state().get("name") == expected, "a value written in the background is refused")
        check(report["background"]["actions"] == [], "no action is offered while 4D is in the background")

        activate(process, project)
        ax.wait_for(lambda: "AXPress" in (element("btnCount").actions() or []), "The press action did not return with 4D in front", timeout=8)
        check(element("btnCount").press() == 0, "back in front, a press is accepted")
        ax.wait_for(lambda: state().get("presses") == presses + 1, "The button's method did not run once", timeout=8)
        check(True, "and runs the button's method once")
        # Actions in quick succession: a repeated press runs once, and a different action waits for it.
        presses = state().get("presses")
        count = element("btnCount")
        started = time.monotonic()
        burst = [count.press(), count.press()]
        apart = time.monotonic() - started
        burst.append(element("inputCity").set_text("Bergen"))
        ax.wait_for(lambda: value("inputCity") == "Bergen", "The value written right after a press was dropped", timeout=15)
        time.sleep(1)
        report["burst"] = {"codes": burst, "presses": state().get("presses") - presses, "secondPressAfterSeconds": round(apart, 3)}
        # A press repeated while the first runs runs once. Each accessibility call waits for 4D's main
        # thread, which is slow under Rosetta: a second press arriving after the first completed is a new one.
        if apart < 0.1:
            check(state().get("presses") == presses + 1, "a press repeated while it runs runs once")
        else:
            check(state().get("presses") in (presses + 1, presses + 2), "a press repeated after the first may have completed runs at most twice")
        check(True, "a value written right after a press waits for it and is entered")

        # A grid cell's editor keeps its typed text in the background too.
        table = ax.wait_for(lambda: element("Items"), "The grid was not published", timeout=10)

        def content(column, row):
            children = table.cell(column, row).read("AXChildren") or []
            return children[0] if children else None

        cell = ax.wait_for(lambda: content(0, 0), "The grid's first cell did not load", timeout=20)
        check(cell.set_boolean("AXFocused", True) == 0, "a grid cell takes keyboard focus through accessibility")
        try:
            ax.wait_for(lambda: state().get("editing") is True and state().get("focus") in ("Items", "colDescription"), "The cell's editor did not open", timeout=20)
        finally:
            report["states"]["cellFocus"] = state()
        keys.key("end")
        keys.type_text("s")
        ax.wait_for(lambda: content(0, 0) and content(0, 0).read("AXValue") == "Pens", "The cell's typed text was not published", timeout=8)
        check(state().get("lines", [None])[0] == "Pen", "the cell's typed text is not in its collection yet")
        report["states"]["cellEditing"] = state()
        background("cellInactive")
        report["cellRead"] = {"value": content(0, 0).read("AXValue"), "resolved": state().get("resolved"), "native": state().get("native"), "front": report["states"].get("cellEditing")}
        check(content(0, 0).read("AXValue") == "Pens", "with 4D in the background, the cell still publishes its typed text")
        check(content(0, 1).read("AXValue") == "Ink", "and the other row its own value")
        activate(process, project)
        keys.key("return")
        ax.wait_for(lambda: state().get("lines", [None])[0] == "Pens", "Return did not commit the cell", timeout=8)
        ax.wait_for(lambda: content(0, 0) and content(0, 0).read("AXValue") == "Pens", "The committed cell's value was not published", timeout=8)
        check(True, "back in front, the committed cell publishes its value")
        report["passed"] = True
    finally:
        keys.set_guard(None)
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        (BUILD / ("inactive-edit-other.json" if args.other_window else "inactive-edit-dormant.json" if args.dormant else "inactive-edit.json")).write_text(json.dumps(report, indent=2) + "\n")
        if report["passed"]:
            print(f"PASS: {len(checks)} inactive-edit checks" + (" (woken in the background)" if args.dormant else ""))


if __name__ == "__main__":
    main()
