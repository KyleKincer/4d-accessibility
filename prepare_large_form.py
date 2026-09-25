#!/usr/bin/env python3
"""Compile a complete large form and a long note for external AX validation."""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import (
    BUILD,
    PACKAGE,
    ROOT,
    literal,
    project_at,
    run_utility,
    sha,
    verify_package,
)

FIXTURE = BUILD / "large-form-fixture"
TITLE = "AXB complete large form"
NOTE = ("Readable note text. " * 4000)[:65536] + "END-OF-NOTE"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--debounced", action="store_true", help="Exercise a search that submits after one second without a keystroke")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("large-form-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "LargeForm")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(
        BUILD / "AccessibilityBridge.bundle",
        FIXTURE / "Plugins/AccessibilityBridge.bundle",
    )
    for source in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(source, methods / source.name)
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text("""var $window : Integer
var $data : Object
var $bar; $menu : Text
var $item : Object
ON ERR CALL("LargeError")
$bar:=Create menu
$menu:=Create menu
For each ($item; New collection(New object("label"; "Undo"; "action"; ak undo); New object("label"; "Redo"; "action"; ak redo)))
 APPEND MENU ITEM($menu; $item.label)
 SET MENU ITEM PROPERTY($menu; -1; Associated standard action name; $item.action)
 SET MENU ITEM SHORTCUT($menu; -1; "Z"; Command key mask+Choose($item.label="Redo"; Shift key mask; 0))
End for each
APPEND MENU ITEM($bar; "Edit"; $menu)
SET MENU BAR($bar; Current process)
$data:=New object("note"; File("/RESOURCES/note.txt").getText(); "ticks"; 0; "pressed"; ""; "beforeCount"; 0; "lastInputLength"; 0; "commits"; 0)
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("note"; $data.note; "pressed"; $data.pressed)))
CLOSE WINDOW($window)
QUIT 4D
""")
    (methods / "LargeError.4dm").write_text(
        'File("/RESOURCES/status.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
    )
    (methods / "LargeClick.4dm").write_text(
        "Form.pressed:=OBJECT Get name(Object current)\n"
    )
    (methods / "LargeInput.4dm").write_text("""Case of
 : (Form event code=On Before Keystroke)
  Form.beforeCount:=Form.beforeCount+1
  Form.lastInputLength:=Length(Keystroke)
  If (Form.lastInputLength>4096)
   Form.bulkInputLength:=Form.lastInputLength
  End if
  If (Position("[reject]"; Keystroke)>0)
   FILTER KEYSTROKE("")
  End if
 : (Form event code=On Data Change)
  Form.commits:=Form.commits+1
End case
""")
    (methods / "LargeForm.4dm").write_text("""var $reply; $state : Object
var $start; $end : Integer
var $focused; $named : Pointer
Case of
 : (Form event code=On Load)
  Form.start:=AXB_Form("start"; New object("label"; "Large form"; "controls"; New object("Note"; New object("label"; "Large note"))))
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  $state:=New object("ready"; True; "start"; Form.start; "ticks"; Form.ticks; "pressed"; Form.pressed; "bridgeError"; Form.axbError; "failure"; Form.axbFailure; "note"; Form.note)
  $state.compiled:=Is compiled mode
  $state.beforeCount:=Form.beforeCount
  $state.lastInputLength:=Form.lastInputLength
  $state.bulkInputLength:=Form.bulkInputLength
  $state.commits:=Form.commits
  If ((OBJECT Get name(Object with focus)="Note") & Is editing text)
   GET HIGHLIGHT(*; "Note"; $start; $end)
   $state.editor:=New object("selection"; New collection($start-1; $end-$start); "text"; Get edited text)
   $state.nativeFocus:=AXB_Host("focus"; New object)
   $focused:=OBJECT Get pointer(Object with focus)
   $named:=OBJECT Get pointer(Object named; "Note")
   $state.focusPointerMissing:=Is nil pointer($focused)
   $state.namedPointerMissing:=Is nil pointer($named)
   $state.focusBindingMatches:=$focused=$named
  End if
  File("/RESOURCES/status.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
""")
    if args.debounced:
        (methods / "Compiler_Large.4dm").write_text("C_TEXT(LargeScope; $0)\n")
        # Model application callbacks that make an idle poll costly enough to
        # reach the adaptive one-second delay. Pending edits must bypass it.
        (methods / "LargeScope.4dm").write_text('''#DECLARE() -> $scope : Text
var $until : Integer
$until:=Milliseconds+150
While (Milliseconds<$until)
End while
$scope:="search"
''')
        path = methods / "LargeInput.4dm"
        path.write_text(path.read_text().replace('Case of\n', '''Case of
 : (Form event code=On After Keystroke)
  Form.searchAt:=Milliseconds+1000
  Form.observedText:=Get edited text
  SET TIMER(60)
''', 1))
        path = methods / "LargeForm.4dm"
        path.write_text(path.read_text().replace('"label"; "Large form";', '"label"; "Large form"; "scope"; Formula(LargeScope);').replace('  Form.ticks:=Form.ticks+1', '''  If ((Form.searchAt#Null) && (Milliseconds>=Form.searchAt))
   Form.submitted:=Form.observedText
   OB REMOVE(Form; "searchAt")
   GOTO OBJECT(*; "Close")
   SET TIMER(6)
  End if
  Form.ticks:=Form.ticks+1''').replace('  $state.compiled:=Is compiled mode', '''  $state.submitted:=Form.submitted
  $state.observedText:=Form.observedText
  $state.compiled:=Is compiled mode'''))
    objects = {}
    for index in range(600):
        objects[f"Item{index:03}"] = {
            "type": "button",
            "text": str(index),
            "left": 10 + (index % 20) * 43,
            "top": 10 + (index // 20) * 20,
            "width": 40,
            "height": 18,
            "fontSize": 9,
            "method": "LargeClick",
            "events": ["onClick"],
        }
    objects["Note"] = {
        "type": "input",
        "dataSource": "Form.note",
        "multiline": "yes",
        "left": 10,
        "top": 620,
        "width": 750,
        "height": 120,
        "method": "LargeInput",
        "events": ["onBeforeKeystroke", "onDataChange"] + (["onAfterKeystroke"] if args.debounced else []),
    }
    objects["Close"] = {
        "type": "button",
        "text": "Close",
        "action": "cancel",
        "method": "LargeClick",
        "events": ["onClick"],
        "left": 770,
        "top": 650,
        "width": 100,
        "height": 28,
    }
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(
        json.dumps(
            {
                "windowTitle": TITLE,
                "width": 885,
                "height": 755,
                "method": "LargeForm",
                "events": ["onLoad", "onTimer", "onUnload"],
                "pages": [None, {"objects": objects}],
            },
            indent=2,
        )
        + "\n"
    )
    (FIXTURE / "Resources/note.txt").write_text("" if args.debounced else NOTE)
    hashes = {
        str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()
    }
    with tempfile.TemporaryDirectory(
        prefix="large-form-compile-", dir=BUILD
    ) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(
            server / "Contents/MacOS" / info["CFBundleExecutable"],
            driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f"$options.plugins:=Folder({literal(FIXTURE / 'Plugins')})\n"
            f"$options.components:=New collection(File({literal(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')}))\n"
            f"$result:=Compile project(File({literal(project)}); $options)",
            90,
        )
    report = {
        "passed": compiled.get("success") is True and not compiled.get("errors"),
        "compiler": compiled,
        "sources_sha256": hashes,
        "native_sha256": sha(
            FIXTURE
            / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
        ),
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
        "debounced": args.debounced,
    }
    (BUILD / "large-form-compile-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(("PASS" if report["passed"] else "FAIL") + ": large form compilation")
    if not report["passed"]:
        print(compiled)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
