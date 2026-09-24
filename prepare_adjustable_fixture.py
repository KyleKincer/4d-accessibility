#!/usr/bin/env python3
"""Prepare typed steppers, rulers and progress controls for AX/VoiceOver tests."""

import argparse
import json
import plistlib
import shutil
import subprocess
import uuid
from pathlib import Path

from build_component import (
    PACKAGE,
    literal,
    project_at,
    run_utility,
    sha,
    verify_package,
)

root = Path(__file__).resolve().parent
fixture = root / "build/adjustable-controls-fixture"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--server", required=True, type=Path)
args = parser.parse_args()
assert (
    subprocess.run(["pgrep", "-x", "4D"], capture_output=True, check=False).returncode
    != 0
), "Close 4D before preparing the fixture"
server_app = args.server.expanduser().resolve()
info = plistlib.loads((server_app / "Contents/Info.plist").read_bytes())
assert info.get("CFBundleIdentifier") == "com.4D.4DServer"
verify_package(PACKAGE)
if fixture.exists():
    fixture.rename(root / ("build/adjustable-controls-previous-" + uuid.uuid4().hex))
project = project_at(fixture, "Adjustable")
sources = fixture / "Project/Sources"
methods = sources / "Methods"
shutil.copytree(PACKAGE, fixture / "Components/AccessibilityBridge.4dbase")
shutil.copytree(
    root / "build/AccessibilityBridge.bundle",
    fixture / "Plugins/AccessibilityBridge.bundle",
)
for p in (root / "host/OptionalMethods").glob("*.4dm"):
    shutil.copy2(p, methods / p.name)
