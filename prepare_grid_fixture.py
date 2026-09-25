#!/usr/bin/env python3
"""Prepare isolated full logical listbox tests; only synthetic data is used."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import struct
import tempfile
import uuid
import zlib

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "logical-grid-fixture"
TITLE = "AXB complete 4D grid fixture"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    family = parser.add_mutually_exclusive_group()
    family.add_argument("--entity", action="store_true", help="Use a local synthetic entity selection and automatic primary-key identity")
    family.add_argument("--collection", action="store_true", help="Use the complete collection-backed provider with the same editor/action suite")
    parser.add_argument("--key-type", choices=("text", "integer", "longint"), default="text", help="Use existing Text, Integer or LongInt array identities")
    parser.add_argument("--described", action="store_true", help="Add picture/computed, decorative and protected columns with application descriptions")
    parser.add_argument("--object-description", action="store_true", help="Use a native Object array for the described array column")
    parser.add_argument("--styled-description", action="store_true", help="Use a styled computed description column in a collection/entity grid")
    parser.add_argument("--subform", action="store_true", help="Open the unchanged grid in an automatic page subform, with only root bridge hooks")
    parser.add_argument("--repeated", action="store_true", help="Add an independent sibling instance to the collection widget subform fixture")
    parser.add_argument("--row-states", action="store_true", help="Exercise disabled/nonselectable rows and native editing exceptions")
    parser.add_argument("--cell-controls", action="store_true", help="Add native Boolean/popup/mixed cells and application validation")
    parser.add_argument("--stored-meta", action="store_true", help="Read the collection's existing This.meta objects automatically")
    parser.add_argument("--slow-visible-selection", action="store_true", help="Reproduce visible-row confirmation under expensive application callbacks")
    parser.add_argument("--slow-distant-selection", action="store_true", help="Reproduce a distant row reveal with an expensive selection controller")
    parser.add_argument("--boolean-hidden", action="store_true", help="Use the legacy Boolean hidden-row array without changing the host binding")
    args = parser.parse_args()
    if args.boolean_hidden and (args.collection or args.entity or args.subform or args.described or args.row_states or args.cell_controls or args.slow_visible_selection or args.slow_distant_selection or args.key_type != "text"):
        parser.error("--boolean-hidden uses the default root array fixture")
    if (args.slow_visible_selection or args.slow_distant_selection) and (args.collection or args.entity or args.subform or args.described or args.row_states or args.cell_controls or args.key_type != "text"):
        parser.error("Slow selection probes use the default root array fixture")
    if args.slow_visible_selection and args.slow_distant_selection:
        parser.error("Choose one slow selection probe")
    if args.key_type != "text" and (args.collection or args.entity):
        parser.error("--key-type applies to array grids only")
    if args.repeated and not (args.subform and args.collection and args.cell_controls):
        parser.error("--repeated requires --subform --collection --cell-controls")
    if args.object_description and (not args.described or args.collection or args.entity):
        parser.error("--object-description requires --described with an array grid")
    if args.styled_description and (not args.described or not (args.collection or args.entity)):
        parser.error("--styled-description requires --described with a collection or entity grid")
    if args.stored_meta and (not args.row_states or not args.collection):
        parser.error("--stored-meta requires --row-states --collection")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("logical-grid-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "LogicalGridFixture")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for folder, pattern in [(ROOT / "host/OptionalMethods", "*.4dm"), (ROOT / "tests/4d", "AXBG_*.4dm")]:
        for method in folder.glob(pattern):
            if method.name in ("AXBG_WidgetState.4dm", "AXBG_WidgetEvent.4dm") and not args.cell_controls:
                continue
            shutil.copy2(method, methods / method.name)
    (methods / "Compiler_AXBG.4dm").write_text("C_OBJECT(AXBG_Failed; $1)\nC_OBJECT(AXBG_Describe; $1)\nC_TEXT(AXBG_Describe; $0)\nARRAY TEXT(aGridKey; 0)\nARRAY TEXT(aGridName; 0)\nARRAY REAL(aGridAmount; 0)\nARRAY BOOLEAN(aGridSelected; 0)\nARRAY LONGINT(aGridControl; 0)\n")
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text('''var $window; $row : Integer
var $data : Object
ARRAY TEXT(aGridKey; 600)
ARRAY TEXT(aGridName; 600)
ARRAY REAL(aGridAmount; 600)
ARRAY BOOLEAN(aGridSelected; 600)
ARRAY LONGINT(aGridControl; 600)
For ($row; 1; 600)
 aGridKey{$row}:="line-"+String($row; "0000")
 aGridName{$row}:="Line item "+String($row; "0000")
 aGridAmount{$row}:=$row+0.25
End for
aGridControl{2}:=lk row is hidden
aGridControl{3}:=lk row is disabled
aGridControl{4}:=lk row is not selectable
aGridKey{3}:="café"
aGridKey{4}:="CAFÉ"
aGridKey{5}:="CAFE"
aGridKey{6}:="cafe"
$data:=New object("runId"; JSON Parse(File("/RESOURCES/launch.json").getText()).runId)
$window:=Open form window("Grid"; Plain form window)
DIALOG("Grid"; $data)
$data.accepted:=(OK=1)
$data.finalFar:=aGridName{Find in array(aGridKey; "line-0600")}
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.runId; "accepted"; $data.accepted; "farValue"; $data.finalFar)))
CLOSE WINDOW($window)
QUIT 4D
''')
    if args.collection or args.entity:
        startup = (database / "onStartup.4dm").read_text().replace("var $data : Object", "var $data; $item : Object")
        startup = startup.replace('$window:=Open form window', '\n'.join([
            '$data.rows:=New collection',
            'For ($row; 1; 600)',
            ' If ($row#2)',
            '  $data.rows.push(New object("id"; aGridKey{$row}; "name"; aGridName{$row}; "amount"; aGridAmount{$row}))',
            ' End if', 'End for', '$window:=Open form window']))
        startup = startup.replace('$data.finalFar:=aGridName{Find in array(aGridKey; "line-0600")}', '$data.finalFar:=""\nFor each ($item; $data.rows)\n If ($item.id="line-0600")\n  $data.finalFar:=$item.name\n End if\nEnd for each')
        (database / "onStartup.4dm").write_text(startup)
        form_method = (methods / "AXBG_Form.4dm").read_text().replace('  Form.scope:=', '  Form.selected:=New collection\n  Form.scope:=', 1)
        form_method = form_method.replace('"kind"; "array"; "keyColumn"; "RowID";', '"kind"; "collection"; "keyProperty"; "id"; "selection"; Formula(Form.selected);')
        (methods / "AXBG_Form.4dm").write_text(form_method)
        (methods / "AXBG_Selected.4dm").write_text('Form.hooks:=Form.hooks+1\nForm.hookSelection:=Form.selected.extract("id")\nIf (Form.rejectSelection=True)\n LISTBOX SELECT ROW(*; "Items"; 0; lk remove from selection)\nEnd if\nAXBG_State\n')
        (methods / "AXBG_State.4dm").write_text("""var $state; $item : Object
