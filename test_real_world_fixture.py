#!/usr/bin/env python3
"""Check that a form stays accessible through what real applications do to it.

The fixture is a form with the bridge's area and ordinary controls. Through accessibility only,
the test checks that:

- the application can still serialize its form's data: JSON Stringify(Form) succeeds, and the
  data holds only the application's own properties;
- a static text longer than a label's bound, a value longer than the text bound and a character
  cut in half by Substring cost only those controls' detail, not the window;
- a button behind a floating palette that has the keyboard still runs when pressed;
- after an error in a callback the bridge stops the window's session, then starts it again by
  itself once the callback works;
- while a field is edited, each character's bounds and the caret's are published within it.
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

FIXTURE = BUILD / "real-world-fixture"
APPLICATION = "/Applications/4D/4D.app/Contents/MacOS/4D"
TITLE = "AXB real world"
INSTRUCTIONS = "Instructions: " + "Fill every field before saving. " * 25


def prepare(server, compiled):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("real-world-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "RealWorld")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("RealError")
var $window : Integer
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; New object("name"; ""; "presses"; 0; "big"; ""; "status"; ""; "fail"; False; \\
 "rows"; New collection(New object("name"; "Alpha"); New object("name"; "Bravo"))))
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "RealError.4dm").write_text('var $file : 4D.File\n$file:=File("/RESOURCES/errors.txt")\nIf (Not($file.exists))\n $file.setText("")\nEnd if\n'
                                            '$file.setText($file.getText()+String(Error)+" "+Error method+" "+String(Error line)+Char(10))\n')
    (methods / "RealCount.4dm").write_text("Form.presses:=Form.presses+1\n")
    (methods / "RealSerialize.4dm").write_text('var $text : Text\n$text:=JSON Stringify(Form)\nForm.status:=String(Length($text))+" "+OB Keys(Form).join(",")\n')
    (methods / "RealPalette.4dm").write_text('var $process : Integer\n$process:=New process("RealPaletteRun"; 0; "Palette")\n')
    (methods / "RealPaletteRun.4dm").write_text('var $window : Integer\n$window:=Open form window("Palette"; Palette form window; 50; 50)\nDIALOG("Palette"; New object("note"; ""))\nCLOSE WINDOW($window)\n')
    (methods / "AXB_Configure.4dm").write_text('#DECLARE($formName : Text) -> $options : Object\nIf ($formName="Probe")\n'
        ' $options:=New object("grids"; New object("Rows"; New object("kind"; "collection"; "keyProperty"; "name"; "label"; "Rows"; "ready"; Formula(RealReady))))\nEnd if\n')
    # A callback that fails while Form.fail is set, as an application formula can.
    (methods / "RealReady.4dm").write_text('#DECLARE -> $ready : Boolean\nvar $missing : Object\nIf (Form.fail=True)\n $missing.deeper:=1\nEnd if\n$ready:=True\n')
    (methods / "Compiler_RealWorld.4dm").write_text("C_TEXT(AXB_Configure; $1)\nC_OBJECT(AXB_Configure; $0)\nC_BOOLEAN(RealReady; $0)\n")
    # The form applies a command file on its timer, and records its own state.
    (methods / "RealForm.4dm").write_text('''var $state; $command : Object
var $file : 4D.File
Case of
 : (Form event code=On Load)
  SET TIMER(15)
 : (Form event code=On Timer)
  $file:=File("/RESOURCES/command.json")
  If ($file.exists)
   $command:=JSON Parse($file.getText())
   $file.delete()
   Case of
    : ($command.op="set")
     Form[$command.key]:=$command.value
    : ($command.op="big")
     Form.big:="x"*$command.length
    : ($command.op="cut")
     Form.big:=Substring("Smile "+Char(55357)+Char(56832)+" ok"; 1; 7)
   End case
  End if
  $state:=New object("focus"; OBJECT Get name(Object with focus); "editing"; Is editing text; "presses"; Form.presses; "status"; Form.status; "name"; Form.name)
  $state.diagnostics:=AXB_Form("diagnostics"; New object)
  $state.areas:=AXB_Area("diagnostics"; ""; "")
  File("/RESOURCES/state.json").setText(JSON Stringify($state))
End case
''')
    objects = {
        "labelName": {"type": "text", "text": "Name", "left": 20, "top": 22, "width": 80, "height": 17},
        "inputName": {"type": "input", "dataSource": "Form.name", "left": 110, "top": 20, "width": 200, "height": 20},
        "labelCity": {"type": "text", "text": "City", "left": 20, "top": 52, "width": 80, "height": 17},
        "inputCity": {"type": "input", "dataSource": "Form.city", "left": 110, "top": 50, "width": 200, "height": 20},
        "btnCount": {"type": "button", "text": "Count", "method": "RealCount", "events": ["onClick"], "left": 20, "top": 80, "width": 90, "height": 24},
        "btnSerialize": {"type": "button", "text": "Serialize", "method": "RealSerialize", "events": ["onClick"], "left": 120, "top": 80, "width": 90, "height": 24},
        "btnPalette": {"type": "button", "text": "Palette", "method": "RealPalette", "events": ["onClick"], "left": 220, "top": 80, "width": 90, "height": 24},
        "textInstructions": {"type": "text", "text": INSTRUCTIONS, "left": 20, "top": 112, "width": 400, "height": 60},
        "labelNotes": {"type": "text", "text": "Notes", "left": 20, "top": 182, "width": 80, "height": 17},
        "inputNotes": {"type": "input", "dataSource": "Form.big", "left": 110, "top": 180, "width": 310, "height": 20},
        "Rows": {"type": "listbox", "listboxType": "collection", "dataSource": "Form.rows", "left": 20, "top": 210, "width": 400, "height": 60,
                 "columns": [{"name": "colRowName", "dataSource": "This.name", "width": 380, "header": {"name": "hdrRowName", "text": "Name"}}]},
    }
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(json.dumps({"windowTitle": TITLE, "width": 440, "height": 290, "method": "RealForm",
                                                  "events": ["onLoad", "onTimer"], "pages": [None, {"objects": objects}]}, indent=2) + "\n")
    palette = sources / "Forms/Palette"
    palette.mkdir(parents=True)
    (palette / "form.4DForm").write_text(json.dumps({"windowTitle": "AXB palette", "width": 260, "height": 60, "pages": [None, {"objects": {
        "inputNote": {"type": "input", "dataSource": "Form.note", "left": 20, "top": 20, "width": 220, "height": 20}}}]}, indent=2) + "\n")
    install(["--project-dir", str(project.parent), "--form", "Probe"])
    if compiled:
        info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
        with tempfile.TemporaryDirectory(prefix="real-world-compile-", dir=BUILD) as temporary:
            driver = Path(temporary)
            project_at(driver, "Driver")
            result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
                '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
                f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
                f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
                f'$result:=Compile project(File({literal(project)}); $options)', 120)
        if not (result.get("success") is True and not result.get("errors")):
            print(json.dumps(result, indent=2))
            raise SystemExit("FAIL: real-world fixture compilation")
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--compiled", action="store_true", help="Open the project compiled instead of interpreted")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the fixture")
    if not ax.trusted():
        parser.error("Accessibility permission is required")
    ax.require_test_input()
    verify_package(PACKAGE)
    project = prepare(args.server.expanduser().resolve(), args.compiled)
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

    def command(op, **values):
        (resources / "command.json").write_text(json.dumps(dict(op=op, **values)))

    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + [APPLICATION, "--project", str(project), "--dataless",
                                "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"],
                               stdout=(BUILD / "real-world.log").open("w"), stderr=subprocess.STDOUT)
    try:
        wait_for_start(process, project, lambda: (resources / "state.json").exists(), BUILD, timeout=60)
        app = ax.application(process.pid)

        def window(title=TITLE):
            return next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == title), None)

        def element(name):
            current = window()
            return current.find("/" + name) if current else None

        def value(name):
            target = element(name)
            return target.read("AXValue") if target else None

        activate(process, project)
        keys.set_guard(keys.guard_frontmost(process.pid, ax))
        ax.wait_for(lambda: element("btnCount"), "The form was not published", timeout=30)

        # The form's data stays the application's own.
        check(element("btnSerialize").press() == 0, "Serialize is pressed")
        ax.wait_for(lambda: state().get("status"), "Serialize did not run", timeout=10)
        length, keys_seen = state()["status"].split(" ", 1)
        report["serialized"] = state()["status"]
        check(int(length) > 0, "JSON Stringify(Form) succeeds while the bridge describes the form")
        check(not [key for key in keys_seen.split(",") if key.startswith("axb")], "the form's data holds only the application's properties")

        # What a real form holds beyond the bridge's bounds costs a control's detail, not the window.
        instructions = element("textInstructions")
        label = instructions.read("AXDescription") or "" if instructions else ""
        check(instructions is not None and instructions.read("AXValue") == INSTRUCTIONS,
              "a static text longer than a label's bound is published, its value whole")
        check(len(label) == 512 and label.endswith("\u2026") and INSTRUCTIONS.startswith(label[:-1]), "and its label shortened, with an ellipsis")
        command("big", length=1100000)
        ax.wait_for(lambda: len(value("inputNotes") or "") == 1024 * 1024, "A value longer than the text bound was not published", timeout=15)
        notes = element("inputNotes")
        check(notes.is_settable("AXValue") is False, "a value longer than the text bound is published shortened, and cannot be written back")
        check(element("btnCount") is not None and state()["diagnostics"].get("repairs", 0) >= 1, "the rest of the window stays published, and the repairs are reported")
        command("set", key="big", value="short")
        ax.wait_for(lambda: value("inputNotes") == "short" and element("inputNotes").is_settable("AXValue"), "The notes field did not recover", timeout=15)
        check(True, "the field is published whole and editable again once its value is within bounds")
        command("cut")
        ax.wait_for(lambda: value("inputNotes") == "Smile �", "A character cut in half was not published", timeout=15)
        check(element("btnCount") is not None, "a character cut in half is published as U+FFFD, and the window stays")
        command("set", key="big", value="")

        # A floating palette that has the keyboard does not swallow an action behind it.
        presses = state()["presses"]
        check(element("btnPalette").press() == 0, "the palette is opened")
        ax.wait_for(lambda: window("AXB palette") is not None, "The palette did not open", timeout=15)
        activate(process, project)
        ax.wait_for(lambda: app.read("AXFocusedWindow") and app.read("AXFocusedWindow").read("AXTitle") == "AXB palette", "The palette did not take the keyboard", timeout=10)
        check(element("btnCount").press() == 0, "a button behind the palette is pressed")
        ax.wait_for(lambda: state().get("presses") == presses + 1, "The press behind the palette did not run", timeout=10)
        check(True, "the press runs the button's method, as a click would")

        # One failure does not leave the window inaccessible until it is reopened.
        command("set", key="fail", value=True)
        ax.wait_for(lambda: element("btnCount") is None, "The failing callback did not stop the window's session", timeout=15)
        report["states"]["failed"] = state()
        check(True, "an error in a callback stops the window's session")
        command("set", key="fail", value=False)
        started = time.monotonic()
        ax.wait_for(lambda: element("btnCount") is not None, "The window's session did not start again", timeout=90)
        report["restartSeconds"] = round(time.monotonic() - started, 1)
        check(True, "the session starts again by itself once the callback works")
        presses = state()["presses"]
        check(element("btnCount").press() == 0, "the restarted window takes a press")
        ax.wait_for(lambda: state().get("presses") == presses + 1, "The press after the restart did not run", timeout=10)
        check(True, "and runs it")

        # The field 4D edits reports each character's bounds, which Zoom and VoiceOver follow.
        palette = window("AXB palette")
        if palette:
            # Close the palette: the keyboard returns to the form.
            close = next((c for c in palette.read("AXChildren") or [] if c.read("AXSubrole") == "AXCloseButton"), None)
            if close:
                close.press()
        activate(process, project)
        name = element("inputName")
        check(name.set_boolean("AXFocused", True) == 0, "Name takes keyboard focus")
        ax.wait_for(lambda: state().get("focus") == "inputName", "Name did not take focus", timeout=10)
        keys.type_text("Alex")
        ax.wait_for(lambda: value("inputName") == "Alex", "The typed text was not published", timeout=8)
        time.sleep(0.6)
        name = element("inputName")
        position, size = name.read("AXPosition"), name.read("AXSize")
        first, caret = name.bounds(0, 1), name.bounds(4, 0)
        report["bounds"] = {"field": [position, size], "first": first, "caret": caret}
        check(first and first[2] > 0 and first[3] > 0 and position[0] <= first[0] < position[0] + size[0] and position[1] <= first[1] < position[1] + size[1],
              "the first character's bounds lie within the field")
        check(caret and caret[0] > first[0] and caret[3] > 0, "the caret's bounds follow the typed text")
        report["passed"] = True
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(10)
        (BUILD / ("real-world" + ("-intel" if args.intel else "") + ("-compiled" if args.compiled else "") + ".json")).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} real-world checks" + (" (compiled)" if args.compiled else "") + (" (Rosetta)" if args.intel else ""))


if __name__ == "__main__":
    main()