(sources / "DatabaseMethods").mkdir()
(sources / "DatabaseMethods/onStartup.4dm").write_text("""var $window : Integer
ON ERR CALL("ProbeError")
ProbeDate:=!2026-09-24!
ProbeTime:=?09:00:00?
$window:=Open form window("Root"; Plain form window)
DIALOG("Root"; New object("amount"; 4; "disabled"; 5; "readonly"; 5; "scale"; 25; "temperature"; 5; "unconfigured"; 5; "vertical"; 5; "fractional"; 0.5; "dense"; 5000; "rejectedProgress"; 5; "rejected"; 4; "text"; "unchanged"; "sequence"; 0; "events"; New collection))
CLOSE WINDOW($window)
QUIT 4D
""")
(methods / "Compiler_Probe.4dm").write_text("C_DATE(ProbeDate; ProbeRulerDate)\nC_TIME(ProbeTime; ProbeProgressTime; ProbeReadOnlyTime)\nC_LONGINT(ProbeLong)\nC_OBJECT(ProbeAdjust; $1)\nC_TEXT(ProbeChange; $1; $3)\nC_REAL(ProbeChange; $2)\n")
(methods / "ProbeError.4dm").write_text(
    'File("/RESOURCES/status.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
)
(methods / "ProbeEvent.4dm").write_text(
    'ProbeChange(OBJECT Get name(Object current); 0; String(Form event code))\n'
)
(methods / "ProbeAdjust.4dm").write_text(
    '#DECLARE($request : Object)\nProbeChange($request.objectName; $request.delta; "accessibility")\n'
)
(methods / "ProbeChange.4dm").write_text("""#DECLARE($name : Text; $delta : Real; $origin : Text)
var $minimumDate; $maximumDate; $date : Date
var $minimum; $maximum; $number : Real
var $time : Time
var $value : Variant
$value:=OBJECT Get value($name)
If (($delta#0) & Not(Form.rejectTyped=True))
 If (Value type($value)=Is date)
  OBJECT GET MINIMUM VALUE(*; $name; $minimumDate)
  OBJECT GET MAXIMUM VALUE(*; $name; $maximumDate)
  $date:=$value+$delta
  If ($date<$minimumDate)
   $date:=$minimumDate
  End if
  If ($date>$maximumDate)
   $date:=$maximumDate
  End if
  OBJECT SET VALUE($name; $date)
 Else
  OBJECT GET MINIMUM VALUE(*; $name; $minimum)
  OBJECT GET MAXIMUM VALUE(*; $name; $maximum)
  $number:=New collection($maximum; New collection($minimum; Num($value)+$delta).max()).min()
  If (Value type($value)=Is time)
   $time:=?00:00:00?+$number
   OBJECT SET VALUE($name; $time)
  Else
   OBJECT SET VALUE($name; $number)
  End if
 End if
End if
Form.events.push(New object("name"; $name; "event"; $origin; "value"; OBJECT Get value($name); "focus"; OBJECT Get name(Object with focus)))
If (($name="LongStepper") && (Form.rejectTyped=True))
 ProbeLong:=4
End if
If ($name="Rejected")
 Form.rejected:=4
End if
If ($name="RejectedProgress")
 Form.rejectedProgress:=5
End if
If (($name="DateProgress") && (Form.shiftDateRange=True))
 OBJECT GET MINIMUM VALUE(*; "DateProgress"; $minimumDate)
 OBJECT GET MAXIMUM VALUE(*; "DateProgress"; $maximumDate)
 OBJECT SET MINIMUM VALUE(*; "DateProgress"; $minimumDate+1)
 OBJECT SET MAXIMUM VALUE(*; "DateProgress"; $maximumDate+1)
End if
""")
(methods / "ProbeForm.4dm").write_text("""var $command; $state; $reply; $controls : Object
var $name : Text
var $left; $top; $right; $bottom; $x; $y : Integer
ARRAY TEXT($order; 0)
Case of
 : (Form event code=On Load)
  Form.ticks:=0
  ProbeDate:=!2026-09-24!
  ProbeTime:=?09:00:00?
  ProbeProgressTime:=?09:00:00?
  ProbeLong:=4
  ProbeRulerDate:=!2026-09-24!
  Form.progressDate:=!2026-09-24!
  Form.readOnlyDate:=!2026-09-24!
  ProbeReadOnlyTime:=?09:00:00?
  For each ($name; New collection("DateRuler"; "DateProgress"; "ReadOnlyDateProgress"))
   OBJECT SET MINIMUM VALUE(*; $name; !2026-09-01!)
   OBJECT SET MAXIMUM VALUE(*; $name; !2026-09-30!)
  End for each
  OBJECT SET ENABLED(*; "Disabled"; False)
  OBJECT SET ENABLED(*; "DisabledProgress"; False)
  $controls:=New object("Stepper"; New object("description"; Formula(String(Form.amount)+" items")))
  For each ($name; New collection("Progress"; "Vertical"; "TimeProgress"; "FractionalProgress"; "DenseProgress"; "DisabledProgress"; "RejectedProgress"; "DateProgress"))
   $controls[$name]:=New object("adjust"; Formula(ProbeAdjust($1)))
  End for each
  Form.invalidAdjustment:=AXB_Form("start"; New object("label"; "Invalid callback"; "controls"; New object("Progress"; New object("adjust"; "not a formula"))))
  Form.start:=AXB_Form("start"; New object("label"; "Adjustable controls"; "controls"; $controls))
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  If (File("/RESOURCES/command.json").exists)
   $command:=JSON Parse(File("/RESOURCES/command.json").getText())
   File("/RESOURCES/command.json").delete()
   Case of
    : ($command.action="focus")
     GOTO OBJECT(*; $command.object)
    : ($command.action="key")
     POST KEY($command.key; 0; Current process)
    : ($command.action="click")
     OBJECT GET COORDINATES(*; $command.object; $left; $top; $right; $bottom)
     $x:=$left+($right-$left)*$command.x
     $y:=$top+($bottom-$top)*$command.y
     CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
     POST CLICK($x; $y; Current process)
    : ($command.action="close")
     CANCEL
    : ($command.action="value")
     OBJECT SET VALUE($command.object; $command.value)
    : ($command.action="dateValue")
     OBJECT SET VALUE($command.object; !2026-09-01!+$command.value)
    : ($command.action="rejectTyped")
     Form.rejectTyped:=$command.value
    : ($command.action="shiftDateRange")
     Form.shiftDateRange:=$command.value
     If (Not(Form.shiftDateRange))
      OBJECT SET MINIMUM VALUE(*; "DateProgress"; !2026-09-01!)
      OBJECT SET MAXIMUM VALUE(*; "DateProgress"; !2026-09-30!)
      Form.progressDate:=!2026-09-24!
     End if
   End case
   Form.sequence:=$command.sequence
  End if
  FORM GET ENTRY ORDER($order; *)
  $state:=New object("ready"; True; "start"; Form.start; "sequence"; Form.sequence; "events"; Form.events; "focus"; OBJECT Get name(Object with focus); "objects"; New object; "order"; New collection)
  $state.invalidAdjustment:=Form.invalidAdjustment
  $state.dateText:=String(ProbeDate)
  $state.timeText:=String(ProbeTime)
  $state.rulerDateText:=String(ProbeRulerDate)
  $state.progressDateText:=String(Form.progressDate)
  $state.ticks:=Form.ticks
  $state.bridgeError:=Form.axbError
  $state.bridgeFailure:=Form.axbFailure
  $state.discovery:=Form.axbView.discovery
  $state.diagnostics:=AXB_Form("diagnostics"; New object)
  ARRAY TO COLLECTION($state.order; $order)
  For each ($name; New collection("UnconfiguredProgress"; "Stepper"; "DateStepper"; "TimeStepper"; "LongStepper"; "Ruler"; "DateRuler"; "DateProgress"; "ReadOnlyDateProgress"; "ReadOnlyTimeProgress"; "Progress"; "Vertical"; "TimeProgress"; "FractionalProgress"; "DenseProgress"; "DisabledProgress"; "ReadOnlyProgress"; "RejectedProgress"; "Disabled"; "ReadOnly"; "Rejected"))
   $state.objects[$name]:=New object("type"; OBJECT Get type(*; $name); "format"; OBJECT Get format(*; $name); "value"; OBJECT Get value($name); "enterable"; OBJECT Get enterable(*; $name); "enabled"; OBJECT Get enabled(*; $name))
  End for each
  File("/RESOURCES/status.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
""")
objects = {
    "Text": {
        "type": "input",
        "dataSource": "Form.text",
        "left": 20,
        "top": 15,
        "width": 240,
        "height": 24,
    }
}
for i, (name, binding, hint) in enumerate(
    [
        ("Stepper", "Form.amount", "integer"),
        ("DateStepper", "ProbeDate", "date"),
        ("TimeStepper", "ProbeTime", "time"),
        ("Disabled", "Form.disabled", "integer"),
        ("ReadOnly", "Form.readonly", "integer"),
    ]
):
    objects[name] = {
        "type": "stepper",
        "dataSource": binding,
        "dataSourceTypeHint": hint,
        "left": 30 + i * 70,
        "top": 70,
        "width": 20,
        "height": 30,
        "min": 0,
        "max": 10,
        "step": 2,
        "enterable": True,
        "method": "ProbeEvent",
        "events": ["onClick", "onDataChange"],
        "continuousExecution": False,
    }
