#!/usr/bin/env python3
"""Compile an area-owned classic current/named-selection grid fixture."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET
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

FIXTURE = BUILD / "selection-fixture"
TITLE = "AX bridge classic selection"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--named", action="store_true")
    parser.add_argument("--no-bridge", action="store_true")
    args = parser.parse_args()
    for name in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential fixture preparation")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("selection-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Selection")
    sources = project.parent / "Sources"
    methods = sources / "Methods"
    table_id, key_id = uuid.uuid4().hex.upper(), uuid.uuid4().hex.upper()
    fields = "".join(
        f'<field name="{name}" uuid="{key_id if number == 1 else uuid.uuid4().hex.upper()}" type="{kind}" id="{number}"'
        + (' unique="true" never_null="true"' if number == 1 else "")
        + "/>"
        for number, name, kind in [
            (1, "id", 4),
            (2, "name", 10),
            (3, "amount", 6),
            (4, "approved", 1),
        ]
    )
    (sources / "catalog.4DCatalog").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n'
        + f'<base name="Selection" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en"><schema name="DEFAULT_SCHEMA"/><table name="AXBSItem" uuid="{table_id}" id="1">{fields}<primary_key field_name="id" field_uuid="{key_id}"/></table><index kind="regular" unique_keys="true" name="AXBS_PK" uuid="{uuid.uuid4().hex.upper()}" type="7"><field_ref uuid="{key_id}" name="id"><table_ref uuid="{table_id}" name="AXBSItem"/></field_ref></index></base>\n'
    )
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text("""var $i; $window : Integer
var $item; $saved; $data; $config : Object
ON ERR CALL("AXBS_Error")
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
If (ds.AXBSItem.all().length=0)
 For ($i; 1; 600)
  $item:=ds.AXBSItem.new()
  $item.id:=$i
  $item.name:="Record "+String($i; "0000")
  $item.amount:=$i+0.25
  $item.approved:=False
  $saved:=$item.save()
  If (Not($saved.success))
   File("/RESOURCES/errors.json").setText(JSON Stringify($saved))
   QUIT 4D
   return
  End if
 End for
End if
ALL RECORDS([AXBSItem])
ORDER BY([AXBSItem]; [AXBSItem]id; >)
If ($config.named)
 ORDER BY([AXBSItem]; [AXBSItem]id; <)
 COPY NAMED SELECTION([AXBSItem]; "AXBS_Source")
 ORDER BY([AXBSItem]; [AXBSItem]id; >)
End if
$data:=New object("config"; $config; "events"; New collection; "buttons"; New collection; "changes"; 0; "hooks"; 0; "note"; "Ordinary editor")
$window:=Open form window("Grid"; Plain form window)
DIALOG("Grid"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $config.runId; "accepted"; OK=1)))
CLOSE WINDOW($window)
QUIT 4D
""")
    (methods / "AXBS_Error.4dm").write_text(
        'File("/RESOURCES/errors.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
    )
    (methods / "AXBS_Form.4dm").write_text("""Case of
 : (Form event code=On Load)
  SET TIMER(6)
 : (Form event code=On Timer)
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
  AXBS_State
End case
""")
    (methods / "AXBS_Selected.4dm").write_text("Form.hooks:=Form.hooks+1\nAXBS_State\n")
    (
        methods / "AXBS_Column.4dm"
    ).write_text("""Form.events.push(New object("object"; OBJECT Get name(Object current); "event"; Form event code))
If (Form event code=On Data Change)
 Form.changes:=Form.changes+1
End if
If (Form event code=On Before Keystroke)
 If (Keystroke="x")
  FILTER KEYSTROKE("")
 End if
End if
""")
    (methods / "AXBS_Click.4dm").write_text("""var $table : Pointer
var $name : Text
$name:=OBJECT Get name(Object current)
Form.buttons.push($name)
Case of
 : ($name="Sort")
  If (Form.config.named)
   ORDER BY([AXBSItem]; [AXBSItem]id; >)
   COPY NAMED SELECTION([AXBSItem]; "AXBS_Source")
  Else
   ORDER BY([AXBSItem]; [AXBSItem]id; <)
  End if
 : ($name="Hide")
  OBJECT SET VISIBLE(*; "Items"; Not(OBJECT Get visible(*; "Items")))
 : ($name="Modify")
  GOTO SELECTED RECORD([AXBSItem]; 2)
  [AXBSItem]name:="Unsaved buffer"
 : ($name="Unload")
  UNLOAD RECORD([AXBSItem])
 : ($name="New")
  CREATE RECORD([AXBSItem])
  [AXBSItem]id:=999
  [AXBSItem]name:="Unsaved new buffer"
