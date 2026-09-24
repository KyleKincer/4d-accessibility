#!/usr/bin/env python3
"""Compile a complete status controls and a long note for external AX validation."""

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

FIXTURE = BUILD / "status-controls-fixture"
TITLE = "AXB complete status controls"


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
        FIXTURE.rename(BUILD / ("status-controls-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "StatusControls")
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
ON ERR CALL("StatusError")
$data:=New object("ticks"; 0; "pressed"; 0; "progress"; 35; "busy"; 1; "shipped"; False; "name"; "Ada"; "mixed"; 2; "flatMixed"; 2; "checkboxCalls"; 0)
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("pressed"; $data.pressed)))
CLOSE WINDOW($window)
QUIT 4D
""")
    (methods / "StatusError.4dm").write_text(
        'File("/RESOURCES/status.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
    )
    (
        methods / "StatusClick.4dm"
    ).write_text("""If (OBJECT Get name(Object current)="Ship")
 Form.pressed:=Form.pressed+1
 Form.progress:=100
 Form.busy:=0
 Form.shipped:=True
End if
If (New collection("Mixed"; "FlatMixed").indexOf(OBJECT Get name(Object current))>=0)
 Form.checkboxCalls:=Form.checkboxCalls+1
End if
""")
    (
        methods / "StatusForm.4dm"
    ).write_text("""var $reply; $state; $controls; $options : Object
Case of
 : (Form event code=On Load)
  $controls:=New object
  $controls.Progress:=New object("label"; "Packing progress"; "description"; Formula(String(Form.progress)+" items packed"))
  $controls.Busy:=New object("label"; "Sending invoice")
  $controls.Status:=New object("label"; "Shipment"; "description"; Formula(Choose(Form.shipped; "Shipped"; "Waiting to ship")))
  $controls.Decorative:=New object("decorative"; True)
  $controls.Name:=New object("label"; "Customer name")
  $options:=New object("label"; "Shipment details"; "controls"; $controls)
  Form.start:=AXB_Form("start"; $options)
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  $state:=New object("ready"; True; "start"; Form.start; "ticks"; Form.ticks; "pressed"; Form.pressed; "name"; Form.name; "bridgeError"; Form.axbError; "failure"; Form.axbFailure)
  $state.discovery:=Form.axbView.discovery
  $state.progress:=Form.progress
  $state.busy:=Form.busy
  $state.mixed:=Form.mixed
  $state.flatMixed:=Form.flatMixed
  $state.checkboxCalls:=Form.checkboxCalls
  $state.progressType:=OBJECT Get type(*; "Progress")
  $state.busyType:=OBJECT Get type(*; "Busy")
  File("/RESOURCES/status.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
""")
    objects = {
        "Order": {
            "type": "groupBox",
            "text": "Order",
            "left": 10,
            "top": 10,
            "width": 550,
            "height": 330,
        },
        "Shipping": {
            "type": "groupBox",
            "text": "Shipping",
            "left": 30,
            "top": 45,
            "width": 500,
            "height": 150,
        },
        "Name": {
            "type": "input",
            "dataSource": "Form.name",
            "left": 50,
            "top": 75,
            "width": 220,
            "height": 26,
        },
        "Ship": {
            "type": "button",
            "text": "Ship order",
            "left": 50,
            "top": 125,
            "width": 130,
            "height": 28,
            "method": "StatusClick",
            "events": ["onClick"],
        },
        "Mixed": {
            "type": "checkbox",
            "text": "Apply to selection",
            "dataSource": "Form.mixed",
            "dataSourceTypeHint": "integer",
            "threeState": True,
            "focusable": True,
            "left": 300,
            "top": 75,
            "width": 200,
            "height": 24,
            "method": "StatusClick",
            "events": ["onClick"],
        },
        "FlatMixed": {
            "type": "checkbox",
            "style": "flat",
            "text": "Include alternatives",
            "dataSource": "Form.flatMixed",
            "dataSourceTypeHint": "integer",
            "threeState": True,
            "focusable": False,
            "left": 300,
            "top": 125,
            "width": 200,
            "height": 24,
            "method": "StatusClick",
            "events": ["onClick"],
        },
        "Progress": {
            "type": "progress",
            "dataSource": "Form.progress",
            "dataSourceTypeHint": "integer",
            "left": 50,
            "top": 220,
            "width": 300,
            "height": 20,
            "min": 0,
            "max": 100,
            "enterable": False,
        },
        "Busy": {
            "type": "spinner",
            "dataSource": "Form.busy",
            "dataSourceTypeHint": "integer",
            "left": 380,
            "top": 215,
            "width": 30,
            "height": 30,
        },
        "Status": {
            "type": "picture",
            "picture": "/RESOURCES/status.svg",
            "left": 440,
            "top": 215,
            "width": 30,
            "height": 30,
        },
        "Decorative": {
            "type": "picture",
            "picture": "/RESOURCES/status.svg",
            "left": 50,
            "top": 285,
            "width": 25,
            "height": 25,
        },
        "Undescribed": {
            "type": "picture",
            "picture": "/RESOURCES/status.svg",
            "left": 100,
            "top": 285,
            "width": 25,
            "height": 25,
        },
        "Hidden": {
            "type": "picture",
            "picture": "/RESOURCES/status.svg",
            "left": 140,
            "top": 285,
            "width": 25,
            "height": 25,
            "visibility": "hidden",
        },
        "Close": {
            "type": "button",
            "text": "Close",
            "action": "cancel",
            "left": 420,
            "top": 365,
            "width": 100,
            "height": 28,
            "method": "StatusClick",
            "events": ["onClick"],
        },
    }
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(
        json.dumps(
            {
                "windowTitle": TITLE,
                "width": 575,
                "height": 415,
                "method": "StatusForm",
                "events": ["onLoad", "onTimer", "onUnload"],
                "pages": [None, {"objects": objects}],
            },
            indent=2,
        )
    )
    (FIXTURE / "Resources/status.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30"><circle cx="15" cy="15" r="12" fill="green"/></svg>'
    )
    hashes = {
        str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()
    }
    with tempfile.TemporaryDirectory(
        prefix="status-controls-compile-", dir=BUILD
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
    (BUILD / "status-controls-compile-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(("PASS" if report["passed"] else "FAIL") + ": status controls compilation")
    if not report["passed"]:
        print(compiled)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
