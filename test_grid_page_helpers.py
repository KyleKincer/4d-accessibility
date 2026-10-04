#!/usr/bin/env python3
"""Exercise FIFO page batching and editability guards with real 4D helpers.

The view seam records dispatches and uses the real page reader. Native view
ownership, geometry and live application behavior have separate gates.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_component import BUILD, ROOT, project_at, run_utility, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--server", type=Path)
    group.add_argument("--tool4d", type=Path)
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    path = BUILD / "grid-page-helpers.json"
    report = {"passed": False, "scope": __doc__.strip()}
    path.write_text(json.dumps(report) + "\n")
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    app = (args.server or args.tool4d).expanduser().resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    helpers = [ROOT / "host/OptionalMethods" / (name + ".4dm") for name in
               ("AXB_GridPoll", "AXB_GridReadPages", "AXB_KeyIndex")]
    report["sourceSHA256"] = {str(p.relative_to(ROOT)): sha(p) for p in helpers}
    report["driverSHA256"] = sha(Path(__file__))
    with tempfile.TemporaryDirectory(prefix="grid-page-helpers-", dir=BUILD) as directory:
        project_at(Path(directory), "Driver")
        methods = Path(directory) / "Project/Sources/Methods"
        for helper in helpers:
            shutil.copy2(helper, methods / helper.name)
        key_path = methods / "AXB_KeyIndex.4dm"
        lines = key_path.read_text().splitlines()
        declaration = next(i for i, line in enumerate(lines) if line.startswith("#DECLARE"))
        lines[declaration + 1:declaration + 1] = [
            "C_LONGINT(<>uneditableLookups)",
            "If ($keys.length=1000)", " <>uneditableLookups+=1", "End if"]
        key_path.write_text("\n".join(lines) + "\n")
        (methods / "AXB_GridValue.4dm").write_text('''#DECLARE($state : Object; $column : Object; $position : Integer)->$result : Object
$result:=New object("ok"; True; "value"; $column.id+" "+String($position); "enabled"; True; "editable"; $column.valueEditable)
''')
        (methods / "AXB_View.4dm").write_text('''#DECLARE($packet : Object)->$result : Object
var $record : Object
$record:=OB Copy($packet)
OB REMOVE($record; "rootView")
$packet.rootView.calls.push($record)
$result:=AXB_GridReadPages($packet.rootView.state; $packet.requests)
''')
        body = '''var $context; $tree; $state; $route; $routeB; $a; $b; $c; $d; $reply : Object
var $key : Text
var $i : Integer
C_LONGINT(<>uneditableLookups)
<>uneditableLookups:=0
$state:=New object("valid"; True; "positions"; New object; "columns"; New object("c0"; New object("id"; "c0"; "valueEditable"; True); "c1"; New object("id"; "c1"; "valueEditable"; True)))
$state.descriptor:=New object("generation"; "owned"; "order"; 1; "rows"; New collection; "columns"; New collection(New object("id"; "c0"; "enabled"; True; "editable"; False); New object("id"; "c1"; "enabled"; True; "editable"; False)); "disabled"; New collection; "uneditable"; New collection)
For ($i; 0; 999)
 $key:="r"+String($i)
 $state.descriptor.rows.push($key)
 $state.positions[$key]:=$i+1
End for
$state.descriptor.uneditable:=$state.descriptor.rows.copy()
$context:=New object("view"; New object("state"; $state; "calls"; New collection); "token"; New shared object("fast"; True))
$route:=New object("node"; New object("grid"; $state.descriptor; "visible"; True); "path"; New collection("Child"); "lineage"; New collection("root-instance"; "child-instance"); "instance"; "child-instance"; "scope"; "record-owned"; "localID"; "LocalGrid")
$routeB:=New object("node"; New object("grid"; $state.descriptor; "visible"; True); "path"; New collection("OtherChild"); "lineage"; New collection("root-instance"; "other-instance"); "instance"; "other-instance"; "scope"; "other-record"; "localID"; "OtherGrid")
$tree:=New object("routes"; New object("GridA"; $route; "GridB"; $routeB))
$a:=New object("node"; "GridA"; "generation"; "owned"; "order"; 1; "row"; 0; "rowCount"; 1; "column"; 0; "columnCount"; 2)
$b:=OB Copy($a)
$b.row:=1
$c:=OB Copy($a)
$c.node:="GridB"
$d:=OB Copy($a)
$d.columnCount:=1
$result:=New object
AXB_GridPoll($context; $tree; New collection($a; $b; $c; $a))
$result.sameRoute:=New object("calls"; $context.view.calls; "pages"; $context.gridPages; "queue"; $context.gridQueue.copy(); "queuedKeys"; OB Keys($context.gridQueued); "fast"; $context.token.fast; "uneditableLookups"; <>uneditableLookups)
$context.view.calls:=New collection
AXB_GridPoll($context; $tree; New collection)
$result.remaining:=New object("calls"; $context.view.calls; "pages"; $context.gridPages; "queue"; $context.gridQueue.copy(); "queuedKeys"; OB Keys($context.gridQueued))
$context.view.calls:=New collection
AXB_GridPoll($context; $tree; New collection($a; $c; $b))
$result.differentRoutes:=New object("calls"; $context.view.calls; "pages"; $context.gridPages; "queue"; $context.gridQueue.copy())
$context.gridQueue:=New collection
$context.gridQueued:=New object
$context.view.calls:=New collection
$b.order:=2
AXB_GridPoll($context; $tree; New collection($a; $b))
$result.staleSecond:=New object("calls"; $context.view.calls; "pages"; $context.gridPages)
$b.order:=1
$d.rowCount:=16
$reply:=AXB_GridReadPages($state; New collection($d))
$result.maximumPages:=$reply.pages
$d.rowCount:=17
$reply:=AXB_GridReadPages($state; New collection($d))
$result.oversizePages:=$reply.pages
$d.rowCount:=1
$d.row:=1000
$reply:=AXB_GridReadPages($state; New collection($d))
$result.outOfRangePages:=$reply.pages
$state.descriptor.columns[0].editable:=True
<>uneditableLookups:=0
$reply:=AXB_GridReadPages($state; New collection($a))
$result.editableRestricted:=New object("pages"; $reply.pages; "lookups"; <>uneditableLookups)
$state.descriptor.uneditable[0]:="unrestricted"
$reply:=AXB_GridReadPages($state; New collection($a))
$result.editableAllowed:=$reply.pages
$result.exactMembership:=New collection
For each ($key; New collection("R0"; "cafe"; "r@"))
 $state.descriptor.uneditable[0]:=$key
 $state.descriptor.rows[0]:=Choose($key="cafe"; "café"; "r0")
 $state.positions[$state.descriptor.rows[0]]:=1
 <>uneditableLookups:=0
 $reply:=AXB_GridReadPages($state; New collection($a))
 $result.exactMembership.push(New object("restrictedKey"; $key; "rowKey"; $state.descriptor.rows[0]; "pages"; $reply.pages; "lookups"; <>uneditableLookups))
End for each
$state.descriptor.rows[0]:="r0"
$state.descriptor.uneditable[0]:="unrestricted"
$state.columns.c0.valueEditable:=False
<>uneditableLookups:=0
$reply:=AXB_GridReadPages($state; New collection($a))
$result.valueReadOnly:=New object("pages"; $reply.pages; "lookups"; <>uneditableLookups)
'''
        result = run_utility(app / "Contents/MacOS" / info["CFBundleExecutable"], Path(directory), body, 90)
    report["result"] = result
    checks = []
    def check(condition, description):
        assert condition, description
        checks.append(description)
    try:
        same = result["sameRoute"]
        check(len(same["calls"]) == 1 and len(same["calls"][0]["requests"]) == 2, "two adjacent same-route pages share one fresh view dispatch")
        check([(p["node"], p["row"], p["column"]) for p in same["pages"]] == [("GridA", 0, 0), ("GridA", 1, 0)], "both page coordinates and order survive batching")
        check([p["rows"][0]["cells"][0]["value"] for p in same["pages"]] == ["c0 1", "c0 2"], "both pages use their correct backing rows")
        packet = same["calls"][0]
        check(packet["operation"] == "readGrid" and packet["path"] == ["Child"] and packet["lineage"] == ["root-instance", "child-instance"] and packet["instance"] == "child-instance" and packet["scope"] == "record-owned" and packet["action"]["node"] == "LocalGrid", "batch retains the view authority packet")
        check(len(same["queue"]) == len(same["queuedKeys"]) == 1 and same["queue"][0]["query"]["node"] == "GridB", "two-request budget and deduplication preserve the next FIFO request")
        check(same["fast"] is False, "page requests keep ordinary background polling")
        check(same["uneditableLookups"] == 0 and all(not c["editable"] for p in same["pages"] for c in p["rows"][0]["cells"]), "read-only columns skip the long uneditable list without granting editing")
        remaining = result["remaining"]
        check(len(remaining["calls"]) == len(remaining["pages"]) == 1 and remaining["pages"][0]["node"] == "GridB" and remaining["queue"] == remaining["queuedKeys"] == [], "the next cycle drains the retained request and deduplication key")
        different = result["differentRoutes"]
        check(len(different["calls"]) == 2 and all(len(c["requests"]) == 1 for c in different["calls"]), "different routes retain separate fresh view dispatches")
        other = different["calls"][1]
        check(other["path"] == ["OtherChild"] and other["lineage"] == ["root-instance", "other-instance"] and other["instance"] == "other-instance" and other["scope"] == "other-record" and other["action"]["node"] == "OtherGrid", "a different route retains its own path, lineage, instance, scope and local grid")
        check([p["node"] for p in different["pages"]] == ["GridA", "GridB"] and different["queue"][0]["query"]["row"] == 1, "different-route FIFO ordering preserves the third request")
        check(len(result["staleSecond"]["calls"]) == 1 and len(result["staleSecond"]["pages"]) == 1 and result["staleSecond"]["pages"][0]["row"] == 0, "a stale second order is rejected independently inside a batch")
        check(len(result["maximumPages"]) == 1 and len(result["maximumPages"][0]["rows"]) == 16, "a valid sixteen-row page reaches the existing upper bound")
        check(result["outOfRangePages"] == [], "a request beyond the actual descriptor rows is rejected")
        check(result["oversizePages"] == [], "existing sixteen-row page bound remains enforced")
        restricted = result["editableRestricted"]
        check(restricted["lookups"] == 1 and not restricted["pages"][0]["rows"][0]["cells"][0]["editable"], "editable columns still enforce exact uneditable row membership")
        check(result["editableAllowed"][0]["rows"][0]["cells"][0]["editable"] is True, "a genuinely editable unrestricted leaf stays editable")
        exact = result["exactMembership"]
        check([(e["restrictedKey"], e["rowKey"]) for e in exact] == [("R0", "r0"), ("cafe", "café"), ("r@", "r0")], "case, accent and wildcard cases exercise distinct row identities")
        check(all(e["lookups"] == 1 and e["pages"][0]["rows"][0]["cells"][0]["editable"] is True for e in exact), "only exact uneditable membership disables editing")
        check(result["valueReadOnly"]["lookups"] == 0 and not result["valueReadOnly"]["pages"][0]["rows"][0]["cells"][0]["editable"], "a read-only value skips the scan and remains read-only")
        check(report["sourceSHA256"] == {str(p.relative_to(ROOT)): sha(p) for p in helpers}, "canonical helper inputs remain unchanged")
        report.update({"passed": True, "checks": checks, "count": len(checks)})
    finally:
        path.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} grid-page helper command checks")


if __name__ == "__main__":
    main()