End case
AXBS_State
""")
    (methods / "AXBS_State.4dm").write_text("""var $state; $context; $item : Object
var $column; $row; $tableNumber; $fieldNumber; $sourceTable : Integer
var $pointer : Pointer
var $variable; $expression; $sourceName; $highlightName : Text
$state:=New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "hooks"; Form.hooks; "events"; Form.events; "buttons"; Form.buttons; "changes"; Form.changes; "note"; Form.note)
$state.record:=New object("loaded"; Is record loaded([AXBSItem]); "record"; Record number([AXBSItem]); "position"; Selected record number([AXBSItem]); "count"; Records in selection([AXBSItem]); "modified"; Modified record([AXBSItem]))
If ($state.record.loaded)
 $state.record.id:=[AXBSItem]id
 $state.record.name:=[AXBSItem]name
End if
$state.gridVisible:=OBJECT Get visible(*; "Items")
$state.selectedCount:=Records in set("AXBS_Highlight")
LISTBOX GET TABLE SOURCE(*; "Items"; $sourceTable; $sourceName; $highlightName)
$state.selectionMeta:=New collection($sourceTable; $sourceName; $highlightName; LISTBOX Get property(*; "Items"; lk selection mode))
LISTBOX GET CELL POSITION(*; "Items"; $column; $row)
$state.cell:=New collection($column; $row)
$state.edited:=""
If (Is editing text)
 $state.edited:=Get edited text
End if
$pointer:=OBJECT Get pointer(Object named; "ItemName")
If (Not(Is nil pointer($pointer)))
 RESOLVE POINTER($pointer; $variable; $tableNumber; $fieldNumber)
