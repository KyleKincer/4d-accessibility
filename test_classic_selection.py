#!/usr/bin/env python3
"""Check candidate classic-selection reads against unsaved 4D record state."""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, ROOT, literal, project_at, run_utility, sha


BODY = """var $i : Integer
var $entity; $saved; $before; $after; $case; $worker : Object
var $started : Real
var $process : Integer
var $read; $mode; $json : Text
var $values : Collection
var $setName : Text
var $entities : 4D.EntitySelection
ARRAY LONGINT($records; 0)
ARRAY LONGINT($ids; 0)
ARRAY TEXT($names; 0)
$result:=New object("cases"; New collection; "compiled"; Is compiled mode)
If (ds.AXBCRecord.all().length=0)
 For ($i; 1; 5)
  $entity:=ds.AXBCRecord.new()
  $entity.id:=$i
  $entity.name:="Saved "+String($i)
  $saved:=$entity.save()
  If (Not($saved.success))
   $result.error:=$saved
   return
  End if
 End for
End if
For each ($read; New collection("recordNumbers"; "namedRecordNumbers"; "rangeRecordNumbers"; "rangeFields"; "entitySelection"; "entityValues"; "selectionFields"; "selectionJSON"; "workerEntities"; "workerValues"; "workerHighlight"; "workerFailure"))
 For each ($mode; New collection("saved"; "modified"; "unloaded"; "new"))
  UNLOAD RECORD([AXBCRecord])
  QUERY([AXBCRecord]; [AXBCRecord]id>=4)
  ORDER BY([AXBCRecord]; [AXBCRecord]id; <)
  COPY NAMED SELECTION([AXBCRecord]; "AXBC_Named")
  ALL RECORDS([AXBCRecord])
  ORDER BY([AXBCRecord]; [AXBCRecord]id; >)
  LONGINT ARRAY FROM SELECTION([AXBCRecord]; $records)
  ARRAY LONGINT($ids; 2)
  $ids{1}:=$records{1}
  $ids{2}:=$records{5}
  CREATE SET FROM ARRAY([AXBCRecord]; $ids; "AXBC_Highlight")
  GOTO SELECTED RECORD([AXBCRecord]; 2)
  Case of
   : ($mode="modified")
    [AXBCRecord]name:="Unsaved editor value"
   : ($mode="unloaded")
    UNLOAD RECORD([AXBCRecord])
   : ($mode="new")
    CREATE RECORD([AXBCRecord])
    [AXBCRecord]id:=99
    [AXBCRecord]name:="Unsaved new value"
  End case
  $before:=AXBC_Snapshot
  OK:=0
  $values:=New collection
  Case of
   : ($read="recordNumbers")
    LONGINT ARRAY FROM SELECTION([AXBCRecord]; $records)
    ARRAY TO COLLECTION($values; $records)
   : ($read="namedRecordNumbers")
    LONGINT ARRAY FROM SELECTION([AXBCRecord]; $records; "AXBC_Named")
    ARRAY TO COLLECTION($values; $records)
   : ($read="rangeRecordNumbers")
    SELECTION RANGE TO ARRAY(2; 4; [AXBCRecord]; $records)
    ARRAY TO COLLECTION($values; $records)
   : ($read="rangeFields")
    SELECTION RANGE TO ARRAY(2; 4; [AXBCRecord]id; $ids; [AXBCRecord]name; $names)
    ARRAY TO COLLECTION($values; $names)
   : ($read="entitySelection")
    $entities:=Create entity selection([AXBCRecord])
    $values.push($entities.length)
   : ($read="entityValues")
    $entities:=Create entity selection([AXBCRecord])
    $values:=$entities.extract("name")
   : (Position("worker"; $read)=1)
    LONGINT ARRAY FROM SELECTION([AXBCRecord]; $records; "AXBC_Named")
    ARRAY TO COLLECTION($values; $records)
    $setName:="<>AXBC_"+Generate UUID
    If ($read="workerFailure")
     $values:=New collection(2147483647)
    End if
    $worker:=New shared object("done"; False; "table"; 1; "records"; $values.copy(ck shared); "highlight"; $setName)
    COPY SET("AXBC_Highlight"; $worker.highlight)
    $process:=New process("AXB_SelectionRead"; 0; "AXBC isolated read"; $worker)
    $started:=Milliseconds
    While (Not($worker.done) & ((Milliseconds-$started)<5000))
     DELAY PROCESS(Current process; 1)
    End while
    If (Not($worker.done))
     $result.error:="Isolated selection resolution timed out"
     return
    End if
    If (($read#"workerFailure") & ($worker.error#Null))
     $result.error:=$worker.error
     return
    End if
    $entities:=$worker.source
    If ($read="workerFailure")
     $values:=New collection(($worker.error#Null) & ($worker.highlight="") & ($worker.source=Null))
    Else
     If ($read="workerEntities")
      $values:=New collection($entities.length)
     Else
      If ($read="workerValues")
       $values:=$entities.extract("name")
      Else
       $values:=New collection
       LONGINT ARRAY FROM SELECTION([AXBCRecord]; $records)
       For ($i; 1; Size of array($records))
        If ($worker.selected[String($records{$i})]=True)
         $values.push($records{$i})
        End if
       End for
      End if
     End if
    End if
   : ($read="selectionFields")
    SELECTION TO ARRAY([AXBCRecord]id; $ids; [AXBCRecord]name; $names)
    ARRAY TO COLLECTION($values; $names)
   : ($read="selectionJSON")
    $json:=Selection to JSON([AXBCRecord])
    $values:=JSON Parse($json)
  End case
  $after:=AXBC_Snapshot
  $case:=New object("read"; $read; "mode"; $mode; "before"; $before; "after"; $after; "values"; $values; "okPreserved"; OK=0)
  $result.cases.push($case)
  CLEAR NAMED SELECTION("AXBC_Named")
  CLEAR SET("AXBC_Highlight")
 End for each
End for each
UNLOAD RECORD([AXBCRecord])
$result.savedNames:=ds.AXBCRecord.all().orderBy("id asc").extract("name")
"""