objects["TimeStepper"].update(min=28800, max=64800, step=600)
objects["Stepper"].update(width=14, height=22)
objects["Rejected"] = {
    **objects["Stepper"],
    "left": 380,
    "dataSource": "Form.rejected",
    "step": 1,
}
objects["ReadOnly"]["enterable"] = False
objects["Separator"] = {
    "type": "text",
    "text": "/",
    "left": 285,
    "top": 70,
    "width": 15,
    "height": 30,
}
objects["Ruler"] = {
    "type": "ruler",
    "dataSource": "Form.scale",
    "dataSourceTypeHint": "integer",
    "left": 20,
    "top": 145,
    "width": 350,
    "height": 40,
    "min": 0,
    "max": 100,
    "step": 5,
    "enterable": True,
    "method": "ProbeEvent",
    "events": ["onClick", "onDataChange"],
    "continuousExecution": False,
}
objects["Progress"] = {
    "type": "progress",
    "dataSource": "Form.temperature",
    "dataSourceTypeHint": "integer",
    "left": 20,
    "top": 205,
    "width": 350,
    "height": 24,
    "min": 0,
    "max": 10,
    "step": 1,
    "enterable": True,
    "method": "ProbeEvent",
    "events": ["onClick", "onDataChange"],
    "continuousExecution": False,
}
objects["LongStepper"] = {
    **objects["Stepper"], "left": 440, "dataSource": "ProbeLong",
}
objects["Vertical"] = {
    **objects["Progress"], "dataSource": "Form.vertical", "left": 410,
    "top": 145, "width": 24, "height": 210,
}
for i, (name, binding, extra) in enumerate([
    ("TimeProgress", "ProbeProgressTime", {"dataSourceTypeHint": "time", "min": 28800, "max": 64800, "step": 3600}),
    ("FractionalProgress", "Form.fractional", {"dataSourceTypeHint": "real", "max": 1, "step": 0.1}),
    ("DenseProgress", "Form.dense", {"max": 10000}),
    ("DisabledProgress", "Form.disabled", {}),
    ("ReadOnlyProgress", "Form.readonly", {"enterable": False}),
    ("RejectedProgress", "Form.rejectedProgress", {}),
]):
    objects[name] = {**objects["Progress"], "dataSource": binding, "top": 250 + i * 45, **extra}
