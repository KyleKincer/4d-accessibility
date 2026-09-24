#!/usr/bin/env python3
"""Compile array, object, scalar and numeric combos with existing handlers."""

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

FIXTURE = BUILD / "combo-controls-fixture"
TITLE = "AXB combo controls"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("combo-controls-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "ComboControls")
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
ON ERR CALL("ComboError")
$bar:=Create menu
$menu:=Create menu
For each ($item; New collection(New object("label"; "Undo"; "action"; ak undo); New object("label"; "Redo"; "action"; ak redo)))
 APPEND MENU ITEM($menu; $item.label)
 SET MENU ITEM PROPERTY($menu; -1; Associated standard action name; $item.action)
 SET MENU ITEM SHORTCUT($menu; -1; "Z"; Command key mask+Choose($item.label="Redo"; Shift key mask; 0))
End for each
APPEND MENU ITEM($bar; "Edit"; $menu)
SET MENU BAR($bar; Current process)
ARRAY TEXT(ComboChoices; 3)
ComboChoices{0}:="Guitar"
ComboChoices{1}:="Guitar"
ComboChoices{2}:="Bass"
ComboChoices{3}:="Keyboard"
$data:=New object("ticks"; 0; "saved"; 0; "events"; New collection; "region"; "East"; "note"; "Existing note")
$data.wood:=New object("values"; New collection("Maple"; "Mahogany"; "Ash"); "currentValue"; "Maple"; "private"; "must-not-be-published")
$data.rating:=New object("values"; New collection(1.5; 2.5; 3.5); "currentValue"; 1.5)
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("saved"; $data.saved)))
CLOSE WINDOW($window)
QUIT 4D
""")
    (methods / "Compiler_Combo.4dm").write_text("ARRAY TEXT(ComboChoices; 0)\n")
    (methods / "ComboError.4dm").write_text(
        'File("/RESOURCES/status.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
    )
    (methods / "ComboEvent.4dm").write_text("""var $name : Text
$name:=OBJECT Get name(Object current)
Form.events.push(New object("object"; $name; "event"; Form event code))
If ((Form event code=On Before Keystroke) & (Keystroke="#"))
 FILTER KEYSTROKE("")
End if
If ((Form event code=On Data Change) & ($name="Wood") & (Form.wood.currentValue="Invalid"))
 Form.wood.currentValue:="Maple"
 Form.rejected:=True
End if
If ((Form event code=On Clicked) & ($name="Save"))
 Form.saved:=Form.saved+1
End if
""")
    (methods / "ComboForm.4dm").write_text("""var $reply; $state; $controls : Object
Case of
 : (Form event code=On Load)
  $controls:=New object("Instrument"; New object("label"; "Instrument"); "Wood"; New object("label"; "Wood"); "Region"; New object("label"; "Region"); "Rating"; New object("label"; "Rating"); "Note"; New object("label"; "Note"))
  OBJECT SET FORMAT(*; "Rating"; "0.0")
  Form.start:=AXB_Form("start"; New object("label"; "Product choices"; "controls"; $controls))
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  $state:=New object("ready"; True; "start"; Form.start; "ticks"; Form.ticks; "saved"; Form.saved; "events"; Form.events; "bridgeError"; Form.axbError; "failure"; Form.axbFailure)
  $state.discovery:=Form.axbView.discovery
  $state.instrument:=ComboChoices{0}
  $state.wood:=Form.wood.currentValue
  $state.woodChoices:=Form.wood.values
  $state.region:=Form.region
  $state.rating:=Form.rating.currentValue
  $state.rejected:=Form.rejected
  If (Is editing text)
   $state.editor:=New object("object"; OBJECT Get name(Object with focus); "text"; Get edited text)
  End if
  File("/RESOURCES/status.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
""")
    events = [
        "onClick",
        "onBeforeKeystroke",
        "onAfterKeystroke",
        "onDataChange",
        "onGettingFocus",
        "onLosingFocus",
    ]
    objects = {
        "Instrument": {
            "type": "combo",
            "dataSource": "ComboChoices",
            "left": 25,
            "top": 25,
            "width": 260,
            "height": 28,
            "method": "ComboEvent",
            "events": events,
        },
        "Wood": {
            "type": "combo",
            "dataSource": "Form.wood",
            "dataSourceTypeHint": "object",
            "automaticInsertion": True,
            "left": 25,
            "top": 75,
            "width": 260,
            "height": 28,
            "method": "ComboEvent",
            "events": events,
        },
        "Region": {
            "type": "combo",
            "dataSource": "Form.region",
            "choiceList": ["East", "West", "South"],
            "left": 25,
            "top": 125,
            "width": 260,
            "height": 28,
            "method": "ComboEvent",
            "events": events,
        },
        "Rating": {
            "type": "combo",
            "dataSource": "Form.rating",
            "dataSourceTypeHint": "object",
            "left": 25,
            "top": 175,
            "width": 260,
            "height": 28,
            "method": "ComboEvent",
            "events": events,
        },
        "Note": {
            "type": "input",
            "dataSource": "Form.note",
            "left": 25,
            "top": 225,
            "width": 260,
            "height": 28,
        },
        "Save": {
            "type": "button",
            "text": "Save choices",
            "left": 25,
            "top": 280,
            "width": 130,
            "height": 28,
            "method": "ComboEvent",
            "events": ["onClick"],
        },
        "Close": {
            "type": "button",
            "text": "Close",
            "action": "cancel",
            "left": 195,
            "top": 280,
            "width": 90,
            "height": 28,
            "method": "ComboEvent",
            "events": ["onClick"],
        },
    }
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(
        json.dumps(
            {
                "windowTitle": TITLE,
                "width": 320,
                "height": 330,
                "method": "ComboForm",
                "events": ["onLoad", "onTimer", "onUnload"],
                "pages": [None, {"objects": objects}],
            },
            indent=2,
        )
    )
    hashes = {
        str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()
    }
    with tempfile.TemporaryDirectory(
        prefix="combo-controls-compile-", dir=BUILD
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
    }
    (BUILD / "combo-controls-compile-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(("PASS" if report["passed"] else "FAIL") + ": combo controls compilation")
    if not report["passed"]:
        print(compiled)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
