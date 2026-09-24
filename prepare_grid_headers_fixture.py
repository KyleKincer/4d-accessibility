#!/usr/bin/env python3
"""Prepare native header cases on the existing synthetic array/collection/entity data."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from build_component import BUILD, literal, project_at, run_utility, sha

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--server', type=Path, required=True)
parser.add_argument('--kind', choices=['array', 'collection', 'entity'], default='array')
args = parser.parse_args()
subprocess.run([sys.executable, str(ROOT/'prepare_grid_fixture.py'), '--server', str(args.server), *([] if args.kind=='array' else ['--'+args.kind])], check=True)
fixture=BUILD/'logical-grid-fixture';methods=fixture/'Project/Sources/Methods'
form_path=fixture/'Project/Sources/Forms/Grid/form.4DForm';form=json.loads(form_path.read_text());grid=form['pages'][1]['objects']['Items']
grid.update(method='AXBH_Event', events=['onHeaderClick', 'onAfterSort'])
grid['columns'][1]['width']=780
grid['columns'][2]['width']=200
form_path.write_text(json.dumps(form,indent=2)+'\n')
startup=fixture/'Project/Sources/DatabaseMethods/onStartup.4dm'
startup.write_text(startup.read_text().replace('$data.finalFar:=aGridName{Find in array(aGridKey; "line-0600")}', '$data.finalFar:=""\nIf (Find in array(aGridKey; "line-0600")>0)\n $data.finalFar:=aGridName{Find in array(aGridKey; "line-0600")}\nEnd if'))
p=methods/'AXBG_Form.4dm';s=p.read_text().replace('  Form.scope:=', '  Form.headerEvents:=New collection\n  Form.headerBehavior:="native"\n  Form.headerSequence:=0\n  Form.scope:=');p.write_text(s)
(methods/'AXBH_Event.4dm').write_text('''var $0; $column; $row : Integer
var $event : Object
$0:=0
LISTBOX GET CELL POSITION(*; "Items"; $column; $row)
$event:=New object("event"; Form event code; "object"; OBJECT Get name(Object current); "column"; $column; "row"; $row; "behavior"; Form.headerBehavior)
Form.headerEvents.push($event)
If (Form event code=On Header Click)
 If (Form.headerBehavior="reject")
  $0:=-1
 End if
 If (Form.headerBehavior="custom")
  $0:=-1
  LISTBOX SORT COLUMNS(*; "Items"; 1; <)
 End if
End if
''')
(methods/'AXBG_State.4dm').write_text('''var $state : Object
$state:=AXBH_State
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
''')
(methods/'AXBH_State.4dm').write_text('''#DECLARE() -> $state : Object
var $command; $item; $definition; $context : Object
var $key; $name : Text
var $row; $topRow; $leftColumn; $left; $top; $right; $bottom : Integer
var $pointer : Pointer
If (File("/RESOURCES/header-command.json").exists)
 $command:=JSON Parse(File("/RESOURCES/header-command.json").getText())
 File("/RESOURCES/header-command.json").delete()
 If ($command.behavior#Null)
  Form.headerBehavior:=$command.behavior
 End if
 If ($command.sortable#Null)
  LISTBOX SET PROPERTY(*; "Items"; lk sortable; Num($command.sortable))
 End if
 If ($command.headers#Null)
  LISTBOX SET PROPERTY(*; "Items"; lk display header; Num($command.headers))
 End if
 If ($command.enabled#Null)
  OBJECT SET ENABLED(*; "Items"; $command.enabled)
 End if
 If ($command.columnEnabled#Null)
  OBJECT SET ENABLED(*; "ItemAmount"; $command.columnEnabled)
 End if
 If ($command.empty=True)
  If (Form.rows=Null)
   LISTBOX DELETE ROWS(*; "Items"; 1; Size of array(aGridKey))
  Else
   If (OB Instance of(Form.rows; 4D.EntitySelection))
    Form.rows:=Form.rows.slice(0; 0)
   Else
    Form.rows:=New collection
   End if
  End if
 End if
 If ($command.locked#Null)
  LISTBOX SET LOCKED COLUMNS(*; "Items"; $command.locked)
 End if
 If ($command.scope=True)
  Form.scope:=Generate UUID
 End if
 Form.headerSequence:=$command.sequence
End if
$state:=New object("phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "start"; Form.startResult; "bridgeError"; Form.axbError; "failure"; Form.failure; "sequence"; Form.headerSequence; "events"; Form.headerEvents; "rows"; New collection; "headers"; New object)
If (Form.rows=Null)
 For ($row; 1; Size of array(aGridKey))
  If (New collection(1; 3; 5; 7).indexOf(aGridControl{$row})<0)
   $state.rows.push(aGridKey{$row})
  End if
 End for
Else
 For each ($item; Form.rows)
  $state.rows.push(String($item.id))
 End for each
End if
For each ($name; New collection("ItemNameHeader"; "ItemAmountHeader"))
 $pointer:=OBJECT Get pointer(Object named; $name)
 $definition:=New object("enabled"; OBJECT Get enabled(*; $name); "visible"; OBJECT Get visible(*; $name))
 If (Not(Is nil pointer($pointer)))
  $definition.sort:=$pointer->
 End if
 OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
 $definition.frame:=New collection($left; $top; $right-$left; $bottom-$top)
 $state.headers[$name]:=$definition
End for each
OBJECT GET SCROLL POSITION(*; "Items"; $topRow; $leftColumn)
$state.scroll:=New collection($topRow; $leftColumn)
$state.diagnostics:=AXB_Form("diagnostics"; New object)
$state.gridEnabled:=OBJECT Get enabled(*; "Items")
$state.timerTicks:=Form.timerTicks
$state.time:=Milliseconds
$context:=AXB_FormContext
If ($context#Null)
 $state.bridgeActive:=$context.active
 $state.token:=New object("active"; $context.token.active; "pending"; $context.token.pending; "fast"; $context.token.fast)
 If (($context.state#Null) && (Length($context.state)>0))
  $state.snapshot:=JSON Parse($context.state)
 End if
End if
''')
with (methods/'Compiler_AXBG.4dm').open('a') as f:f.write('C_OBJECT(AXBH_State; $0)\nC_LONGINT(AXBH_Event; $0)\n')
config=json.loads((fixture/'Resources/launch.json').read_text());config['headers']=True;(fixture/'Resources/launch.json').write_text(json.dumps(config)+'\n')
server=args.server.expanduser().resolve();info=plistlib.loads((server/'Contents/Info.plist').read_bytes())
with tempfile.TemporaryDirectory(prefix='header-compile-',dir=BUILD) as temporary:
 driver=Path(temporary);project_at(driver,'Driver')
 compiled=run_utility(server/'Contents/MacOS'/info['CFBundleExecutable'],driver,
 '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
 f'$options.plugins:=Folder({literal(fixture/"Plugins")})\n'
 f'$options.components:=New collection(File({literal(fixture/"Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
 f'$result:=Compile project(File({literal(fixture/"Project/LogicalGridFixture.4DProject")}); $options)',90)
report=json.loads((BUILD/'logical-grid-compile-report.json').read_text());report.update(compiler=compiled,passed=compiled.get('success') is True and not compiled.get('errors'))
report['sources_sha256']={str(p.relative_to(fixture)):sha(p) for p in (fixture/'Project/Sources').rglob('*') if p.is_file()}
(BUILD/'logical-grid-compile-report.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['passed'],compiled
print('PASS: native header fixture compile')
