#!/usr/bin/env python3
"""Check outline geometry translation and mixed value pages with real 4D commands."""
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
    path = BUILD / "outline-host-helpers.json"
    report = {"passed": False}
    path.write_text(json.dumps(report) + "\n")
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    app = (args.server or args.tool4d).expanduser().resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    helpers = [ROOT / "host/OptionalMethods" / (name + ".4dm") for name in ("AXB_GridGeometry", "AXB_GridReadPages", "AXB_KeyIndex")]
    report["sourceSHA256"] = {str(p.relative_to(ROOT)): sha(p) for p in helpers}
    report["driverSHA256"] = sha(Path(__file__))
    with tempfile.TemporaryDirectory(prefix="outline-helpers-", dir=BUILD) as directory:
        project_at(Path(directory), "Driver")
        methods = Path(directory) / "Project/Sources/Methods"
        for helper in helpers:
            shutil.copy2(helper, methods / helper.name)
        (methods / "AXB_GridValue.4dm").write_text('''#DECLARE($state : Object; $column : Object; $position : Integer) -> $result : Object
$state.reads.push(New object("column"; $column.id; "position"; $position))
$result:=New object("ok"; True; "value"; "leaf "+String($position); "enabled"; True; "editable"; True)
''')
        body = '''var $grid; $translated; $state; $reply; $query : Object
$grid:=New object("outline"; New object("group"; New object("parent"; ""; "level"; 0; "kind"; "group"; "label"; "Immediate"; "expanded"; True; "frame"; New collection(3; 4; 120; 24)); "leaf"; New object("parent"; "group"; "level"; 1; "kind"; "leaf")); "visible"; New collection("group"); "frames"; New object("group"; New object("item"; New collection(3; 4; 120; 24))); "headers"; New object; "layout"; New object("rows"; New collection(New collection(4; 24)); "columns"; New collection(New collection(3; 120))))
$translated:=AXB_GridGeometry($grid; New collection(8; 9); New collection(14; 20; 100; 100))
$result:=New object("logicalGroup"; $translated.outline.group.frame; "originalGroup"; $grid.outline.group.frame; "viewportGroup"; $translated.frames.group.item; "leaf"; $translated.outline.leaf; "layoutRows"; $translated.layout.rows; "layoutColumns"; $translated.layout.columns)
$state:=New object("valid"; True; "positions"; New object("leaf"; 7); "columns"; New object("item"; New object("id"; "item"); "value"; New object("id"; "value")); "reads"; New collection)
$state.descriptor:=New object("generation"; "owned"; "order"; 1; "rows"; New collection("group"; "leaf"); "columns"; New collection(New object("id"; "item"; "enabled"; True; "editable"; True); New object("id"; "value"; "enabled"; True; "editable"; True)); "outline"; $grid.outline; "disabled"; New collection; "uneditable"; New collection)
$query:=New object("node"; "owned"; "generation"; "owned"; "order"; 1; "row"; 0; "rowCount"; 2; "column"; 0; "columnCount"; 2)
$reply:=AXB_GridReadPages($state; New collection($query))
$result.pages:=$reply.pages
$result.reads:=$state.reads
$state.reads:=New collection
$query.generation:="retired"
$reply:=AXB_GridReadPages($state; New collection($query))
$result.stalePages:=$reply.pages
$result.staleReads:=$state.reads
'''
        result = run_utility(app / "Contents/MacOS" / info["CFBundleExecutable"], Path(directory), body, 90)
    report["result"] = result
    try:
        assert result["logicalGroup"] == [11, 13, 120, 24]
        assert result["originalGroup"] == [3, 4, 120, 24]
        assert result["viewportGroup"] == [14, 20, 100, 17]
        assert "frame" not in result["leaf"] and result["leaf"]["parent"] == "group"
        assert result["layoutRows"] == [[13, 24]] and result["layoutColumns"] == [[11, 120]]
        rows = result["pages"][0]["rows"]
        assert [c["value"] for c in rows[0]["cells"]] == ["Immediate", ""]
        assert all(c["editable"] is False and c["role"] == "text" for c in rows[0]["cells"])
        assert [c["value"] for c in rows[1]["cells"]] == ["leaf 7", "leaf 7"]
        assert result["reads"] == [{"column": "item", "position": 7}, {"column": "value", "position": 7}]
        assert result["stalePages"] == [] and result["staleReads"] == []
        assert report["sourceSHA256"] == {str(p.relative_to(ROOT)): sha(p) for p in helpers}
        report.update({"passed": True, "checks": 11})
    finally:
        path.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: 11 outline host-helper command checks")


if __name__ == "__main__":
    main()
