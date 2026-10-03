#!/usr/bin/env python3
"""Check disclosure guards with real 4D types, without entering a UI."""
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
    path = BUILD / "outline-action-helpers.json"
    report = {"passed": False}
    path.write_text(json.dumps(report) + "\n")
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    app = (args.server or args.tool4d).expanduser().resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    helpers = [ROOT / "host/OptionalMethods" / (name + ".4dm") for name in ("AXB_OutlineTarget", "AXB_KeyIndex", "AXB_GridOptions")]
    report.update({"sourceSHA256": {str(p.relative_to(ROOT)): sha(p) for p in helpers}, "driverSHA256": sha(Path(__file__))})
    body = '''var $state; $action; $target; $candidate; $changed; $checks; $expected; $options : Object
var $malformed : Variant
var $property : Text
$checks:=New object
$expected:=New object("parent"; "parent"; "kind"; "group"; "level"; 1; "label"; "Exact A"; "expanded"; True)
$state:=New object("valid"; True; "positions"; New object("owned"; 7; "leaf"; 8); "binding"; New object("count"; 20; "hierarchy"; New collection(True; True)))
$state.descriptor:=New object("generation"; "current"; "order"; 1; "actions"; New object("disclose"; True); "disabled"; New collection; "outline"; New object("owned"; OB Copy($expected); "leaf"; New object("parent"; "owned"; "level"; 2; "kind"; "leaf")))
$state.descriptor.outline.owned.frame:=New collection(3; 4; 120; 24)
$action:=New object("operation"; "gridSetExpanded"; "value"; New object("row"; "owned"; "generation"; "current"; "expanded"; False; "expectedGroup"; OB Copy($expected)))
$action.value.expectedGroup.frame:=New collection(103; 204; 120; 24)
$target:=AXB_OutlineTarget($state; $action; True)
$checks.translatedGeometry:=$target.ok & ($target.backingRow=7) & ($target.breakLevel=2) & ($target.expanded=True)
$changed:=OB Copy($state)
$changed.descriptor.order:=8
$changed.descriptor.outline.owned.expanded:=False
$checks.beforeStateReject:=Not(AXB_OutlineTarget($changed; $action; True).ok)
$checks.confirmationAllowsDisclosureAndOrder:=AXB_OutlineTarget($changed; $action; False).ok
For each ($malformed; New collection(Null; 1; "scalar"; New collection))
 $candidate:=OB Copy($action)
 $candidate.value:=$malformed
 $checks["valueType"+String(Value type($malformed))]:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
 $candidate:=OB Copy($action)
 $candidate.value.expectedGroup:=$malformed
 $checks["groupType"+String(Value type($malformed))]:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
End for each
For each ($property; New collection("parent"; "label"; "kind"; "level"; "expanded"))
 $candidate:=OB Copy($action)
 $candidate.value.expectedGroup[$property]:=New collection
 $checks["malformed"+$property]:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
End for each
For each ($property; New collection("generation"; "row"; "expanded"))
 $candidate:=OB Copy($action)
 $candidate.value[$property]:=New collection
 $checks["malformedValue"+$property]:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
End for each
For each ($property; New collection("parent"; "label"))
 $changed:=OB Copy($state)
 $changed.descriptor.outline.owned[$property]:="replaced"
 $checks["changed"+$property]:=Not(AXB_OutlineTarget($changed; $action; False).ok)
End for each
$candidate:=OB Copy($action)
$candidate.value.row:="leaf"
$checks.leafReject:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
$candidate.value.row:="missing"
$checks.missingReject:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
$candidate:=OB Copy($action)
$candidate.value.generation:="old"
$checks.generationReject:=Not(AXB_OutlineTarget($state; $candidate; True).ok)
$changed:=OB Copy($state)
$changed.valid:=False
$checks.loadingReject:=Not(AXB_OutlineTarget($changed; $action; False).ok)
$changed:=OB Copy($state)
$changed.descriptor.actions.disclose:=False
$checks.capabilityReject:=Not(AXB_OutlineTarget($changed; $action; True).ok)
$changed:=OB Copy($state)
$changed.descriptor.disabled:=New collection("owned")
$checks.disabledReject:=Not(AXB_OutlineTarget($changed; $action; True).ok)
$changed:=OB Copy($state)
$changed.positions.owned:=0
$checks.zeroPositionReject:=Not(AXB_OutlineTarget($changed; $action; True).ok)
$changed.positions.owned:=21
$checks.highPositionReject:=Not(AXB_OutlineTarget($changed; $action; True).ok)
$changed:=OB Copy($state)
$changed.binding.hierarchy:=New collection(True)
$checks.breakLevelReject:=Not(AXB_OutlineTarget($changed; $action; True).ok)
$options:=New object("kind"; "outline"; "keyColumn"; "Key"; "setExpanded"; Formula(True))
$checks.controllerAccepted:=AXB_GridOptions(New object("Grid"; $options))
$options.kind:="array"
$checks.flatControllerReject:=Not(AXB_GridOptions(New object("Grid"; $options)))
$options.kind:="outline"
For each ($malformed; New collection(Null; 1; "scalar"; New collection; New object))
 $options.setExpanded:=$malformed
 $checks["controllerType"+String(Value type($malformed))]:=Not(AXB_GridOptions(New object("Grid"; $options)))
End for each
$result:=$checks
'''
    with tempfile.TemporaryDirectory(prefix="outline-actions-", dir=BUILD) as directory:
        project_at(Path(directory), "Driver")
        methods = Path(directory) / "Project/Sources/Methods"
        for helper in helpers:
            shutil.copy2(helper, methods / helper.name)
        result = run_utility(app / "Contents/MacOS" / info["CFBundleExecutable"], Path(directory), body, 90)
    report["result"] = result
    try:
        assert len(result) == 37, result
        assert all(value is True for value in result.values()), result
        assert report["sourceSHA256"] == {str(p.relative_to(ROOT)): sha(p) for p in helpers}
        report.update({"passed": True, "checks": len(result)})
    finally:
        path.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS:", report["checks"], "outline action-helper command checks")


if __name__ == "__main__":
    main()