var $edited; $far : Text
$edited:=""
$far:=""
If (Is editing text)
 $edited:=Get edited text
End if
For each ($item; Form.rows)
 If ($item.id="line-0600")
  $far:=$item.name
 End if
End for each
$state:=New object("phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "start"; Form.startResult; "bridgeError"; Form.axbError; "failure"; Form.failure; "selected"; Form.selected.extract("id"); "hooks"; Form.hooks; "hookSelection"; Form.hookSelection; "timerTicks"; Form.timerTicks; "note"; Form.note; "first"; Form.rows[0].id; "rows"; Form.rows.length; "receipt"; Form.axbForm.receipt; "edited"; $edited; "focus"; OBJECT Get name(Object with focus); "farValue"; $far; "changes"; Form.changes; "edits"; Form.edits; "filtered"; Form.filtered)
$state.diagnostics:=AXB_Form("diagnostics"; New object)
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
""")
        click = (methods / "AXBG_Click.4dm").read_text().replace('aGridKey{2}', 'Form.rows[1].id').replace('aGridKey{1}', 'Form.rows[0].id').replace('LISTBOX SORT COLUMNS(*; "Items"; 1; <)', 'Form.rows:=Form.rows.orderBy("id desc")').replace('LISTBOX DELETE ROWS(*; "Items"; 1; 1)', 'Form.rows.remove(0)\n  Form.rows:=Form.rows')
        click = 'var $copy : Collection\nvar $item : Object\n' + click.replace('Case of\n', 'Case of\n : (OBJECT Get name(Object current)="Rebind")\n  $copy:=New collection\n  For each ($item; Form.rows)\n   $copy.push(New object("id"; $item.id; "name"; $item.name; "amount"; $item.amount))\n  End for each\n  Form.rows:=$copy\n  Form.selected:=New collection\n', 1)
        (methods / "AXBG_Click.4dm").write_text(click)
    if args.entity:
        tables = []
        indexes = []
        for table_number, table_name in [(1, "AXBGItem"), (2, "AXBGOther")]:
            table_id, primary_id = uuid.uuid4().hex.upper(), uuid.uuid4().hex.upper()
            fields = [f'<field name="id" uuid="{primary_id}" type="4" unique="true" never_null="true" id="1"/>']
            for field_number, field_name, field_type in [(2, "displayKey", 10), (3, "name", 10), (4, "amount", 6), (5, "duplicateKey", 4)]:
                fields.append(f'<field name="{field_name}" uuid="{uuid.uuid4().hex.upper()}" type="{field_type}" id="{field_number}"/>')
            tables.append(f'<table name="{table_name}" uuid="{table_id}" id="{table_number}">' + "".join(fields) + f'<primary_key field_name="id" field_uuid="{primary_id}"/></table>')
            indexes.append(f'<index kind="regular" unique_keys="true" name="{table_name}_PK" uuid="{uuid.uuid4().hex.upper()}" type="7"><field_ref uuid="{primary_id}" name="id"><table_ref uuid="{table_id}" name="{table_name}"/></field_ref></index>')
        (sources / "catalog.4DCatalog").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n' + f'<base name="LogicalGridFixture" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en"><schema name="DEFAULT_SCHEMA"/>' + "".join(tables + indexes) + '</base>\n')
        startup = (database / "onStartup.4dm").read_text()
        start, end = startup.index('$data.rows:=New collection'), startup.index('$window:=Open form window')
        startup = startup[:start] + '$data.rows:=ds.AXBGItem.all().orderBy("id asc")\n' + startup[end:]
        startup = startup.replace('$item.id="line-0600"', '$item.displayKey="line-0600"')
        (database / "onStartup.4dm").write_text(startup)
        form_method = (methods / "AXBG_Form.4dm").read_text().replace('Form.selected:=New collection', 'Form.selected:=ds.AXBGItem.newSelection()').replace('"kind"; "collection"; "keyProperty"; "id";', '"kind"; "entity";')
        (methods / "AXBG_Form.4dm").write_text(form_method)
        selected_method = methods / "AXBG_Selected.4dm"
        selected_method.write_text(selected_method.read_text().replace('extract("id")', 'extract("displayKey")'))
        state_method = (methods / "AXBG_State.4dm").read_text().replace('$item.id="line-0600"', '$item.displayKey="line-0600"').replace('Form.selected.extract("id")', 'Form.selected.extract("displayKey")').replace('Form.rows[0].id', 'Form.rows[0].displayKey')
        (methods / "AXBG_State.4dm").write_text(state_method)
        click = (methods / "AXBG_Click.4dm").read_text()
        start, end = click.index('  $copy:=New collection'), click.index(' : (OBJECT Get name(Object current)="Reject selection")')
        click = click[:start] + '  Form.rows:=ds.AXBGOther.all().orderBy("id desc")\n  Form.selected:=ds.AXBGOther.newSelection()\n' + click[end:]
        start, end = click.index('  If (Form.originalSecondKey=Null)'), click.index(' : (OBJECT Get name(Object current)="Sort")')
        click = click[:start] + '  If (Form.axbView.options.grids.Items.keyProperty=Null)\n   Form.axbView.options.grids.Items.keyProperty:="duplicateKey"\n  Else\n   OB REMOVE(Form.axbView.options.grids.Items; "keyProperty")\n  End if\n' + click[end:]
        click = click.replace('Form.rows.remove(0)\n  Form.rows:=Form.rows', 'Form.rows:=Form.rows.slice(1)')
        (methods / "AXBG_Click.4dm").write_text(click)
        (methods / "AXBG_SeedError.4dm").write_text('File("/RESOURCES/seed.json").setText(JSON Stringify(New object("passed"; False; "error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
        (methods / "AXBG_Seed.4dm").write_text("""var $name : Text
var $row : Integer
var $entity; $saved : Object
ON ERR CALL("AXBG_SeedError")
For each ($name; New collection("AXBGItem"; "AXBGOther"))
 For ($row; 1; 600)
  If ($row#2)
   $entity:=ds[$name].new()
   $entity.id:=$row
   $entity.displayKey:="line-"+String($row; "0000")
   Case of
    : ($row=3)
     $entity.displayKey:="café"
    : ($row=4)
     $entity.displayKey:="CAFÉ"
    : ($row=5)
     $entity.displayKey:="CAFE"
    : ($row=6)
     $entity.displayKey:="cafe"
   End case
   $entity.name:="Line item "+String($row; "0000")
   $entity.amount:=$row+0.25
   $entity.duplicateKey:=1
   $saved:=$entity.save()
   If (Not($saved.success))
    File("/RESOURCES/seed.json").setText(JSON Stringify(New object("passed"; False; "save"; $saved)))
    QUIT 4D
    return
   End if
  End if
 End for
End for each
File("/RESOURCES/seed.json").setText(JSON Stringify(New object("passed"; (ds.AXBGItem.all().length=599) & (ds.AXBGOther.all().length=599))))
QUIT 4D
""")
    objects = {"Items": {"type": "listbox", "left": 20, "top": 20, "width": 600, "height": 240,
        "dataSource": "aGridSelected", "rowControlSource": "aGridControl", "showHeaders": True, "headerHeight": "22px", "rowHeight": "24px",
        "showFooters": False, "selectionMode": "multiple", "sortable": True, "scrollbarVertical": "always", "scrollbarHorizontal": "always", "columns": []},
        "NoteLabel": {"type": "text", "text": "Note", "left": 20, "top": 285, "width": 60, "height": 24},
        "Note": {"type": "input", "dataSource": "Form.note", "left": 90, "top": 285, "width": 400, "height": 24}}
    for name, binding, label, width in [("RowID", "aGridKey", "Internal identity", 100), ("ItemName", "aGridName", "Description", 480), ("ItemAmount", "aGridAmount", "Amount", 180)]:
        column = {"name": name, "dataSource": binding, "width": width, "enterable": name == "ItemName", "header": {"name": name + "Header", "text": label}}
        if name == "ItemName":
            column.update(method="AXBG_Column", events=["onBeforeKeystroke", "onDataChange", "onAfterEdit"])
        objects["Items"]["columns"].append(column)
    for index, name in enumerate(["Sort", "Bottom", "Top", "Scope", "Remove", "Close"]):
        button = {"type": "button", "text": name, "left": 20 + index * 100, "top": 330, "width": 90, "height": 28}
        if name == "Close":
            button["action"] = "accept"
        else:
            button.update(method="AXBG_Click", events=["onClick"])
        objects[name] = button
    for index, name in enumerate(["Toggle ready", "Toggle valid keys"]):
        objects[name] = {"type": "button", "text": name, "left": 20 + index * 180, "top": 370, "width": 165, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
    if args.collection or args.entity:
        grid = objects["Items"]
        grid.update(listboxType="collection", dataSource="Form.rows", currentItemSource="Form.current", selectedItemsSource="Form.selected")
        grid.pop("rowControlSource")
        for column, property_name in zip(grid["columns"], ["id", "name", "amount"]):
            column["dataSource"] = "This." + property_name
        objects["Rebind"] = {"type": "button", "text": "Rebind", "left": 390, "top": 370, "width": 130, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
    objects["Reject selection"] = {"type": "button", "text": "Reject selection", "left": 530, "top": 370, "width": 100, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
    if args.boolean_hidden:
        for method in [methods / "Compiler_AXBG.4dm", database / "onStartup.4dm"]:
            source = method.read_text().replace("ARRAY LONGINT(aGridControl;", "ARRAY BOOLEAN(aGridControl;")
            source = source.replace("aGridControl{2}:=lk row is hidden", "aGridControl{2}:=True")
            source = source.replace("aGridControl{3}:=lk row is disabled\n", "").replace("aGridControl{4}:=lk row is not selectable\n", "")
            method.write_text(source)
        objects["Toggle hidden"] = {"type": "button", "text": "Toggle hidden", "left": 390, "top": 370, "width": 130, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
        click = methods / "AXBG_Click.4dm"
        click.write_text(click.read_text().replace("Case of\n", 'Case of\n : (OBJECT Get name(Object current)="Toggle hidden")\n  aGridControl{Find in array(aGridKey; "line-0600")}:=Not(aGridControl{Find in array(aGridKey; "line-0600")})\n', 1))
    if args.cell_controls:
        compiler = methods / "Compiler_AXBG.4dm"
        compiler.write_text(compiler.read_text() + "ARRAY BOOLEAN(aGridCheck; 0)\nARRAY BOOLEAN(aGridPopup; 0)\nARRAY LONGINT(aGridMixed; 0)\nC_OBJECT(AXBG_WidgetState; $0)\nC_LONGINT(AXBG_WidgetEvent; $0)\n")
        startup = database / "onStartup.4dm"
        source = startup.read_text().replace("ARRAY TEXT(aGridKey; 600)", "ARRAY BOOLEAN(aGridCheck; 600)\nARRAY BOOLEAN(aGridPopup; 600)\nARRAY LONGINT(aGridMixed; 600)\nARRAY TEXT(aGridKey; 600)")
        source = source.replace(' aGridKey{$row}:=', ' aGridMixed{$row}:=Choose(($row>=5) & ($row<=8); 4-$row; 0)\n aGridKey{$row}:=', 1)
        source = source.replace('"amount"; aGridAmount{$row}))', '"amount"; aGridAmount{$row}; "approved"; False; "decision"; False; "mixed"; aGridMixed{$row}))')
        startup.write_text(source)
        if args.entity:
            import xml.etree.ElementTree as ET
            catalog = sources / "catalog.4DCatalog"
            xml = ET.fromstring(catalog.read_text())
            for table in xml.findall("table"):
                for number, name, kind in [(6, "approved", 1), (7, "decision", 1), (8, "mixed", 4)]:
                    table.insert(len(table.findall("field")), ET.Element("field", name=name, uuid=uuid.uuid4().hex.upper(), type=str(kind), id=str(number)))
            catalog.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n' + ET.tostring(xml, encoding="unicode") + "\n")
            seed = methods / "AXBG_Seed.4dm"
            seed.write_text(seed.read_text().replace('   $saved:=$entity.save()', '   $entity.approved:=False\n   $entity.decision:=False\n   $entity.mixed:=Choose(($row>=5) & ($row<=8); 4-$row; 0)\n   $saved:=$entity.save()'))
        for name, variable, property_name, extra in [
            ("Approved", "aGridCheck", "approved", {"controlType": "checkbox", "controlTitle": "Approved; reviewed"}),
            ("Decision", "aGridPopup", "decision", {"controlType": "popup", "booleanFormat": "Allowed;Denied"}),
            ("Mixed", "aGridMixed", "mixed", {"controlType": "checkbox", "threeState": True, "numberFormat": "###0"}),
        ]:
            objects["Items"]["columns"].append({"name": name, "dataSource": "This."+property_name if args.collection or args.entity else variable,
                "width": 180, "enterable": True, "dataSourceTypeHint": "number" if name == "Mixed" else "boolean", "header": {"name": name+"Header", "text": name}, "method": "AXBG_WidgetEvent", "events": ["onBeforeDataEntry", "onDataChange"], **extra})
        form_method = methods / "AXBG_Form.4dm"
        form_method.write_text(form_method.read_text().replace(' : (Form event code=On Load)', ' : (Form event code=On Load)\n  Form.widgetEvents:=New collection\n  Form.widgetSequence:=0'))
        state_method = methods / "AXBG_State.4dm"
        state_method.write_text(state_method.read_text().replace('File("/RESOURCES/runtime-status.json")', '$state.widgets:=AXBG_WidgetState\nFile("/RESOURCES/runtime-status.json")'))
    if args.described:
        compiler = methods / "Compiler_AXBG.4dm"
        compiler.write_text(compiler.read_text() + "ARRAY PICTURE(aGridPicture; 0)\n")
        startup = database / "onStartup.4dm"
        startup.write_text(startup.read_text().replace("For ($row; 1; 600)", 'var $icon : Picture\nARRAY PICTURE(aGridPicture; 600)\nREAD PICTURE FILE(File("/RESOURCES/ready.png").platformPath; $icon)\nFor ($row; 1; 600)\n aGridPicture{$row}:=$icon', 1))
        # Same small synthetic status image used by the AreaList fixture.
        def png_chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        icon = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 12, 12, 8, 6, 0, 0, 0))
        icon += png_chunk(b"IDAT", zlib.compress((b"\0" + bytes([0, 140, 40, 255]) * 12) * 12)) + png_chunk(b"IEND", b"")
        (FIXTURE / "Resources/ready.png").write_bytes(icon)
        form_method = methods / "AXBG_Form.4dm"
        form_method.write_text(form_method.read_text().replace('  $result:=AXB_Form("start";', '''  Form.descriptionCalls:=0
  Form.protectedCalls:=0
  Form.badDescription:=False
  Form.customEditable:=False
  $options.grids.Items.columns:=New object("ItemStatus"; New object("label"; "Readiness"; "value"; Formula(AXBG_Describe($1))); "ItemSecret"; New object("value"; Formula(AXBG_Describe($1))); "ItemDecoration"; New object("decorative"; True); "RowID"; New object("value"; Formula(AXBG_Describe($1))))
  Form.providerOptions:=$options
  $result:=AXB_Form("start";'''))
        state_method = methods / "AXBG_State.4dm"
        state_method.write_text(state_method.read_text().replace('$state.diagnostics:=', '$state.descriptionCalls:=Form.descriptionCalls\n$state.protectedCalls:=Form.protectedCalls\n$state.badDescription:=Form.badDescription\n$state.customEditable:=Form.customEditable\n$state.diagnostics:='))
        click = methods / "AXBG_Click.4dm"
        click.write_text('var $bridge : Object\n' + click.read_text().replace('Case of\n', '''Case of
 : (OBJECT Get name(Object current)="Custom editing")
  Form.customEditable:=Not(Form.customEditable)
  OBJECT SET ENTERABLE(*; "ItemStatus"; Form.customEditable)
  OBJECT SET ENTERABLE(*; "ItemSecret"; Form.customEditable)
  OBJECT SET ENTERABLE(*; "ItemDecoration"; Form.customEditable)
 : (OBJECT Get name(Object current)="Descriptions")
  Form.badDescription:=Not(Form.badDescription)
  If (Form.badDescription)
   Form.providerOptions.grids.Items.columns.ItemStatus.value:=Formula(42)
  Else
   Form.providerOptions.grids.Items.columns.ItemStatus.value:=Formula(AXBG_Describe($1))
  End if
  If (Form.fixtureSubform=True)
   Form.restartRequested:=True
  Else
   $bridge:=AXB_Form("stop"; New object)
   $bridge:=AXB_Form("start"; Form.providerOptions)
   Form.startResult:=$bridge
  End if
''', 1))
        grid = objects["Items"]
        for name, binding, label in [
            ("ItemStatus", "Uppercase(This.name)" if args.collection or args.entity else "aGridPicture", "Status image"),
            ("ItemDecoration", '"PRIVATE-DECORATION"' if args.collection or args.entity else "aGridName", "Decoration"),
            ("ItemSecret", "This.name" if args.collection or args.entity else "aGridName", "Protected"),
        ]:
            column = {"name": name, "dataSource": binding, "width": 180, "enterable": False, "header": {"name": name + "Header", "text": label}}
            if name == "ItemSecret":
                column["fontFamily"] = "%password"
            grid["columns"].append(column)
        objects["Descriptions"] = {"type": "button", "text": "Descriptions", "left": 410, "top": 285, "width": 200, "height": 26, "method": "AXBG_Click", "events": ["onClick"]}
        objects["Custom editing"] = {"type": "button", "text": "Custom editing", "left": 20, "top": 410, "width": 200, "height": 26, "method": "AXBG_Click", "events": ["onClick"]}
        objects["Note"]["width"] = 280
        if args.object_description:
            compiler.write_text(compiler.read_text() + "ARRAY OBJECT(aGridObject; 0)\n")
            startup.write_text(startup.read_text().replace("ARRAY PICTURE(aGridPicture; 600)", "ARRAY PICTURE(aGridPicture; 600)\nARRAY OBJECT(aGridObject; 600)").replace(' aGridPicture{$row}:=$icon', ' aGridPicture{$row}:=$icon\n aGridObject{$row}:=New object("valueType"; "text"; "value"; "Ready: Line item "+String($row; "0000"); "private"; "PRIVATE-NOT-SERIALIZED")'))
            next(c for c in grid["columns"] if c["name"] == "ItemStatus")["dataSource"] = "aGridObject"
        if args.styled_description:
            next(c for c in grid["columns"] if c["name"] == "ItemStatus").update(multiStyle=True, dataSource='"<span style=\'font-weight:bold\'>"+This.name+"</span>"')
    if args.row_states:
        compiler = methods / "Compiler_AXBG.4dm"
        compiler.write_text(compiler.read_text() + "C_OBJECT(AXBG_Meta; $0)\n")
        form_method = methods / "AXBG_Form.4dm"
        form_method.write_text(form_method.read_text().replace('  $result:=AXB_Form("start";', '  Form.metaCalls:=0\n  Form.disableFar:=False\n  Form.invalidMeta:=False\n  Form.otherMeta:=False\n  Form.unselectFar:=False\n  Form.restrictOnSelection:=False\n  Form.swappedMeta:=False\n  Form.metaArgumentsOK:=True\n  Form.metaContext:="row-metadata-fixture"\n  Form.expectedMetaKey:="id"\n  $result:=AXB_Form("start";', 1))
        (methods / "AXBG_Meta.4dm").write_text('''#DECLARE() -> $meta : Object
// The same ordinary application formatter serves native 4D and the bridge.
Form.metaCalls:=Form.metaCalls+1
$meta:=New object("disabled"; (This.amount=3.25) | ((This.amount=600.25) & (Form.disableFar=True)); "unselectable"; (This.amount=4.25) | ((This.amount=600.25) & (Form.unselectFar=True)))
// Native cell-level disabled flags are ignored by 4D; the bridge must agree.
$meta.cell:=New object("ItemName"; New object("disabled"; True))
If (This.amount=7.25)
 $meta.disabled:=Null
 $meta.unselectable:=Null
End if
''')
        if args.collection or args.entity:
            objects["Items"]["metaSource"] = "This.meta" if args.stored_meta else "AXBG_Meta"
            if not args.stored_meta:
                (methods / "AXBG_MetaOther.4dm").write_text('#DECLARE() -> $meta : Object\n$meta:=New object\n')
                compiler.write_text(compiler.read_text() + "C_OBJECT(AXBG_MetaOther; $0)\n")
                compiler.write_text(compiler.read_text() + "C_OBJECT(AXBG_MetaBridge; $1)\nC_VARIANT(AXBG_MetaBridge; $0)\n")
                (methods / "AXBG_MetaBridge.4dm").write_text('''#DECLARE($request : Object) -> $meta : Variant
var $same : Boolean
$same:=(New collection(This).indexOf($request.item)=0) & ($request.key=This[Form.expectedMetaKey]) & ($request.row>=1) & ($request.row=Int($request.row)) & (Form.metaContext="row-metadata-fixture")
If (Not($same) & (Form.metaArgumentFailure=Null))
 Form.metaArgumentFailure:=New object("key"; $request.key; "expectedKey"; This[Form.expectedMetaKey]; "row"; $request.row; "sameItem"; New collection(This).indexOf($request.item)=0; "context"; Form.metaContext)
End if
Form.metaArgumentsOK:=Form.metaArgumentsOK & $same
If ($request.row=1)
 Form.metaFirst:=New object("row"; $request.row; "key"; $request.key; "keyType"; Value type($request.key))
End if
If (Form.invalidMeta)
 $meta:=42
Else
 $meta:=AXBG_Meta
End if
''')
                objects["Metadata source"] = {"type": "button", "text": "Metadata source", "left": 310, "top": 410, "width": 200, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
            form_method = methods / "AXBG_Form.4dm"
            metadata_setup = ''
            if args.stored_meta:
                metadata_setup += '  var $item : Object\n  For each ($item; Form.rows)\n   $item.meta:=New object("disabled"; $item.amount=3.25; "unselectable"; $item.amount=4.25)\n   If ($item.amount=7.25)\n    $item.meta:=New object("disabled"; Null; "unselectable"; Null)\n   End if\n   $item.alternateMeta:=OB Copy($item.meta)\n  End for each\n'
            else:
                metadata_setup += '  $options.grids.Items.meta:=Formula(AXBG_MetaBridge($1))\n'
            form_method.write_text(form_method.read_text().replace('  $result:=AXB_Form("start";', metadata_setup + '  $result:=AXB_Form("start";', 1))
        click = methods / "AXBG_Click.4dm"
        click.write_text(click.read_text().replace('Case of\n', '''Case of
 : (OBJECT Get name(Object current)="Metadata source")
  Form.otherMeta:=Not(Form.otherMeta)
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; Choose(Form.otherMeta; "AXBG_MetaOther"; "AXBG_Meta"))
 : (OBJECT Get name(Object current)="Single click")
  LISTBOX SET PROPERTY(*; "Items"; lk single click edit; 1-LISTBOX Get property(*; "Items"; lk single click edit))
 : (OBJECT Get name(Object current)="Selection none")
  If (LISTBOX Get property(*; "Items"; lk selection mode)=lk none)
   LISTBOX SET PROPERTY(*; "Items"; lk selection mode; lk multiple)
  Else
   LISTBOX SET PROPERTY(*; "Items"; lk selection mode; lk none)
  End if
 : (OBJECT Get name(Object current)="Disable far")
  Form.disableFar:=Not(Form.disableFar)
  AXBG_RowFlags
 : (OBJECT Get name(Object current)="Restrict selection")
  Form.unselectFar:=Not(Form.unselectFar)
  AXBG_RowFlags
 : (OBJECT Get name(Object current)="Restrict during selection")
  Form.restrictOnSelection:=Not(Form.restrictOnSelection)
 : (OBJECT Get name(Object current)="Swap stored metadata")
  Form.swappedMeta:=Not(Form.swappedMeta)
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; Choose(Form.swappedMeta; "This.alternateMeta"; "This.meta"))
 : (OBJECT Get name(Object current)="Invalid metadata")
  Form.invalidMeta:=Not(Form.invalidMeta)
''', 1))
        if args.entity:
            click.write_text(click.read_text().replace('Form.axbView.options.grids.Items.keyProperty:="duplicateKey"', 'Form.axbView.options.grids.Items.keyProperty:="duplicateKey"\n   Form.expectedMetaKey:="duplicateKey"').replace('OB REMOVE(Form.axbView.options.grids.Items; "keyProperty")', 'OB REMOVE(Form.axbView.options.grids.Items; "keyProperty")\n   Form.expectedMetaKey:="id"'))
        (methods / "AXBG_RowFlags.4dm").write_text('''var $item : Object
If (Form.rows=Null)
 aGridControl{Find in array(aGridKey; "line-0600")}:=Choose(Form.disableFar; lk row is disabled; 0)+Choose(Form.unselectFar; lk row is not selectable; 0)
Else
 If (Value type(Form.rows)=Is collection)
  For each ($item; Form.rows)
   If ($item.amount=600.25)
    $item.meta:=New object("disabled"; Form.disableFar; "unselectable"; Form.unselectFar)
    $item.alternateMeta:=OB Copy($item.meta)
   End if
  End for each
 End if
End if
''')
        selected_method = methods / "AXBG_Selected.4dm"
        selected_method.write_text(selected_method.read_text().replace('AXBG_State', 'If (Form.restrictOnSelection=True)\n Form.unselectFar:=True\n AXBG_RowFlags\nEnd if\nAXBG_State'))
        state_method = methods / "AXBG_State.4dm"
        state_method.write_text(state_method.read_text().replace('$state.diagnostics:=', '$state.metaCalls:=Form.metaCalls\n$state.metaFirst:=Form.metaFirst\n$state.metaArgumentsOK:=Form.metaArgumentsOK\n$state.metaArgumentFailure:=Form.metaArgumentFailure\n$state.otherMeta:=Form.otherMeta\n$state.unselectFar:=Form.unselectFar\n$state.restrictOnSelection:=Form.restrictOnSelection\n$state.swappedMeta:=Form.swappedMeta\n$state.singleClick:=LISTBOX Get property(*; "Items"; lk single click edit)\n$state.selectionMode:=LISTBOX Get property(*; "Items"; lk selection mode)\n$state.disableFar:=Form.disableFar\n$state.invalidMeta:=Form.invalidMeta\n$state.diagnostics:='))
        for index, name in enumerate(["Single click", "Selection none", "Disable far", "Invalid metadata"]):
            objects[name] = {"type": "button", "text": name, "left": 20 + index * 150, "top": 450, "width": 140, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
        for index, name in enumerate(["Restrict selection", "Swap stored metadata", "Restrict during selection"]):
            if name == "Swap stored metadata" and not args.stored_meta:
                continue
            objects[name] = {"type": "button", "text": name, "left": 20 + index * 200, "top": 490, "width": 190, "height": 28, "method": "AXBG_Click", "events": ["onClick"]}
    state_method = methods / "AXBG_State.4dm"
    state_method.write_text('var $context; $snapshot : Object\n' + state_method.read_text().replace('$state.diagnostics:=', '$state.rejectSelection:=Form.rejectSelection\n$context:=AXB_FormContext\nIf (($context#Null) && ($context.state#Null) && (Length($context.state)>0))\n $snapshot:=JSON Parse($context.state)\n $state.windowActive:=$snapshot.enabled\n $state.focused:=$snapshot.nodes.query("focused = :1"; True).extract("id")\nEnd if\n$state.diagnostics:='))
    form = {"windowTitle": TITLE, "width": 645, "height": 550 if args.row_states else 465 if args.described else 425, "method": "AXBG_Form", "events": ["onLoad", "onTimer", "onUnload"], "pages": [None, {"objects": objects}]}
    folder = sources / "Forms/Grid"
    folder.mkdir(parents=True)
    (folder / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    if args.subform:
        startup = database / "onStartup.4dm"
        startup.write_text(startup.read_text().replace('Open form window("Grid";', 'Open form window("Root";').replace('DIALOG("Grid"; $data)', 'DIALOG("Root"; New object("grid"; $data))'))
        child_method = methods / "AXBG_Form.4dm"
        child_method.write_text(child_method.read_text().replace('  $result:=AXB_Form("start"; $options)', '  $options.label:="Grid"\n  Form.providerOptions:=$options\n  Form.fixtureSubform:=True\n  OBJECT SET VISIBLE(*; "Close"; False)').replace('  Form.startResult:=$result\n', '').replace('  SET TIMER(6)\n', '').replace('  AXBG_State\n', '').replace('  $result:=AXB_Form("stop"; New object)', '  // The root owns bridge cleanup.'))
        if args.entity:
            click = methods / "AXBG_Click.4dm"
            source = click.read_text().replace("Form.axbView.options", "Form.providerOptions")
            boundary = source.index(' : (OBJECT Get name(Object current)="Sort")')
            source = source[:boundary] + '  Form.restartRequested:=True\n' + source[boundary:]
            click.write_text(source)
        state_method = methods / "AXBG_State.4dm"
        # The child has no root registration. Its read-only observer consumes
        # the snapshot captured by the owning root, just like diagnostics.
        state_method.write_text(state_method.read_text().replace('"bridgeError"; Form.axbError', '"bridgeError"; Form.rootBridgeError').replace('"failure"; Form.failure', '"failure"; Form.rootFailure').replace('AXB_Form("diagnostics"; New object)', 'Form.rootCoverage').replace('$context:=AXB_FormContext', '$context:=New object("state"; Form.rootSnapshot)'))
        (methods / "AXBG_Root.4dm").write_text('''var $options; $reply : Object
var $context : Object
Case of
 : (Form event code=On Load)
  ON ERR CALL("AXBG_Error")
  SET TIMER(6)
 : (Form event code=On Timer)
  If (Form.grid.restartRequested=True)
   $reply:=AXB_Form("stop"; New object)
   Form.bridgeStarted:=False
   Form.grid.restartRequested:=False
  End if
  If ((Form.grid.providerOptions#Null) & Not(Form.bridgeStarted=True))
   $options:=New object("label"; "Grid in page subform"; "scope"; Formula(Form.grid.scope); "children"; New object("Grid"; Form.grid.providerOptions))
   $reply:=AXB_Form("start"; $options)
   Form.grid.startResult:=$reply
   Form.bridgeStarted:=True
  End if
  If (Form.bridgeStarted=True)
   Form.grid.timerTicks:=Form.grid.timerTicks+1
   Form.grid.rootBridgeError:=Form.axbError
   Form.grid.rootFailure:=Form.axbFailure
   Form.grid.rootCoverage:=AXB_Form("diagnostics"; New object)
   $context:=AXB_FormContext
   Form.grid.rootSnapshot:=$context.state
   EXECUTE METHOD IN SUBFORM("Grid"; "AXBG_State")
  End if
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
''')
        root_form = {"windowTitle": TITLE, "width": 685, "height": 610 if args.row_states else 520, "method": "AXBG_Root", "events": ["onLoad", "onTimer", "onUnload"], "pages": [None, {"objects": {
            "Grid": {"type": "subform", "detailForm": "Grid", "dataSource": "Form.grid", "left": 20, "top": 20, "width": 645, "height": 550 if args.row_states else 465},
            "Close": {"type": "button", "text": "Close", "left": 20, "top": 577 if args.row_states else 487, "width": 140, "height": 28, "action": "accept"},
        }}]}
        root_folder = sources / "Forms/Root"
        if args.repeated:
            child_method.write_text('var $observer : Object\n$observer:=AXB_Form("event"; New object)\n'+child_method.read_text())
            startup.write_text(startup.read_text().replace('New object("grid"; $data)', 'New object("grid"; $data; "peer"; OB Copy($data))'))
            root_form["width"] = 1350
            root_form["pages"][1]["objects"]["Peer"] = {"type": "subform", "detailForm": "Grid", "dataSource": "Form.peer", "left": 685, "top": 20, "width": 645, "height": 550}
            root_method = methods / "AXBG_Root.4dm"
            root_source = root_method.read_text().replace('var $options; $reply : Object', 'var $options; $reply; $peer : Object')
            root_source = root_source.replace('If ((Form.grid.providerOptions#Null) & Not(Form.bridgeStarted=True))', 'If ((Form.grid.providerOptions#Null) & (Form.peer.providerOptions#Null) & Not(Form.bridgeStarted=True))')
            root_source = root_source.replace('   $reply:=AXB_Form("start"; $options)', '   Form.peer.providerOptions.label:="Peer"\n   $options.children.Peer:=Form.peer.providerOptions\n   $reply:=AXB_Form("start"; $options)')
            root_source = root_source.replace('   EXECUTE METHOD IN SUBFORM("Grid"; "AXBG_State")', '   EXECUTE METHOD IN SUBFORM("Grid"; "AXBG_State")\n   Form.peer.widgetReadOnly:=True\n   EXECUTE METHOD IN SUBFORM("Peer"; "AXBG_WidgetState"; $peer)\n   Form.grid.peerWidgets:=$peer')
            root_method.write_text(root_source)
            state_method.write_text(state_method.read_text().replace('$state.widgets:=AXBG_WidgetState', '$state.widgets:=AXBG_WidgetState\n$state.peerWidgets:=Form.peerWidgets'))
        root_folder.mkdir()
        (root_folder / "form.4DForm").write_text(json.dumps(root_form, indent=2) + "\n")
    if args.key_type != "text":
        minimum, maximum = (-32768, 32767) if args.key_type == "integer" else (-2147483648, 2147483647)
        command = "INTEGER" if args.key_type == "integer" else "LONGINT"
        for method in [*methods.glob("AXBG_*.4dm"), methods / "Compiler_AXBG.4dm", database / "onStartup.4dm"]:
            source = method.read_text().replace("ARRAY TEXT(aGridKey;", f"ARRAY {command}(aGridKey;")
            source = source.replace('aGridKey{$row}:="line-"+String($row; "0000")', 'aGridKey{$row}:=$row')
            for old, new in [('"café"', minimum), ('"CAFÉ"', minimum + 1), ('"CAFE"', 0), ('"cafe"', maximum - 1), ('"line-0600"', maximum)]:
                source = source.replace(old, str(new))
            if method.name == "onStartup.4dm":
                source = source.replace('$data:=New object', f'aGridKey{{600}}:={maximum}\n$data:=New object', 1)
            method.write_text(source)
    if args.slow_visible_selection:
        form_method = methods / "AXBG_Form.4dm"
        form_method.write_text(form_method.read_text().replace('Formula(Form.scope)', 'Formula(AXBG_SlowScope)').replace('; "onSelection"; Formula(AXBG_Selected)', ''))
        (methods / "AXBG_SlowScope.4dm").write_text('''// Simulate an expensive application callback while a selection is pending.
#DECLARE() -> $scope : Text
If ((Form.axbForm#Null) && (Form.axbForm.pending#Null))
 DELAY PROCESS(Current process; 70)
End if
$scope:=Form.scope
''')
        compiler = methods / "Compiler_AXBG.4dm"
        compiler.write_text(compiler.read_text() + "C_TEXT(AXBG_SlowScope; $0)\n")
    if args.slow_distant_selection:
        selected = methods / "AXBG_Selected.4dm"
        selected.write_text("DELAY PROCESS(Current process; 150)\n" + selected.read_text())
    (FIXTURE / "Resources/launch.json").write_text(json.dumps({"runId": uuid.uuid4().hex, "keyType": args.key_type, "kind": "entity" if args.entity else "collection" if args.collection else "array", "described": args.described, "objectDescription": args.object_description, "styledDescription": args.styled_description, "subform": args.subform, "repeated": args.repeated, "rowStates": args.row_states, "storedMeta": args.stored_meta, "cellControls": args.cell_controls, "slowVisibleSelection": args.slow_visible_selection, "slowDistantSelection": args.slow_distant_selection, "booleanHidden": args.boolean_hidden}) + "\n")
    if args.entity:
        with (FIXTURE / "seed.log").open("w") as log:
            seeded = subprocess.run([str(server / "Contents/MacOS" / info["CFBundleExecutable"]), "--project", str(project), "--data", str(FIXTURE / "synthetic.4dd"), "--create-data", "--headless", "--utility", "--skip-onstartup", "--startup-method", "AXBG_Seed", "--webadmin-auto-start", "false"], stdout=log, stderr=log, timeout=90)
        seed_report = json.loads((FIXTURE / "Resources/seed.json").read_text(encoding="utf-8-sig"))
        if seeded.returncode or seed_report.get("passed") is not True:
            raise RuntimeError("Synthetic entity seeding failed: " + str(seed_report))
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="logical-grid-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    passed = compiled.get("success") is True and not compiled.get("errors")
    (BUILD / "logical-grid-compile-report.json").write_text(json.dumps({"passed": passed, "compiler": compiled, "sources_sha256": hashes,
        "native_sha256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ")}, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: logical-grid fixture compilation")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
