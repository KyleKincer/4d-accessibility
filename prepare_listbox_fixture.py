#!/usr/bin/env python3
"""Prepare and compile isolated native-listbox adapter tests with synthetic data."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "listbox-fixture"
TITLE = "AX bridge native list boxes"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--entity", action="store_true", help="Use a synthetic entity selection for the second grid")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing this disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("listbox-fixture-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "ListboxFixture")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    table_uuid, key_uuid, label_uuid, number_uuid, nullable_uuid, other_uuid, other_key_uuid = (uuid.uuid4().hex.upper() for _ in range(7))
    (sources / "catalog.4DCatalog").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd" >\n'
        f'<base name="ListboxFixture" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en">\n\t<schema name="DEFAULT_SCHEMA"/>\n'
        f'\t<table name="AXBItem" uuid="{table_uuid}" id="1">\n\t\t<field name="id" uuid="{key_uuid}" type="10" unique="true" never_null="true" id="1"/>\n'
        f'\t\t<field name="name" uuid="{label_uuid}" type="10" id="2"/>\n'
        f'\t\t<field name="number" uuid="{number_uuid}" type="4" id="3"/>\n'
        f'\t\t<field name="optionalLabel" uuid="{nullable_uuid}" type="10" id="4"/>\n'
        f'\t\t<primary_key field_name="id" field_uuid="{key_uuid}"/>\n\t</table>\n'
        f'\t<table name="AXBOther" uuid="{other_uuid}" id="2">\n'
        f'\t\t<field name="id" uuid="{other_key_uuid}" type="10" unique="true" never_null="true" id="1"/>\n'
        f'\t\t<primary_key field_name="id" field_uuid="{other_key_uuid}"/>\n\t</table>\n</base>')
    (sources / "Classes").mkdir(exist_ok=True)
    (sources / "Classes/AXBItemEntity.4dm").write_text('Class extends Entity\n\nFunction get computedName() -> $value : Text\n $value:=This.name\n')
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for path in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(path, methods / path.name)
    for path in (ROOT / "tests/4d").glob("AXBL_*.4dm"):
        shutil.copy2(path, methods / path.name)
    walkthrough = ROOT / "skills/4d-accessibility/references/examples/LISTBOX-FORM.md"
    snippets = re.findall(r"```4d\n// (\w+)\n(.*?)```", walkthrough.read_text(), re.S)
    if len(snippets) != 7:
        raise RuntimeError("Listbox walkthrough changed; check the method mapping")
    for name, snippet in snippets:
        (methods / (name + ".4dm")).write_text(snippet)
    (methods / "Compiler_AXBL.4dm").write_text(
        "C_OBJECT(AXBL_Describe; $0)\nC_OBJECT(AXBL_Apply; $0; $1)\nC_OBJECT(AXBL_Failed; $1)\n"
        "C_TEXT(AXBL_Selection; $1)\n"
        "ARRAY TEXT(aListID; 0)\nARRAY TEXT(aListName; 0)\nARRAY BOOLEAN(aListSelected; 0)\nARRAY LONGINT(aListControl; 0)\n")
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text('''ON ERR CALL("AXBL_Error")
var $window; $row : Integer
var $data : Object
ARRAY TEXT(aListID; 600)
ARRAY TEXT(aListName; 600)
ARRAY BOOLEAN(aListSelected; 600)
ARRAY LONGINT(aListControl; 600)
$data:=New object("rows"; New collection; "selected"; New collection; "runId"; JSON Parse(File("/RESOURCES/launch.json").getText()).runId)
$data.entity:=JSON Parse(File("/RESOURCES/launch.json").getText()).entity
$data.leftPicker:=New object("isSubform"; True; "items"; New collection(New object("id"; "left-1"; "name"; "Left item one"); New object("id"; "left-2"; "name"; "Left item two")); "selectedItems"; New collection)
$data.rightPicker:=New object("isSubform"; True; "items"; New collection(New object("id"; "right-1"; "name"; "Right item one"); New object("id"; "right-2"; "name"; "Right item two")); "selectedItems"; New collection)
For ($row; 1; 600)
 aListID{$row}:="A"+String($row; "0000")
 aListName{$row}:="Array item "+String($row; "0000")
 $data.rows.push(New object("id"; "C"+String($row; "0000"); "name"; "Collection item "+String($row; "0000")))
End for
If ($data.entity=True)
 $data.rows:=ds.AXBItem.all().orderBy("id asc")
 $data.selected:=ds.AXBItem.newSelection()
 $data.leftPicker:=New object("isSubform"; True; "entity"; True; "items"; ds.AXBItem.query("id in :1"; New collection("C0001"; "C0002")); "selectedItems"; ds.AXBItem.newSelection())
 $data.rightPicker:=New object("isSubform"; True; "entity"; True; "items"; ds.AXBItem.query("id in :1"; New collection("C0003"; "C0004")); "selectedItems"; ds.AXBItem.newSelection())
 ALL RECORDS([AXBItem])
 FIRST RECORD([AXBItem])
 [AXBItem]name:="Unsaved record buffer sentinel"
End if
aListControl{2}:=lk row is hidden
aListControl{3}:=lk row is disabled
aListControl{4}:=lk row is not selectable
$window:=Open form window("Lists"; Plain form window)
DIALOG("Lists"; $data)
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "AXBL_Error.4dm").write_text('File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "code"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (methods / "AXBL_Seed.4dm").write_text('''ON ERR CALL("AXBL_Error")
var $entity; $saved : Object
var $i : Integer
For ($i; 1; 600)
 $entity:=ds.AXBItem.new()
 $entity.id:="C"+String($i; "0000")
 $entity.name:="Collection item "+String($i; "0000")
 $entity.number:=$i
 $entity.optionalLabel:=$entity.name
 If ($i=6)
  $entity.optionalLabel:=Null
 End if
 $saved:=$entity.save()
 If (Not($saved.success))
  File("/RESOURCES/seed.json").setText(JSON Stringify(New object("passed"; False)))
  QUIT 4D
  return
 End if
End for
File("/RESOURCES/seed.json").setText(JSON Stringify(New object("passed"; ds.AXBItem.all().length=600)))
QUIT 4D
''')
    (FIXTURE / "Resources/launch.json").write_text(json.dumps({"runId": uuid.uuid4().hex, "entity": args.entity}) + "\n")
    objects = {}
    for name, kind, left, source in (("Array", "array", 20, "aListSelected"), ("Collection", "collection", 390, "Form.rows")):
        grid = {"type": "listbox", "left": left, "top": 20, "width": 350, "height": 210,
                "dataSource": source, "showHeaders": True, "headerHeight": "20px", "rowHeight": "24px",
                "showFooters": False, "selectionMode": "multiple", "sortable": True,
                "scrollbarVertical": "always", "scrollbarHorizontal": "always", "columns": [],
                "events": ["onSelectionChange"], "method": "AXBL_Event"}
        for column, width, binding in (("ID", 70, "aListID" if kind == "array" else "This.id"),
                                       ("Name", 450, "aListName" if kind == "array" else "This.name")):
            grid["columns"].append({"name": name + column, "dataSource": binding, "width": width, "enterable": False,
                                    "header": {"name": name + column + "Header", "text": column}})
        if kind == "collection":
            grid.update(listboxType="collection", currentItemSource="Form.current", selectedItemsSource="Form.selected")
        else:
            grid["rowControlSource"] = "aListControl"
        objects[name] = grid
    for i, name in enumerate(("Sort", "Bottom", "Top", "Hide", "Duplicate", "Reset", "Single", "Format", "Rebind", "CaseKeys", "Scope", "CaseLabel", "CancelPending", "Fault", "Filter", "EntityLimits", "EntityWrong", "EntityWrongClass", "EntityNull", "EntityNumeric", "EntityComputed", "EntityNullLabel", "RejectSelection", "ScopeSelection")):
        objects[name] = {"type": "button", "text": name, "left": 20 + (i % 5)*145, "top": 260+(i//5)*40,
                         "width": 135, "height": 28, "method": "AXBL_Click", "events": ["onClick"]}
    # Run the documentation's exact collection methods in two child contexts.
    # Their separate bindings expose routing or deferred Formula-copy mistakes.
    for name, source, left in (("LeftPicker", "Form.leftPicker", 20), ("RightPicker", "Form.rightPicker", 390)):
        objects[name] = {"type": "subform", "detailForm": "ItemPicker", "dataSource": source,
                         "left": left, "top": 480, "width": 350, "height": 200, "borderStyle": "none"}
    picker = {"width": 350, "height": 200, "method": "ListAX_Form", "events": ["onLoad", "onActivate", "onUnload"], "pages": [None, {"objects": {
        "Items": {"type": "listbox", "listboxType": "collection", "dataSource": "Form.items", "selectedItemsSource": "Form.selectedItems",
                  "left": 0, "top": 0, "width": 340, "height": 145, "showHeaders": True, "headerHeight": "20px", "rowHeight": "24px",
                  "selectionMode": "multiple", "events": ["onSelectionChange"], "method": "ListAX_SelectionEvent",
                  "columns": [{"name": "ItemsKey", "dataSource": "This.id", "width": 65, "enterable": False, "header": {"name": "ItemsKeyHeader", "text": "Key"}},
                              {"name": "ItemsName", "dataSource": "This.name", "width": 240, "enterable": False, "header": {"name": "ItemsNameHeader", "text": "Name"}}]},
        "SelectionStatus": {"type": "input", "dataSource": "Form.selectionSummary", "enterable": False, "left": 0, "top": 160, "width": 340, "height": 25}
    }}]}
    picker_folder = sources / "Forms/ItemPicker"
    picker_folder.mkdir(parents=True)
    (picker_folder / "form.4DForm").write_text(json.dumps(picker, indent=2) + "\n")
    form = {"windowTitle": TITLE, "width": 765, "height": 705, "method": "AXBL_Form", "events": ["onLoad", "onUnload"], "pages": [None, {"objects": objects}]}
    folder = sources / "Forms/Lists"
    folder.mkdir(parents=True)
    (folder / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    if args.entity:
        with open(FIXTURE / "seed.log", "wb") as log:
            os.chmod(log.name, 0o600)
            seeded = subprocess.run([str(server / "Contents/MacOS" / info["CFBundleExecutable"]),
                "--project", str(project), "--data", str(FIXTURE / "synthetic.4dd"), "--create-data",
                "--headless", "--utility", "--skip-onstartup", "--startup-method", "AXBL_Seed",
                "--webadmin-auto-start", "false"], stdout=log, stderr=log, timeout=90)
        seed_report = json.loads((FIXTURE / "Resources/seed.json").read_text(encoding="utf-8-sig"))
        if seeded.returncode != 0 or seed_report.get("passed") is not True:
            raise RuntimeError("Synthetic entity fixture seeding failed")
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="listbox-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    passed = compiled.get("success") is True and not compiled.get("errors")
    (BUILD / "listbox-compile-report.json").write_text(json.dumps({"passed": passed, "compiler": compiled, "entity": args.entity,
        "sources_sha256": hashes, "walkthrough_sha256": sha(walkthrough),
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ")}, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: native list-box fixture compilation")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