SNAPSHOT = """#DECLARE() -> $state : Object
$state:=New object("loaded"; Is record loaded([AXBCRecord]); "record"; Record number([AXBCRecord]); "selectedRecord"; Selected record number([AXBCRecord]); "selectionCount"; Records in selection([AXBCRecord]); "modified"; Modified record([AXBCRecord]))
If ($state.loaded)
 $state.id:=[AXBCRecord]id
 $state.name:=[AXBCRecord]name
End if
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run:
        parser.error("--run is required for sequential 4D command tests")
    for name in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential utility test")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must name a licensed 4D Server application")
    executable = server / "Contents/MacOS" / info["CFBundleExecutable"]
    BUILD.mkdir(exist_ok=True)
    driver = BUILD / ("classic-selection-" + uuid.uuid4().hex)
    driver.mkdir()
    project = project_at(driver, "Driver")
    table_id, primary_id = uuid.uuid4().hex.upper(), uuid.uuid4().hex.upper()
    catalog = driver / "Project/Sources/catalog.4DCatalog"
    catalog.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n'
        f'<base name="ClassicSelection" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en"><schema name="DEFAULT_SCHEMA"/>'
        f'<table name="AXBCRecord" uuid="{table_id}" id="1">'
        f'<field name="id" uuid="{primary_id}" type="4" unique="true" never_null="true" id="1"/>'
        f'<field name="name" uuid="{uuid.uuid4().hex.upper()}" type="10" id="2"/>'
        f'<primary_key field_name="id" field_uuid="{primary_id}"/></table>'
        f'<index kind="regular" unique_keys="true" name="AXBC_PK" uuid="{uuid.uuid4().hex.upper()}" type="7">'
        f'<field_ref uuid="{primary_id}" name="id"><table_ref uuid="{table_id}" name="AXBCRecord"/></field_ref></index></base>\n'
    )
    methods = driver / "Project/Sources/Methods"
    (methods / "AXBC_Snapshot.4dm").write_text(SNAPSHOT)
    for name in ("AXB_SelectionRead", "AXB_SelectionError"):
        shutil.copy2(
            ROOT / "host/OptionalMethods" / (name + ".4dm"), methods / (name + ".4dm")
        )
    (methods / "Compiler_AXBC.4dm").write_text(
        "C_OBJECT(AXBC_Snapshot; $0)\nC_OBJECT(AXB_SelectionRead; $1)\nC_OBJECT(AXB_SelectionWorkerReply)\n"
    )
    (methods / "AXBC_Run.4dm").write_text(
        'var $result : Object\nON ERR CALL("AXBC_Error")\n'
        + BODY
        + '\nFile("/RESOURCES/result.json").setText(JSON Stringify($result; *))\nQUIT 4D\n'
    )
    (methods / "AXBC_Error.4dm").write_text(
        'File("/RESOURCES/result.json").setText(JSON Stringify(New object("success"; False; "error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
    )
    with tempfile.TemporaryDirectory(
        prefix="classic-selection-compile-", dir=BUILD
    ) as temporary:
        compiler = Path(temporary)
        project_at(compiler, "Driver")
        compiled = run_utility(
            executable,
            compiler,
            "$result:=Compile project(File("
            + literal(project)
            + '); New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none"))',
            90,
        )
    assert compiled.get("success") and not compiled.get("errors"), compiled
    results = []
    for mode in ("interpreted", "compiled"):
        with (driver / (mode + ".log")).open("w") as log:
            # Named selections require the normal application process context;
            # the 4D Server utility process is not a desktop host equivalent.
            subprocess.run(
                [
                    "/usr/bin/arch",
                    "-arm64",
                    "/Applications/4D/4D.app/Contents/MacOS/4D",
                    "--project",
                    str(project),
                    "--data",
                    str(driver / "synthetic.4dd"),
                    "--create-data",
                    "--opening-mode",
                    mode,
                    "--skip-onstartup",
                    "--startup-method",
                    "AXBC_Run",
                    "--webadmin-auto-start",
                    "false",
                ],
                stdout=log,
                stderr=log,
                check=True,
                timeout=90,
            )
        result = json.loads(
            (driver / "Resources/result.json").read_text(encoding="utf-8-sig")
        )
        assert result.get("compiled") is (mode == "compiled"), result
        results.append(result)
    result = {
        "runs": results,
        "cases": [c for run in results for c in run.get("cases", [])],
    }
    cases = result.get("cases", [])
    checks = [
        {
            "name": "all candidate reads and record states returned in both modes",
            "passed": len(cases) == 96,
        }
    ]
    safe = {
        "recordNumbers",
        "namedRecordNumbers",
        "entitySelection",
        "entityValues",
        "workerEntities",
        "workerValues",
        "workerHighlight",
        "workerFailure",
    }
    for case in cases:
        if case["read"] in safe:
            checks.append(
                {
                    "name": case["read"]
                    + "/"
                    + case["mode"]
                    + ": original record state preserved",
                    "passed": case["before"] == case["after"],
                }
            )
            checks.append(
                {
                    "name": case["read"] + "/" + case["mode"] + ": OK preserved",
                    "passed": case["okPreserved"],
                }
            )
    expected_names = ["Saved " + str(i) for i in range(1, 6)]
    for run in results:
        for mode in ("saved", "modified", "unloaded", "new"):
            by_read = {
                case["read"]: case for case in run["cases"] if case["mode"] == mode
            }
            records = by_read["recordNumbers"]["values"]
            checks.append(
                {
                    "name": ("compiled" if run["compiled"] else "interpreted")
                    + "/"
                    + mode
                    + ": full selection order and distinct physical record IDs",
                    "passed": len(records) == 5
                    and len(set(records)) == 5
                    and all(isinstance(n, int) and n >= 0 for n in records),
                }
            )
            checks.append(
                {
                    "name": ("compiled" if run["compiled"] else "interpreted")
                    + "/"
                    + mode
                    + ": named selection keeps its own reverse order",
                    "passed": by_read["namedRecordNumbers"]["values"]
                    == records[-2:][::-1],
                }
            )
            checks.append(
                {
                    "name": ("compiled" if run["compiled"] else "interpreted")
                    + "/"
                    + mode
                    + ": entity selection count and persisted values",
                    "passed": by_read["entitySelection"]["values"] == [5]
                    and by_read["entityValues"]["values"] == expected_names,
                }
            )
            checks.append(
                {
                    "name": ("compiled" if run["compiled"] else "interpreted")
                    + "/"
                    + mode
                    + ": isolated named selection preserves order and shared entity values",
                    "passed": by_read["workerEntities"]["values"] == [2]
                    and by_read["workerValues"]["values"] == expected_names[-2:][::-1],
                }
            )
            checks.append(
                {
                    "name": ("compiled" if run["compiled"] else "interpreted")
                    + "/"
                    + mode
                    + ": isolated highlight read keeps both selected record IDs",
                    "passed": by_read["workerHighlight"]["values"]
                    == [records[0], records[-1]],
                }
            )
            checks.append(
                {
                    "name": ("compiled" if run["compiled"] else "interpreted")
                    + "/"
                    + mode
                    + ": production worker reports an invalid physical record without running the application error handler",
                    "passed": by_read["workerFailure"]["values"] == [True],
                }
            )
    checks.append(
        {
            "name": "destructive baseline detects loss of unsaved record",
            "passed": any(
                c["read"] == "selectionFields"
                and c["mode"] == "modified"
                and c["before"] != c["after"]
                for c in cases
            ),
        }
    )
    checks.append(
        {
            "name": "reads do not save synthetic editor values",
            "passed": all(run.get("savedNames") == expected_names for run in results),
        }
    )
    passed = all(c["passed"] for c in checks)
    report = {
        "passed": passed,
        "checks": checks,
        "result": result,
        "compiler": compiled,
        "driver_sha256": sha(ROOT / "test_classic_selection.py"),
        "worker_sources_sha256": {
            name: sha(ROOT / "host/OptionalMethods" / name)
            for name in ("AXB_SelectionRead.4dm", "AXB_SelectionError.4dm")
        },
        "scope": "Candidate commands in interpreted and compiled desktop engine processes. No grid, accessibility UI or VoiceOver coverage claim.",
    }
    (BUILD / "classic-selection-commands.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(
        f"{'PASS' if passed else 'FAIL'}: {len(checks)} classic-selection command checks"
    )
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