objects["UnconfiguredProgress"] = {**objects["Progress"], "dataSource": "Form.unconfigured", "left": 285, "top": 15, "width": 100}
objects["DateRuler"] = {**objects["Ruler"], "dataSource": "ProbeRulerDate", "dataSourceTypeHint": "date", "top": 520, "step": 1}
objects["DateProgress"] = {**objects["Progress"], "dataSource": "Form.progressDate", "dataSourceTypeHint": "date", "top": 570}
objects["ReadOnlyDateProgress"] = {**objects["DateProgress"], "dataSource": "Form.readOnlyDate", "top": 605, "enterable": False}
objects["ReadOnlyTimeProgress"] = {**objects["TimeProgress"], "dataSource": "ProbeReadOnlyTime", "left": 410, "top": 405, "width": 24, "height": 140, "enterable": False}
objects["Close"] = {
    "type": "button",
    "text": "Close",
    "left": 300,
    "top": 650,
    "width": 120,
    "height": 28,
    "action": "cancel",
    "events": ["onClick"],
}
folder = sources / "Forms/Root"
folder.mkdir(parents=True)
(folder / "form.4DForm").write_text(
    json.dumps(
        {
            "windowTitle": "AXB adjustable controls",
            "width": 480,
            "height": 700,
            "method": "ProbeForm",
            "events": ["onLoad", "onTimer", "onUnload"],
            "pages": [None, {"objects": objects}],
        },
        indent=2,
    )
    + "\n"
)
server = server_app / "Contents/MacOS" / info["CFBundleExecutable"]
driver = root / ("build/adjustable-controls-compile-" + uuid.uuid4().hex)
project_at(driver, "Driver")
hashes = {
    str(p.relative_to(fixture)): sha(p) for p in sources.rglob("*") if p.is_file()
}
compiled = run_utility(
    server,
    driver,
    '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
    + f"$options.plugins:=Folder({literal(fixture / 'Plugins')})\n"
    + f"$options.components:=New collection(File({literal(fixture / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')}))\n"
    + f"$result:=Compile project(File({literal(project)}); $options)",
    90,
)
report = {
    "passed": compiled.get("success") is True and not compiled.get("errors"),
    "compiler": compiled,
    "sources_sha256": hashes,
    "native_sha256": sha(
        fixture
        / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
    ),
    "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
}
(root / "build/adjustable-controls-compile-report.json").write_text(
    json.dumps(report, indent=2) + "\n"
)
print(("PASS" if report["passed"] else "FAIL") + ": adjustable controls compilation")
if not report["passed"]:
    print(compiled)
    raise SystemExit(1)
