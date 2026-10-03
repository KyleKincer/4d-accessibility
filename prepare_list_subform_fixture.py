#!/usr/bin/env python3
"""Prepare an automatically discovered classic list-subform desktop fixture."""

from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET
from build_component import project_at, run_utility, literal, sha, BUILD


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument(
        "--configured",
        action="store_true",
        help="Supply optional central column labels",
    )
    parser.add_argument(
        "--selection-mode",
        choices=("multiple", "single", "none", "default"),
        default="multiple",
    )
    parser.add_argument(
        "--no-primary-key",
        action="store_true",
        help="Use an existing unique field through central configuration",
    )
    parser.add_argument(
        "--table-parent",
        action="store_true",
        help="Open the parent as a table input form",
    )
    parser.add_argument("--no-area", action="store_true")
    parser.add_argument("--auto-modify", action="store_true")
    parser.add_argument("--header", action="store_true")
    parser.add_argument("--multiline", action="store_true")
    parser.add_argument(
        "--horizontal",
        action="store_true",
        help="Force a horizontal scrollbar beneath the rows",
    )
    parser.add_argument(
        "--text-key",
        action="store_true",
        help="Check native edits that change an existing text row key",
    )
    parser.add_argument("--diagnostics-test", action="store_true", help="Keep parent metadata diagnostics when an invalid key disables the list")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    subprocess.run(
        [
            sys.executable,
            str(root / "prepare_selection_fixture.py"),
            "--server",
            str(args.server),
        ],
        check=True,
    )
    fixture = BUILD / "list-subform-fixture"
    if fixture.exists():
        fixture.rename(BUILD / ("list-subform-previous-" + uuid.uuid4().hex))
    (BUILD / "selection-fixture").rename(fixture)
    header = 28 if args.header else 0
    height = 40 if args.multiline else 24
    sources = fixture / "Project/Sources"
    methods = sources / "Methods"
    parent = json.loads((sources / "Forms/Grid/form.4DForm").read_text())
    for name in ("AXBS_Column", "AXBS_Click", "AXBS_Selected"):
        (methods / (name + ".4dm")).unlink(missing_ok=True)
    parent["windowTitle"] = "AX bridge classic list subform"
    parent["pages"][1]["objects"] = {
        "Items": {
            "type": "subform",
            "left": 20,
            "top": 20,
            "width": 650,
            "height": 240,
            "table": 1,
            "listForm": "Rows",
            "selectionMode": "multiple",
            "enterableInList": True,
            "scrollbarVertical": "visible",
            "borderStyle": "solid",
            "method": "AXBL_Items",
            "events": ["onSelectionChange", "onDataChange", "onDoubleClick"],
        },
        "Note": {
            "type": "input",
            "left": 20,
            "top": 280,
            "width": 650,
            "height": 28,
            "dataSource": "Form.note",
        },
        "Modify": {
            "type": "button",
            "left": 140,
            "top": 330,
            "width": 100,
            "height": 28,
            "text": "Modify",
            "method": "AXBL_Modify",
            "events": ["onClick"],
        },
        "Close": {
            "type": "button",
            "left": 260,
            "top": 330,
            "width": 100,
            "height": 28,
            "text": "Close",
            "action": "cancel",
        },
    }
    if args.selection_mode == "default":
        parent["pages"][1]["objects"]["Items"].pop("selectionMode")
    else:
        parent["pages"][1]["objects"]["Items"]["selectionMode"] = args.selection_mode
    if args.horizontal:
        parent["pages"][1]["objects"]["Items"]["scrollbarHorizontal"] = "visible"
    parent["pages"][1]["objects"]["Inspect"] = {
        "type": "button",
        "left": 500,
        "top": 330,
        "width": 100,
        "height": 28,
        "text": "Inspect",
        "method": "AXBL_Inspect",
        "events": ["onClick"],
    }
    for index, name in enumerate(("Rebind", "Visibility", "Availability", "Ready")):
        parent["pages"][1]["objects"][name] = {
            "type": "button",
            "left": 20 + index * 155,
            "top": 365,
            "width": 145,
            "height": 28,
            "text": name,
            "method": "AXBL_" + name,
            "events": ["onClick"],
        }
    parent["height"] = 415
    (sources / "Forms/Grid/form.4DForm").write_text(json.dumps(parent, indent=2) + "\n")
    rows = sources / "TableForms/1/Rows"
    rows.mkdir(parents=True, exist_ok=True)
    objects = {}
    for name, field, left, width, hint in [
        ("ItemID", "id", 0, 75, "integer"),
        ("ItemName", "name", 80, 300, "text"),
        ("ItemAmount", "amount", 390, 110, "number"),
    ]:
        objects[name] = {
            "type": "input",
            "left": left,
            "top": header,
            "width": width,
            "height": height,
            "dataSource": "[AXBSItem]" + field,
            "dataSourceTypeHint": hint,
            "enterable": field == "name",
            "borderStyle": "none",
            "method": "AXBL_Field",
            "events": [
                "onDataChange",
                "onGettingFocus",
                "onLosingFocus",
                "onBeforeKeystroke",
            ],
        }
    objects["Approved"] = {
        "type": "checkbox",
        "left": 520,
        "top": header,
        "width": 90,
        "height": height,
        "text": "Approved",
        "dataSource": "[AXBSItem]approved",
        "method": "AXBL_Field",
        "events": ["onDataChange", "onClick"],
    }
    if args.multiline:
        objects["ItemName"]["multiline"] = "yes"
    if header:
        for name, text, left, width in [
            ("HeadingID", "ID", 0, 75),
            ("HeadingName", "Description", 80, 300),
            ("HeadingAmount", "Amount", 390, 110),
            ("HeadingApproved", "Approved", 520, 90),
        ]:
            objects[name] = {
                "type": "text",
                "left": left,
                "top": 0,
                "width": width,
                "height": header,
                "text": text,
            }
    (rows / "form.4DForm").write_text(
        json.dumps(
            {
                "destination": "listScreen",
                "method": "AXBL_Rows",
                "events": ["onSelectionChange", "onLoadRecord"],
                "width": 900 if args.horizontal else 650,
                "height": header + height,
                "markerHeader": header,
                "markerBody": header + height,
                "markerBreak": header + height,
                "markerFooter": header + height,
                "pages": [None, {"objects": objects}],
            },
            indent=2,
        )
        + "\n"
    )
    (methods / "AXB_Configure.4dm").write_text(
        '#DECLARE($name : Text) -> $options : Object\n$options:=New object("label"; "Classic list subform"; "controls"; New object("Note"; New object("label"; "Note")))\n'
    )
    if args.diagnostics_test:
        args.configured = True
    if args.text_key:
        args.configured = True
    if args.no_primary_key:
        args.configured = True
        catalog = sources / "catalog.4DCatalog"
        tree = ET.parse(catalog)
        table = tree.find("table")
        table.remove(table.find("primary_key"))
        tree.write(catalog, encoding="unicode")
    if args.configured:
        (methods / "AXB_Configure.4dm").write_text(
            '#DECLARE($name : Text) -> $options : Object\n$options:=New object("label"; "Classic list subform"; "controls"; New object("Note"; New object("label"; "Note")); "grids"; New object("Items"; New object("kind"; "listSubform"; "label"; "Records"; "columns"; New object("ItemID"; New object("label"; "ID"); "ItemName"; New object("label"; "Description"); "ItemAmount"; New object("label"; "Amount")))))\n'
        )
        config_method = methods / "AXB_Configure.4dm"
        config_method.write_text(
            config_method.read_text()
            + "$options.grids.Items.ready:=Formula(Form.gridReady)\n"
        )
    else:
        (methods / "AXB_Configure.4dm").unlink()
    if args.no_primary_key:
        config_method = methods / "AXB_Configure.4dm"
        config_method.write_text(
            config_method.read_text() + '$options.grids.Items.keyProperty:="id"\n'
        )
    if args.text_key:
        config_method = methods / "AXB_Configure.4dm"
        config_method.write_text(
            config_method.read_text() + '$options.grids.Items.keyProperty:="name"\n'
        )
    (methods / "AXBL_Inspect.4dm").write_text(
        "Form.inspections:=Form.inspections+1\nForm.privateRead:=Null\n"
    )
    (methods / "AXBL_Rebind.4dm").write_text(
        'var $reply : Object\nEXECUTE METHOD IN SUBFORM("Items"; "AXBL_ChangeField"; $reply)\nForm.rebound:=True\n'
    )
    (methods / "AXBL_ChangeField.4dm").write_text(
        '#DECLARE() -> $reply : Object\nOBJECT SET DATA SOURCE(*; "ItemName"; ->[AXBSItem]amount)\n$reply:=New object("ok"; True)\n'
    )
    (methods / "AXBL_Visibility.4dm").write_text(
        'Form.listVisible:=Not(Form.listVisible)\nOBJECT SET VISIBLE(*; "Items"; Form.listVisible)\n'
    )
    (methods / "AXBL_Availability.4dm").write_text(
        'Form.listEnabled:=Not(Form.listEnabled)\nOBJECT SET ENABLED(*; "Items"; Form.listEnabled)\n'
    )
    (methods / "AXBL_Ready.4dm").write_text("Form.gridReady:=Not(Form.gridReady)\n")
    (methods / "AXBL_Items.4dm").write_text(
        'AXBL_Events.push(New object("object"; OBJECT Get name(Object current); "event"; Form event code; "form"; Current form name; "record"; Record number([AXBSItem])))\n'
    )
    (methods / "AXBL_Rows.4dm").write_text((methods / "AXBL_Items.4dm").read_text())
    (methods / "AXBL_Field.4dm").write_text(
        (methods / "AXBL_Items.4dm").read_text()
        + 'If ((Form event code=On Before Keystroke) & (Character code(Keystroke)=120))\n FILTER KEYSTROKE("")\nEnd if\n'
    )
    (methods / "AXBL_Modify.4dm").write_text(
        'GOTO SELECTED RECORD([AXBSItem]; 2)\n[AXBSItem]name:="Unsaved buffer"\nFile("/RESOURCES/modified-buffer.json").setText(JSON Stringify(AXBL_Buffer))\nForm.privateRead:=Null\n'
    )
    (methods / "AXBL_Buffer.4dm").write_text("""#DECLARE() -> $result : Object
    ARRAY LONGINT($records; 0)
    var $selection : Collection
    LONGINT ARRAY FROM SELECTION([AXBSItem]; $records)
    $selection:=New collection
    ARRAY TO COLLECTION($selection; $records)
    $result:=New object("loaded"; Is record loaded([AXBSItem]); "record"; Record number([AXBSItem]); "position"; Selected record number([AXBSItem]); "count"; Records in selection([AXBSItem]); "modified"; Modified record([AXBSItem]); "selection"; Generate digest(JSON Stringify($selection); SHA256 digest))
    If ($result.loaded)
     $result.id:=[AXBSItem]id
     $result.name:=[AXBSItem]name
    End if
    """)
    (methods / "AXBL_Inside.4dm").write_text("""#DECLARE() -> $result : Object
    ARRAY TEXT($objects; 0)
    ARRAY POINTER($variables; 0)
    ARRAY LONGINT($pages; 0)
    var $names; $columns : Collection
    var $i; $left; $top; $right; $bottom; $x; $y; $tableNumber; $fieldNumber; $containerWidth; $containerHeight : Integer
    var $variable : Text
    FORM GET OBJECTS($objects; $variables; $pages; Form current page+Form inherited)
    $names:=New collection
    ARRAY TO COLLECTION($names; $objects)
    $result:=New object("formName"; Current form name; "formTable"; Current form table; "dataType"; Value type(Form); "objects"; $names; "buffer"; AXBL_Buffer)
    $columns:=New collection
    For ($i; 1; Size of array($objects))
     $tableNumber:=0
     $fieldNumber:=0
     $variable:=""
     If (Not(Is nil pointer($variables{$i})))
      RESOLVE POINTER($variables{$i}; $variable; $tableNumber; $fieldNumber)
     End if
     OBJECT GET COORDINATES(*; $objects{$i}; $left; $top; $right; $bottom)
     $columns.push(New object("name"; $objects{$i}; "table"; $tableNumber; "field"; $fieldNumber; "variable"; $variable; "frame"; New collection($left; $top; $right-$left; $bottom-$top)))
    End for
    $result.columns:=$columns
    $x:=0
    $y:=0
    CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
    $result.origin:=New collection($x; $y)
    OBJECT GET SUBFORM CONTAINER SIZE($containerWidth; $containerHeight)
    $result.container:=New collection($containerWidth; $containerHeight)
    If (Find in array($objects; "ItemName")>0)
     $result.name:=OBJECT Get value("ItemName")
    End if
    """)
    (methods / "AXBS_Form.4dm").write_text("""Case of
     : (Form event code=On Load)
      SET TIMER(6)
      Form.baselineTick:=0
     : (Form event code=On Timer)
      Form.baselineTick:=Form.baselineTick+1
      If (Form.config.autoModify & (Form.baselineTick=3))
       GOTO SELECTED RECORD([AXBSItem]; 2)
       [AXBSItem]name:="Unsaved buffer"
       File("/RESOURCES/modified-buffer.json").setText(JSON Stringify(AXBL_Buffer))
       Form.privateRead:=Null
      End if
      If (File("/RESOURCES/close.json").exists)
       CANCEL
      End if
      AXBS_State
    End case
    """)
    (methods / "AXBS_State.4dm").write_text(
        """var $state; $inside; $before; $after; $context : Object
    var $table : Pointer
    var $detail; $list : Text
    var $scroll; $savedOK : Integer
    var $pending : Object
    var $source : Collection
    var $dataClass : Object
    var $primaryKey : Text
    var $horizontal; $vertical : Boolean
    var $records; $names : Collection
    var $highlightedCount : Integer
    ARRAY LONGINT($recordNumbers; 0)
    $savedOK:=OK
    $before:=AXBL_Buffer
    $inside:=Null
    EXECUTE METHOD IN SUBFORM("Items"; "AXBL_Inside"; $inside)
    $after:=AXBL_Buffer
    OBJECT GET SUBFORM(*; "Items"; $table; $detail; $list)
    OBJECT GET SCROLL POSITION(*; "Items"; $scroll)
    OBJECT GET SCROLLBAR(*; "Items"; $horizontal; $vertical)
    $pending:=Form.privateRead
    If ($pending=Null)
     LONGINT ARRAY FROM SELECTION($table->; $recordNumbers)
     $records:=New collection
     ARRAY TO COLLECTION($records; $recordNumbers)
     $pending:=New shared object("done"; False; "table"; Table($table); "records"; $records.copy(ck shared); "highlight"; "")
     Form.privateRead:=$pending
     $scroll:=New process("AXBL_Stored"; 0; "AXB list probe read"; $pending)
     OBJECT GET SCROLL POSITION(*; "Items"; $scroll)
    End if
    GET HIGHLIGHTED RECORDS([AXBSItem]; "AXBL_CurrentHighlight")
     $highlightedCount:=Records in set("AXBL_CurrentHighlight")
    CLEAR SET("AXBL_CurrentHighlight")
    $primaryKey:=""
    If (OB Keys(ds).indexOf("AXBSItem")>=0)
     $dataClass:=ds["AXBSItem"]
     $primaryKey:=$dataClass.getInfo().primaryKey
    End if
    $state:=New object("primaryKey"; $primaryKey; "tick"; Form.baselineTick; "inspections"; Form.inspections; "highlightedCount"; $highlightedCount; "compiled"; Is compiled mode; "before"; $before; "after"; $after; "inside"; $inside; "listForm"; $list; "detailForm"; $detail; "scroll"; $scroll; "events"; AXBL_Events)
    $state.scrollbars:=New collection($horizontal; $vertical)
    If ($pending.done=True)
     $source:=$pending.source
     $names:=$source.extract("name"; ck keep null)
     $state.privateRead:=New object("done"; True; "error"; $pending.error; "count"; $source.length; "first"; $names[0]; "second"; $names[1]; "last"; $names[$names.length-1]; "approved"; $source[$source.length-1].approved)
    End if
    $context:=AXB_FormContext
    $state.area:=AXB_Area("diagnostics"; ""; "")
    $state.dependencies:=AXB_Host("info"; New object)
    $state.rebound:=Form.rebound
    $state.listVisible:=Form.listVisible
    $state.listEnabled:=Form.listEnabled
    $state.gridReady:=Form.gridReady
    If ($context#Null)
     $state.diagnostics:=$context.diagnostics
     $state.receipt:=$context.receipt
     $state.pending:=$context.pending
     $state.grid:=$context.view.grids.Items.descriptor
    End if
    If (Not(Is nil pointer($table)))
     $state.table:=Table($table)
    End if
    File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
    OK:=$savedOK
    """
    )
    (methods / "AXBL_Stored.4dm").write_text("""#DECLARE($reply : Object)
var $source : Collection
var $row : Integer
ARRAY LONGINT($records; 0)
READ ONLY([AXBSItem])
COLLECTION TO ARRAY($reply.records; $records)
CREATE SELECTION FROM ARRAY([AXBSItem]; $records)
$source:=New shared collection
For ($row; 1; Records in selection([AXBSItem]))
 GOTO SELECTED RECORD([AXBSItem]; $row)
 Use ($source)
  $source.push(New shared object("id"; [AXBSItem]id; "name"; [AXBSItem]name; "amount"; [AXBSItem]amount; "approved"; [AXBSItem]approved))
 End use
End for
Use ($reply)
 $reply.source:=$source.copy(ck shared; $reply)
 $reply.done:=True
End use
""")
    startup = sources / "DatabaseMethods/onStartup.4dm"
    s = startup.read_text()
    seed_start = s.index("If (ds.AXBSItem.all().length=0)")
    seed_end = s.index("ALL RECORDS([AXBSItem])", seed_start)
    s = s[:seed_start] + """If (Records in table([AXBSItem])=0)
 For ($i; 1; 600)
  CREATE RECORD([AXBSItem])
  [AXBSItem]id:=$i
  [AXBSItem]name:="Record "+String($i; "0000")
  [AXBSItem]amount:=$i+0.25
  [AXBSItem]approved:=False
  SAVE RECORD([AXBSItem])
 End for
End if
""" + s[seed_end:]
    s = s.replace("AXBL_Events:=New collection\n", "").replace(
        "$window:=Open form window",
        "AXBL_Events:=New collection\n$data.inspections:=0\n$data.listVisible:=True\n$data.listEnabled:=True\n$data.gridReady:=True\n$data.rebound:=False\n$window:=Open form window",
    )
    parent_path = sources / "Forms/Grid/form.4DForm"
    install_name = "Grid"
    if args.table_parent:
        catalog = sources / "catalog.4DCatalog"
        tree = ET.parse(catalog)
        table = ET.SubElement(
            tree.getroot(),
            "table",
            name="AXBLParent",
            uuid=uuid.uuid4().hex.upper(),
            id="2",
        )
        key = uuid.uuid4().hex.upper()
        ET.SubElement(
            table,
            "field",
            name="id",
            uuid=key,
            type="4",
            unique="true",
            never_null="true",
            id="1",
        )
        ET.SubElement(table, "primary_key", field_name="id", field_uuid=key)
        tree.write(catalog, encoding="unicode")
        destination = sources / "TableForms/2/Grid"
        destination.mkdir(parents=True)
        parent_path.rename(destination / parent_path.name)
        parent_path.parent.rmdir()
        parent_path = destination / "form.4DForm"
        install_name = "TableForms/2/Grid"
        s = s.replace(
            '$window:=Open form window("Grid"; Plain form window)',
            'CREATE RECORD([AXBLParent])\n[AXBLParent]id:=1\n$window:=Open form window([AXBLParent]; "Grid"; Plain form window)',
        ).replace('DIALOG("Grid"; $data)', 'DIALOG([AXBLParent]; "Grid"; $data)')
    startup.write_text(s)
    compiler = methods / "Compiler_AXBS.4dm"
    s = compiler.read_text().replace("C_REAL(AXBS_List)\n", "")
    s = (
        s[: s.index("C_COLLECTION(AXBL_Events)")]
        if "C_COLLECTION(AXBL_Events)" in s
        else s
    )
    compiler.write_text(
        s
        + "C_COLLECTION(AXBL_Events)\nC_OBJECT(AXBL_Buffer; $0)\nC_OBJECT(AXBL_Inside; $0)\nC_OBJECT(AXBL_Stored; $1)\nC_OBJECT(AXBL_ChangeField; $0)\n"
    )
    if not args.configured:
        compiler.write_text(
            "\n".join(
                line
                for line in compiler.read_text().splitlines()
                if "(AXB_Configure;" not in line
            )
            + "\n"
        )
    server = args.server.expanduser().resolve()
    from install_host_methods import main as install_host

    install_host(["--project-dir", str(fixture / "Project"), "--form", install_name])
    if args.no_area:
        form_path = parent_path
        definition = json.loads(form_path.read_text())
        definition["pages"][0]["objects"].pop("__AXB_Bridge")
        form_path.write_text(json.dumps(definition, indent=2) + "\n")
    config_path = fixture / "Resources/launch.json"
    config = json.loads(config_path.read_text())
    config.update(autoModify=args.auto_modify, noArea=args.no_area)
    config_path.write_text(json.dumps(config) + "\n")
    before = {
        str(p.relative_to(fixture)): sha(p) for p in sources.rglob("*") if p.is_file()
    }
    metadata = fixture / "Resources/AXB.FormMetadata.json"
    if args.diagnostics_test:
        config_method = methods / "AXB_Configure.4dm"
        config_method.write_text(config_method.read_text() + '$options.grids.Items.keyProperty:="missingStoredKey"\n')
        data = json.loads(metadata.read_text())
        table_key = "2" if args.table_parent else "0"
        data["forms"][table_key]["Grid"]["lists"].pop("Items")
        metadata.write_text(json.dumps(data) + "\n")
        before = {str(p.relative_to(fixture)): sha(p) for p in sources.rglob("*") if p.is_file()}

    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="list-subform-compile-", dir=BUILD) as t:
        driver = Path(t)
        project_at(driver, "Driver")
        result = run_utility(
            server / "Contents/MacOS" / info["CFBundleExecutable"],
            driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            + f'$options.plugins:=Folder({literal(fixture/"Plugins")})\n'
            + f'$options.components:=New collection(File({literal(fixture/"Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            + f'$result:=Compile project(File({literal(fixture/"Project/Selection.4DProject")}); $options)',
            90,
        )
    report = {
        "passed": result.get("success") is True and not result.get("errors"),
        "compiler": result,
        "preparer_sha256": sha(root / "prepare_list_subform_fixture.py"),
        "sources_sha256": before,
        "catalog_semantic_sha256": hashlib.sha256(
            ET.canonicalize(
                (sources / "catalog.4DCatalog").read_text(), strip_text=True
            ).encode()
        ).hexdigest(),
        "metadata_sha256": sha(metadata),
        "native_sha256": sha(
            fixture
            / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
        ),
        "component_sha256": sha(
            fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"
        ),
        "diagnosticsTest": args.diagnostics_test,
        "noPrimaryKey": args.no_primary_key,
        "tableParent": args.table_parent,
        "textKey": args.text_key,
        "horizontal": args.horizontal,
        "noArea": args.no_area,
        "autoModify": args.auto_modify,
        "configured": args.configured,
        "selectionMode": args.selection_mode,
        "header": header,
        "rowHeight": height,
    }
    (BUILD / "list-subform-compile-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(
        ("PASS" if report["passed"] else "FAIL") + ": classic list subform compilation"
    )
    if not report["passed"]:
        print(json.dumps(result, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
