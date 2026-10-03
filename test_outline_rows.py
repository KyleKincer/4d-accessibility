#!/usr/bin/env python3
"""Exercise grouped topology and identity rules in the actual 4D interpreter."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_component import BUILD, ROOT, literal, project_at, run_utility, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--server", type=Path)
    group.add_argument("--tool4d", type=Path)
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    path = BUILD / "outline-rows.json"
    report = {"passed": False}
    path.write_text(json.dumps(report) + "\n")
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    app = (args.server or args.tool4d).expanduser().resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    helper = ROOT / "host/OptionalMethods/AXB_OutlineRows.4dm"
    token = ROOT / "host/OptionalMethods/AXB_OutlineToken.4dm"
    report.update({"sourceSHA256": sha(helper), "driverSHA256": sha(Path(__file__))})
    report["tokenSHA256"] = sha(token)
    base = {"keys": ["One", "one", "third"], "flags": [0, 0, 0],
            "levels": [{"values": ["typed A"] * 3, "labels": ["A"] * 3,
                        "frames": [[0, 0, 100, 20], [0, 0, 100, 20], [0, 60, 100, 20]]}],
            "leafFrames": [[0, 20, 40, 20], [0, 40, 40, 20], [0, 80, 40, 20]]}
    body = '''var $base; $previous; $snapshot; $reply; $checks : Object
var $first; $later : Text
var $identity : Collection
$base:=JSON Parse(''' + literal(json.dumps(base)) + ''')
$previous:=AXB_OutlineRows($base; Null)
$first:=$previous.rows[0]
$later:=$previous.rows[3]
$checks:=New object
$checks.repeatedLabelsDistinct:=$previous.ok & ($first#$later) & ($previous.rows.length=5)
$checks.exactLeafKeys:=($previous.rows[1]="l:One") & ($previous.rows[2]="l:one")
$checks.ancestry:=($previous.outline["l:One"].parent=$first) & ($previous.outline["l:third"].parent=$later) & ($previous.outline["l:One"].level=1)
$checks.realLayout:=($previous.layout[3][0]=60) & ($previous.layout[4][0]=80)
// Geometry changes do not change the partition or identity.
$snapshot:=OB Copy($base)
$snapshot.levels[0].frames:=New collection(New collection(10; 50; 120; 20); New collection(10; 50; 120; 20); New collection(10; 110; 120; 20))
$snapshot.leafFrames:=New collection(New collection(10; 70; 40; 20); New collection(10; 90; 40; 20); New collection(10; 130; 40; 20))
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.geometryPreservesIdentity:=$reply.ok & ($reply.rows[0]=$first) & ($reply.rows[3]=$later) & Not($reply.requiresGeneration)
// Sorting must use exact character codes for canonical member sets.
$snapshot:=OB Copy($base)
$snapshot.keys:=New collection("one"; "One"; "third")
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.sortPreservesGroup:=$reply.ok & ($reply.rows[0]=$first) & ($reply.rows[1]="l:one") & ($reply.rows[2]="l:One")
// Collapse retains its group identity while excluding its leaves.
$snapshot:=OB Copy($base)
$snapshot.leafFrames:=New collection(New collection(0; 20; 40; 0); New collection(0; 20; 40; 0); New collection(0; 40; 40; 20))
$snapshot.levels[0].frames[2]:=New collection(0; 20; 100; 20)
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.collapsedGroup:=$reply.ok & ($reply.rows.length=3) & ($reply.rows[0]=$first) & Not($reply.outline[$first].expanded) & ($reply.rows[1]=$later)
$reply:=AXB_OutlineRows($base; $reply)
$checks.reopenRetainsRoot:=$reply.ok & ($reply.rows.length=5) & ($reply.rows[0]=$first) & $reply.outline[$first].expanded
// A native regroup can merge identically labelled roots.
$snapshot:=OB Copy($base)
$snapshot.levels[0].frames[2]:=New collection(0; 0; 100; 20)
$snapshot.leafFrames[2]:=New collection(0; 60; 40; 20)
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.mergeRetiresParents:=$reply.ok & ($reply.rows.length=4) & ($reply.rows[0]#$first) & ($reply.rows[0]#$later) & $reply.requiresGeneration
// Partial row hiding conservatively changes member identity.
$snapshot:=OB Copy($base)
$snapshot.flags[0]:=1
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.partialHiddenRetiresGroup:=$reply.ok & ($reply.rows[0]#$first) & ($reply.rows.length=4) & $reply.requiresGeneration
// Geometry establishes membership; exact values only establish safe labels.
$snapshot:=OB Copy($base)
$snapshot.levels[0].values[1]:="typed a"
$snapshot.levels[0].labels[1]:="a"
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.ambiguousLabelRejected:=Not($reply.ok)
$snapshot:=OB Copy($base)
$snapshot.keys[1]:="One"
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.duplicateKeysRejected:=Not($reply.ok)
$snapshot:=OB Copy($base)
$snapshot.levels[0].frames[1]:=New collection(0; 60; 100; 20)
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.overlapRejected:=Not($reply.ok)
$snapshot:=OB Copy($base)
$snapshot.leafFrames[1]:=New collection(0; 40; 40; 0)
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.mixedLeafDisclosureRejected:=Not($reply.ok)
// Two break levels, one collapsed nested group, and one expanded sibling.
$snapshot:=New object("keys"; New collection("first"; "second"); "flags"; New collection(0; 0); "levels"; New collection(New object("values"; New collection("root"; "root"); "labels"; New collection("Root"; "Root"); "frames"; New collection(New collection(0; 0; 100; 20); New collection(0; 0; 100; 20))); New object("values"; New collection("nested1"; "nested2"); "labels"; New collection("Nested"; "Nested"); "frames"; New collection(New collection(0; 20; 100; 20); New collection(0; 40; 100; 20)))); "leafFrames"; New collection(New collection(0; 40; 40; 0); New collection(0; 60; 40; 20)))
$reply:=AXB_OutlineRows($snapshot; Null)
$checks.nestedDisclosure:=$reply.ok & ($reply.rows.length=4) & $reply.outline[$reply.rows[0]].expanded & Not($reply.outline[$reply.rows[1]].expanded) & $reply.outline[$reply.rows[2]].expanded & ($reply.outline["l:second"].level=2)
var $mixed : Object
$mixed:=OB Copy($snapshot)
$mixed.levels[1].frames[0][3]:=0
$reply:=AXB_OutlineRows($mixed; Null)
$checks.mixedChildDisclosureRejected:=Not($reply.ok)
$snapshot.levels[0].frames[1]:=New collection(0; 0; 100; 0)
$reply:=AXB_OutlineRows($snapshot; Null)
$checks.missingAncestorRejected:=Not($reply.ok)
$snapshot:=OB Copy($base)
$snapshot.levels[0].frames[0]:=New collection(0; 20; 100; 0)
$snapshot.leafFrames[0]:=New collection(0; 20; 40; 0)
$reply:=AXB_OutlineRows($snapshot; Null)
$checks.missingRootRejected:=Not($reply.ok)
$snapshot:=OB Copy($base)
$snapshot.levels[0].frames[0]:=New collection(0; 20; 0; 0)
$reply:=AXB_OutlineRows($snapshot; Null)
$checks.zeroWidthRejected:=Not($reply.ok)
var $level : Integer
$snapshot:=New object("keys"; New collection("deep"); "flags"; New collection(0); "levels"; New collection; "leafFrames"; New collection(New collection(0; 180; 40; 20)))
For ($level; 0; 8)
 $snapshot.levels.push(New object("values"; New collection("level "+String($level)); "labels"; New collection("Level "+String($level)); "frames"; New collection(New collection(0; $level*20; 100; 20))))
End for
$reply:=AXB_OutlineRows($snapshot; Null)
$checks.nineBreakLevels:=$reply.ok & ($reply.rows.length=10) & ($reply.outline["l:deep"].level=9)
$snapshot:=New object("keys"; New collection; "flags"; New collection; "levels"; New collection(New object("values"; New collection; "labels"; New collection; "frames"; New collection)); "leafFrames"; New collection)
$reply:=AXB_OutlineRows($snapshot; Null)
$checks.emptyLoaded:=$reply.ok & ($reply.rows.length=0) & (OB Keys($reply.outline).length=0)
$checks.exactTextToken:=Compare strings(AXB_OutlineToken("A"; Text array); AXB_OutlineToken("a"; Text array); sk char codes)#0
$identity:=JSON Parse(AXB_OutlineToken(2147483647; LongInt array))
$checks.integerToken:=($identity.length=2) & ($identity[0]=LongInt array) & ($identity[1]=2147483647)
$identity:=JSON Parse(AXB_OutlineToken(!2026-10-01!; Date array))
$checks.fullDateToken:=($identity.length=4) & ($identity[0]=Date array) & ($identity[1]=2026) & ($identity[2]=10) & ($identity[3]=1)
$checks.dateCenturiesDistinct:=AXB_OutlineToken(!2026-10-01!; Date array)#AXB_OutlineToken(!1926-10-01!; Date array)
$identity:=JSON Parse(AXB_OutlineToken(?01:02:03?; Time array))
$checks.timeSecondsToken:=($identity.length=2) & ($identity[0]=Time array) & ($identity[1]=3723)
$checks.unprovenRealRejected:=AXB_OutlineToken(1.25; Real array)=""
$snapshot:=OB Copy($base)
For ($level; 0; 2)
 $snapshot.levels[0].values[$level]:=AXB_OutlineToken(!2026-10-01!; Date array)
 $snapshot.levels[0].labels[$level]:="10/1/26"
End for
$previous:=AXB_OutlineRows($snapshot; Null)
For ($level; 0; 2)
 $snapshot.levels[0].values[$level]:=AXB_OutlineToken(!1926-10-01!; Date array)
End for
$reply:=AXB_OutlineRows($snapshot; $previous)
$checks.sameCaptionChangedDateRetiresGroup:=$reply.ok & ($reply.rows[0]#$previous.rows[0]) & $reply.requiresGeneration
$result:=$checks
'''
    with tempfile.TemporaryDirectory(prefix="outline-rows-", dir=BUILD) as directory:
        project_at(Path(directory), "Driver")
        shutil.copy2(helper, Path(directory) / "Project/Sources/Methods" / helper.name)
        shutil.copy2(token, Path(directory) / "Project/Sources/Methods" / token.name)
        result = run_utility(app / "Contents/MacOS" / info["CFBundleExecutable"], Path(directory), body, 90)
    report["result"] = result
    try:
        assert len(result) == 28 and all(value is True for value in result.values()), result
        assert sha(helper) == report["sourceSHA256"]
        assert sha(token) == report["tokenSHA256"]
        report.update({"passed": True, "checks": len(result)})
    finally:
        path.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: 28 grouped topology and identity command checks")


if __name__ == "__main__":
    main()