End if
$state.columnPointer:=New collection($tableNumber; $fieldNumber; $variable)
$item:=ds.AXBSItem.get(600)
$item.reload()
$state.farValue:=$item.name
$state.farChecked:=$item.approved
$item:=ds.AXBSItem.get(Choose(Form.config.named; 1; 600))
$item.reload()
$state.edgeChecked:=$item.approved
$context:=AXB_FormContext
$state.areas:=AXB_Area("diagnostics"; ""; "")
$state.dependencies:=AXB_Host("info"; New object)
If ($context#Null)
 $state.diagnostics:=$context.diagnostics
 $state.receipt:=$context.receipt
 $state.workerError:=$context.view.grids.Items.selectionError
End if
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
""")
    if args.no_bridge:
        p = methods / "AXBS_State.4dm"
        s = p.read_text()
        start = s.index("$context:=AXB_FormContext")
        end = s.index('File("/RESOURCES/runtime-status.json")', start)
        p.write_text(s[:start] + s[end:])
    else:
        shutil.copytree(
            BUILD / "AccessibilityBridge.bundle",
            FIXTURE / "Plugins/AccessibilityBridge.bundle",
        )
        shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
        subprocess.run(
            [
                "python3",
                str(ROOT / "install_host_methods.py"),
                "--project-dir",
                str(project.parent),
            ],
            check=True,
            capture_output=True,
        )
        (methods / "AXB_Configure.4dm").write_text(
            '#DECLARE($name : Text) -> $options : Object\n$options:=New object("label"; "Classic selection"; "controls"; New object("Note"; New object("label"; "Note")); "grids"; New object("Items"; New object("kind"; "selection"; "label"; "Records"; "onSelection"; Formula(AXBS_Selected))))\n'
        )
    (methods / "Compiler_AXBS.4dm").write_text(
        "C_REAL(AXBS_List)\n"
        + (
            ""
            if args.no_bridge
            else "C_TEXT(AXB_Configure; $1)\nC_OBJECT(AXB_Configure; $0)\n"
        )
    )
    objects = {
        "Items": {
            "type": "listbox",
            "left": 20,
            "top": 20,
            "width": 650,
            "height": 240,
            "dataSource": "AXBS_List",
            "listboxType": "namedSelection" if args.named else "currentSelection",
            "table": 1,
            "highlightSet": "AXBS_Highlight",
            "rowHeight": "24px",
            "headerHeight": "22px",
            "showHeaders": True,
            "selectionMode": "multiple",
            "scrollbarVertical": "always",
            "scrollbarHorizontal": "always",
            "sortable": True,
            "columns": [],
        },
        "Note": {
            "type": "input",
            "left": 20,
            "top": 280,
            "width": 650,
            "height": 28,
            "dataSource": "Form.note",
        },
    }
    if args.named:
        objects["Items"].pop("table")
        objects["Items"]["selectionName"] = "AXBS_Source"
    for name, field, label, width, hint, editable in [
        ("ItemID", "id", "ID", 75, "integer", False),
        ("ItemName", "name", "Description", 300, "text", True),
        ("ItemAmount", "amount", "Amount", 120, "number", False),
        ("Approved", "approved", "Approved", 130, "boolean", True),
    ]:
        obj = {
            "name": name,
            "dataSource": "[AXBSItem]" + field,
            "dataSourceTypeHint": hint,
            "width": width,
            "enterable": editable,
            "header": {"name": name + "Header", "text": label},
        }
        if editable:
            obj.update(
                method="AXBS_Column",
                events=[
                    "onBeforeDataEntry",
                    "onBeforeKeystroke",
                    "onDataChange",
                    "onAfterEdit",
                ],
            )
        if name == "Approved":
            obj.update(controlType="checkbox", controlTitle="Approved")
        objects["Items"]["columns"].append(obj)
    for index, name in enumerate(["Sort", "Modify", "Unload", "New", "Hide", "Close"]):
        objects[name] = {
            "type": "button",
            "text": name,
            "left": 20 + index * 108,
            "top": 330,
            "width": 100,
            "height": 28,
        }
        if name == "Close":
            objects[name]["action"] = "cancel"
        else:
            objects[name].update(method="AXBS_Click", events=["onClick"])
    form = {
        "windowTitle": TITLE,
        "width": 690,
        "height": 385,
        "method": "AXBS_Form",
        "events": ["onLoad", "onTimer"],
        "pages": [None, {"objects": objects}],
    }
    if not args.no_bridge:
        from install_host_methods import area_form

        form = area_form(form)
    folder = sources / "Forms/Grid"
    folder.mkdir(parents=True)
    (folder / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    (FIXTURE / "Resources/launch.json").write_text(
        json.dumps(
            {
                "runId": uuid.uuid4().hex,
                "named": args.named,
                "bridge": not args.no_bridge,
            }
        )
        + "\n"
    )
    startup = (database / "onStartup.4dm").read_text()
    seed = startup[
        startup.index("If (ds.AXBSItem.all().length=0)") : startup.index(
            "ALL RECORDS([AXBSItem])"
        )
    ]
    (methods / "AXBS_Seed.4dm").write_text(
        'var $i : Integer\nvar $item; $saved : Object\nON ERR CALL("AXBS_Error")\n'
        + seed
        + 'File("/RESOURCES/seed.json").setText(JSON Stringify(New object("passed"; ds.AXBSItem.all().length=600)))\nQUIT 4D\n'
    )
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with (FIXTURE / "seed.log").open("w") as log:
        seeded = subprocess.run(
            [
                str(server / "Contents/MacOS" / info["CFBundleExecutable"]),
                "--project",
                str(project),
                "--data",
                str(FIXTURE / "synthetic.4dd"),
                "--create-data",
                "--headless",
                "--utility",
                "--skip-onstartup",
                "--startup-method",
                "AXBS_Seed",
                "--webadmin-auto-start",
                "false",
            ],
            stdout=log,
            stderr=log,
            timeout=90,
        )
    assert (
        seeded.returncode == 0
        and json.loads(
            (FIXTURE / "Resources/seed.json").read_text(encoding="utf-8-sig")
        )["passed"]
    )
    catalog = sources / "catalog.4DCatalog"
    (FIXTURE / "Resources/catalog-before.txt").write_text(catalog.read_text())
    before = {
        str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()
    }
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(
        prefix="selection-compile-", dir=BUILD
    ) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(
            server / "Contents/MacOS" / info["CFBundleExecutable"],
            driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            + f"$options.plugins:=Folder({literal(FIXTURE / 'Plugins')})\n"
            + (
                "$options.components:=New collection\n"
                if args.no_bridge
                else f"$options.components:=New collection(File({literal(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')}))\n"
            )
            + f"$result:=Compile project(File({literal(project)}); $options)",
            90,
        )
    report = {
        "preparer_sha256": sha(ROOT / "prepare_selection_fixture.py"),
        "passed": compiled.get("success") is True and not compiled.get("errors"),
        "compiler": compiled,
        "sources_sha256": before,
        "catalog_semantic_sha256": hashlib.sha256(
            ET.canonicalize(
                (sources / "catalog.4DCatalog").read_text(), strip_text=True
            ).encode()
        ).hexdigest(),
        "native_sha256": None
        if args.no_bridge
        else sha(
            FIXTURE
            / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
        ),
        "component_sha256": None
        if args.no_bridge
        else sha(
            FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"
        ),
    }
    (BUILD / "selection-compile-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(("PASS" if report["passed"] else "FAIL") + ": classic selection compilation")
    if not report["passed"]:
        print(json.dumps(compiled, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
