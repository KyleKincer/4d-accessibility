#!/usr/bin/env python3
"""Exercise portable form helpers in a real 4D Server utility host."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import tempfile

from build_component import BUILD, ROOT, project_at, run_utility


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    args = parser.parse_args()
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    with tempfile.TemporaryDirectory(prefix="form-state-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        for source in (ROOT / "host/OptionalMethods").glob("*.4dm"):
            shutil.copy2(source, driver / "Project/Sources/Methods" / source.name)
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver, '''var $checks : Collection
var $reply; $source; $data; $options; $prepared; $bad : Object
var $long : Text
var $i : Integer
$checks:=New collection
$checks.push(AXB_ControlValue(1234.5; "###,##0.00")="1,234.50")
$checks.push(AXB_ControlValue(!2026-09-23!; Char(Internal date long))="September 23, 2026")
$checks.push(AXB_ControlValue(?13:05:09?; Char(HH MM SS))="13:05:09")
$checks.push(AXB_ControlValue(True; "Allowed;Blocked")="Allowed")
$checks.push(AXB_ControlValue(False; "Allowed;Blocked")="Blocked")
$checks.push((AXB_ControlValue(Null; "")="") & (AXB_ControlValue(New object("private"; "do not stringify"); "")=""))
$checks.push(AXB_GridOptions(New object("Items"; New object("kind"; "array"; "keyColumn"; "Key"; "ready"; Formula(True)))))
$checks.push(Not(AXB_GridOptions(New object("Items"; 42))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "array"; "keyColumn"; 1)))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "array"; "keyColumn"; "Key"; "onSelection"; "Arbitrary method")))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "areaList"; "keyColumn"; 1; "keys"; "array name")))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "array"; "keyColumn"; "Key"; "ready"; New object)))))
$checks.push(AXB_GridOptions(New object("Items"; New object("kind"; "collection"; "keyProperty"; "id"; "selection"; Formula(Form.selected)))))
$checks.push(AXB_GridOptions(New object("Items"; New object("kind"; "entity"; "selection"; Formula(Form.selected)))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "collection"; "selection"; Formula(Form.selected))))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "entity"; "keyProperty"; 42)))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "entity"; "selection"; "Form.selected")))))
$checks.push(AXB_GridOptions(New object("Items"; New object("kind"; "collection"; "keyProperty"; "id"; "meta"; Formula(This.meta)))))
$checks.push(AXB_GridOptions(New object("Items"; New object("kind"; "entity"; "meta"; Formula(This.meta)))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "array"; "keyColumn"; "Key"; "meta"; Formula(This.meta))))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "collection"; "keyProperty"; "id"; "meta"; "MetaMethod")))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "areaList"; "keys"; ->$long; "meta"; Formula(This.meta))))))
var $gridState; $gridColumn; $gridCell : Object
$gridState:=New object("binding"; New object("source"; New collection(New object("amount"; 600.25))))
$gridColumn:=New object("name"; "Amount"; "property"; "amount"; "format"; "###,##0.00")
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="600.25") & $gridCell.editable)
$gridState.binding.source[0].amount:=New object("secret"; "never serialize")
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push(Not($gridCell.ok) & ($gridCell.value="Cell description required") & Not($gridCell.editable) & (OB Keys($gridState.valueIssues).length=1))
$gridState.binding.source[0].amount:=Null
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="") & Not($gridCell.editable) & (OB Keys($gridState.valueIssues).length=0))
$gridColumn.protected:=True
$gridState.binding:=Null
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="") & Not($gridCell.editable))
var $gridOptions : Object
$gridOptions:=New object("kind"; "areaList"; "keyColumn"; 7; "keys"; ->$long; "columns"; New object("5"; New object("label"; "Visibility"; "value"; Formula("Visible")); "6"; New object("decorative"; True)))
$checks.push(AXB_GridOptions(New object("Items"; $gridOptions)))
$checks.push(AXB_GridOptions(New object("Items"; New object("kind"; "areaList"; "keys"; ->$long))))
$checks.push(Not(AXB_GridOptions(New object("Items"; New object("kind"; "areaList"; "keys"; ->$long; "keyColumn"; 0)))))
$gridOptions.columns["5"].value:="not a formula"
$checks.push(Not(AXB_GridOptions(New object("Items"; $gridOptions))))
$gridOptions.columns["5"].value:=Formula("Visible")
$gridOptions.columns["5"].decorative:=True
$checks.push(Not(AXB_GridOptions(New object("Items"; $gridOptions))))
$gridOptions.columns:=New object("05"; New object("label"; "Ambiguous column"))
$checks.push(Not(AXB_GridOptions(New object("Items"; $gridOptions))))
$gridOptions.columns:=New object("5"; New object("decorative"; "yes"))
$checks.push(Not(AXB_GridOptions(New object("Items"; $gridOptions))))
// Custom column descriptions reuse application renderers without evaluating
// column strings or serializing an object/record graph.
$gridOptions:=New object("kind"; "array"; "keyColumn"; "Key"; "columns"; New object("StatusIcon"; New object("label"; "Status"; "value"; Formula("Ready")); "Spacer"; New object("decorative"; True)))
$checks.push(AXB_GridOptions(New object("Items"; $gridOptions)))
$gridOptions.columns.StatusIcon.value:=42
$checks.push(Not(AXB_GridOptions(New object("Items"; $gridOptions))))
$gridOptions.columns:=New object(""; New object("decorative"; True))
$checks.push(Not(AXB_GridOptions(New object("Items"; $gridOptions))))
$gridState:=New object("binding"; New object("source"; New collection(New object("id"; 42; "name"; "Visible"; "private"; "NEVER-EXPOSE")); "keyProperty"; "id"))
$gridColumn:=New object("name"; "Summary"; "value"; Formula(String($1.key)+":"+String($1.row)+":"+$1.column+":"+This.name))
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="42:1:Summary:Visible") & Not($gridCell.editable))
$gridColumn.value:=Formula(New object("private"; "NEVER-EXPOSE"))
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push(Not($gridCell.ok) & ($gridCell.value="Cell description required") & (OB Keys($gridState.valueIssues).length=1))
$gridColumn.value:=Formula("Corrected description")
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="Corrected description") & (OB Keys($gridState.valueIssues).length=0))
ARRAY PICTURE($pictures; 1)
$gridColumn.pointer:=->$pictures
$gridState.binding:=New object("keys"; New collection("exact-Key"))
$gridColumn.value:=Formula($1.key+":"+$1.column)
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="exact-Key:Summary") & Not($gridCell.editable))
// Null the binding: even preparing callback arguments would now fail.
$gridColumn.protected:=True
$gridState.binding:=Null
$gridCell:=AXB_GridValue($gridState; $gridColumn; 1)
$checks.push($gridCell.ok & ($gridCell.value="") & Not($gridCell.editable))
$checks.push(AXB_KeyIndex(New collection("café"; "CAFE"; "cafe"; "A@"); "cafe")=2)
$checks.push(AXB_KeyIndex(New collection("café"; "CAFE"; "cafe"; "A@"); "A@")=3)
$checks.push(AXB_KeyIndex(New collection("café"; "CAFE"; "cafe"; "A@"); "a@")=-1)
$checks.push(AXB_TextIndex("aé中😀z"; 0; True)=0)
$checks.push(AXB_TextIndex("aé中😀z"; 3; True)=2)
$checks.push(AXB_TextIndex("aé中😀z"; 6; True)=3)
$checks.push(AXB_TextIndex("aé中😀z"; 10; True)=5)
$checks.push(AXB_TextIndex("aé中😀z"; 5; False)=10)
$checks.push(AXB_TextIndex("aé中😀z"; 6; False)=11)
$checks.push(AXB_TextIndex("aé中😀z"; 2; True)=-1)
$checks.push(AXB_TextIndex("aé中😀z"; 4; False)=-1)
$checks.push(AXB_TextIndex("aé中😀z"; 12; True)=-1)
$checks.push(AXB_TextIndex("aé中😀z"; -1; False)=-1)
$checks.push(AXB_Intersects(New collection(10; 10; 340; 24); New collection(20; 20; 240; 125)))
$checks.push(Not(AXB_Intersects(New collection(10; 10; 10; 10); New collection(20; 20; 240; 125))))
$checks.push(Not(AXB_Intersects(New collection(10; 10; 340; 24); New collection(20; 20; 0; 125))))
$checks.push(Not(AXB_Intersects(New collection(10; 10; 340; 24); New collection(20; 200; 240; 125))))
$checks.push(AXB_Intersects(New collection(-10; -10; 50; 50); New collection(0; 0; 100; 100)))
$checks.push(Not(AXB_Intersects(New collection; Null)))
$reply:=AXB_Result(New object("status"; "completed"))
$checks.push(($reply.status="completed") & ($reply.message="Action completed"))
$reply:=AXB_Result(New object("status"; "pending"; "message"; "wrong"))
$checks.push($reply.status="rejected")
$reply:=AXB_Result(Null)
$checks.push($reply.status="rejected")
$long:=""
For ($i; 1; 700)
 $long:=$long+"x"
End for
$reply:=AXB_Result(New object("status"; "completed"; "message"; $long))
$checks.push(Length($reply.message)=512)
$reply:=AXB_Form("start"; New object)
$checks.push($reply.error="noFormContext")
$reply:=AXB_Form("arbitrary method"; New object)
$checks.push($reply.error="unsupportedOperation")
$source:=New object("method"; "App_Form"; "pages"; New collection(Null; New object("objects"; New object)); "events"; New collection("onTimer"))
$data:=New object
$options:=New object("label"; "Generated"; "describe"; Formula(Null))
$reply:=AXB_Dynamic($source; $data; $options; "start")
$checks.push($reply.ok=True)
$prepared:=$reply.form
$checks.push(($source.method="App_Form") & ($source.pages[0]=Null) & ($source.events.length=1))
$checks.push(($prepared.events.indexOf("onLoad")>=0) & ($prepared.events.indexOf("onUnload")>=0) & ($prepared.events.indexOf("onTimer")>=0))
$checks.push(($data.axbDynamic.method="App_Form") & Not($data.axbDynamic.onLoad) & Not($data.axbDynamic.onUnload))
$checks.push(($prepared.pages[0].objects.__AXB_DynamicContext.dataSource="") & ($prepared.pages[0].objects.__AXB_DynamicContext.visibility="hidden"))
$reply:=AXB_Dynamic($source; $data; $options; "start")
$checks.push($reply.error="dynamicDataInUse")
$reply:=AXB_Dynamic($prepared; New object; $options; "start")
$checks.push($reply.error="alreadyPreparedDynamicForm")
$reply:=AXB_Dynamic($source; Null; $options; "register")
$checks.push($reply.error="invalidDynamicForm")
$reply:=AXB_Dynamic($source; New object; $options; "other")
$checks.push($reply.error="invalidDynamicOperation")
$bad:=OB Copy($source)
$bad.method:=42
$reply:=AXB_Dynamic($bad; New object; $options; "start")
$checks.push($reply.error="invalidDynamicMethod")
$bad:=OB Copy($source)
$bad.events:="onLoad"
$reply:=AXB_Dynamic($bad; New object; $options; "start")
$checks.push($reply.error="invalidDynamicEvents")
$bad:=OB Copy($source)
OB REMOVE($bad; "events")
$reply:=AXB_Dynamic($bad; New object; $options; "start")
$checks.push($reply.error="missingDynamicEvents")
OB REMOVE($bad; "method")
$reply:=AXB_Dynamic($bad; New object; $options; "start")
$checks.push($reply.ok=True)
$bad:=OB Copy($source)
$bad.events:=New collection(On Load; On Unload; On Timer)
$data:=New object
$reply:=AXB_Dynamic($bad; $data; $options; "start")
$checks.push(($reply.ok=True) & $data.axbDynamic.onLoad & $data.axbDynamic.onUnload & ($reply.form.events.length=3))
$bad.events:=New collection(New object)
$reply:=AXB_Dynamic($bad; New object; $options; "start")
$checks.push($reply.error="invalidDynamicEvents")
$data.axbDynamic.closed:=True
$reply:=AXB_Dynamic($source; $data; $options; "start")
$checks.push($reply.ok=True)
// The result always carries a form to open; a failure is reported exactly once.
var axbFormStateFailures : Collection
axbFormStateFailures:=New collection
$options.onError:=Formula(axbFormStateFailures.push($1))
$reply:=AXB_Dynamic($source; $data; $options; "start")
$checks.push(($reply.error="dynamicDataInUse") & (New collection($reply.form).indexOf($source)=0))
$checks.push((axbFormStateFailures.length=1) & (axbFormStateFailures[0].phase="prepare") & (axbFormStateFailures[0].error="dynamicDataInUse"))
$reply:=AXB_Dynamic($source; Null; Null; "start")
$checks.push(($reply.error="invalidDynamicForm") & (New collection($reply.form).indexOf($source)=0) & (axbFormStateFailures.length=1))
$reply:=AXB_Dynamic($source; New object; $options; "start")
$checks.push(($reply.ok=True) & (New collection($reply.form).indexOf($source)<0) & (axbFormStateFailures.length=1))
// Grouping uses the live geometry and never guesses between overlapping boxes.
var $nodes; $diagnostics : Collection
var $outer; $inner; $button; $overlap : Object
$outer:=New object("id"; "outer"; "objectName"; "Outer"; "role"; "group"; "frame"; New collection(0; 0; 400; 400))
$inner:=New object("id"; "inner"; "objectName"; "Inner"; "role"; "group"; "frame"; New collection(10; 10; 200; 200))
$button:=New object("id"; "button"; "objectName"; "Button"; "role"; "button"; "frame"; New collection(20; 20; 100; 25))
$nodes:=New collection($outer; $inner; $button)
$diagnostics:=AXB_ControlGroups($nodes; New object)
$checks.push(($diagnostics.length=0) & ($inner.parent="outer") & ($button.parent="inner") & Not(OB Is defined($outer; "parent")))
OB REMOVE($button; "parent")
$overlap:=New object("id"; "overlap"; "objectName"; "Overlap"; "role"; "group"; "frame"; New collection(0; 0; 180; 300))
$nodes.push($overlap)
$diagnostics:=AXB_ControlGroups($nodes; New object)
$checks.push(Not(OB Is defined($button; "parent")) & ($diagnostics.length=1))
$diagnostics:=AXB_ControlGroups($nodes; New object("controls"; New object("Button"; New object("group"; "Inner"))))
$checks.push(($button.parent="inner") & ($diagnostics.length=0))
OB REMOVE($button; "parent")
$diagnostics:=AXB_ControlGroups($nodes; New object("controls"; New object("Button"; New object("group"; ""))))
$checks.push(Not(OB Is defined($button; "parent")) & ($diagnostics.length=0))
$diagnostics:=AXB_ControlGroups($nodes; New object("controls"; New object("Button"; New object("group"; "Missing"))))
$checks.push(Not(OB Is defined($button; "parent")) & ($diagnostics.length=1))
$nodes:=New collection
For ($i; 1; 600)
 $nodes.push(New object("id"; String($i); "objectName"; "Button"+String($i); "role"; "button"; "frame"; New collection(0; 0; 10; 10)))
End for
var $groupStart; $groupElapsed : Integer
$groupStart:=Milliseconds
$diagnostics:=AXB_ControlGroups($nodes; New object)
$groupElapsed:=Milliseconds-$groupStart
$checks.push($diagnostics.length=0)
$result:=New object("success"; $checks.indexOf(False)<0; "checks"; $checks; "ungrouped600Milliseconds"; $groupElapsed)
''', 45)
    (BUILD / "form-state-report.json").write_text(json.dumps(result, indent=2) + "\n")
    print(result)
    raise SystemExit(0 if result.get("success") is True else 1)


if __name__ == "__main__":
    main()
