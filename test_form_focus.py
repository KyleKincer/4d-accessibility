#!/usr/bin/env python3
"""Exercise the production focus resolver with real 4D objects and paths."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_component import BUILD, ROOT, literal, project_at, run_utility, sha


def node(identifier, data, path, origin=(0, 0), visible=True, enabled=True, observed=True, focus_names=("Name",), binding_key=None, container_enabled=True):
    return {"id": identifier, "objectName": "Name", "enabled": enabled, "visible": visible, "observed": observed,
            "focusNames": None if focus_names is None else list(focus_names), "containerEnabled": container_enabled, "owner": {"bindingKey": binding_key or identifier, "formName": "untitled", "path": path, "origin": list(origin), "data": data}}


def source(data, origin=(0, 0), known=()):
    known = [{"bindingKey": item["id"], **item} for item in known]
    return {"name": "Name", "formName": "untitled", "data": data,
            "origin": list(origin), "known": list(known)}


ROOT_NODE = node("root", "parent", [])
CHILD_NODE = node("child", "child", ["Child"], (20, 145))
CASES = [
    {"label": "ordinary root", "nodes": [ROOT_NODE, CHILD_NODE], "sources": [source("parent")], "expected": "root"},
    {"label": "forwarded child event", "nodes": [ROOT_NODE, CHILD_NODE], "sources": [source("child", (20, 145)), source("parent")], "expected": "child"},
    {"label": "parent before child", "nodes": [ROOT_NODE, CHILD_NODE], "sources": [source("parent"), source("child", (20, 145))], "expected": "child"},
    {"label": "unrelated siblings", "nodes": [node("left", "left", ["Left"]), node("right", "right", ["Right"])], "sources": [source("left"), source("right")], "expected": None},
    {"label": "shared binding at distinct positions", "nodes": [node("left", "shared", ["Left"], (0, 0)), node("right", "shared", ["Right"], (100, 0))], "sources": [source("shared", (100, 0))], "expected": "right"},
    {"label": "shared binding at identical positions", "nodes": [node("left", "shared", ["Left"]), node("right", "shared", ["Right"])], "sources": [source("shared")], "expected": None},
    {"label": "previous shared instance occupied the point", "nodes": [node("left", "shared", ["Left"], (100, 0)), node("right", "shared", ["Right"])], "sources": [source("shared", known=[{"id": "left", "origin": [0, 0]}])], "expected": None},
    {"label": "retired data binding", "nodes": [CHILD_NODE], "sources": [source("retired")], "expected": None},
    {"label": "hidden child", "nodes": [node("child", "child", ["Child"], visible=False)], "sources": [source("child")], "expected": None},
    {"label": "same path has conflicting controls", "nodes": [node("one", "one", []), node("two", "two", [])], "sources": [source("one"), source("two")], "expected": None},
    {"label": "forwarded parent has no local field", "nodes": [CHILD_NODE], "contexts": [ROOT_NODE], "sources": [source("child", (20, 145)), source("parent")], "expected": "child"},
    {"label": "nested forwarded event", "nodes": [ROOT_NODE, CHILD_NODE, node("nested", "nested", ["Child", "Nested"])], "sources": [source("nested"), source("child", (20, 145)), source("parent")], "expected": "nested"},
]
CASES += [
    {"label": "unknown native names conservatively block the parent", "nodes": [ROOT_NODE], "contexts": [node("child", "child", ["Child"], observed=False, focus_names=None)], "sources": [source("parent")], "expected": None},
    {"label": "forwarded unrelated context cannot lend child evidence", "nodes": [CHILD_NODE], "contexts": [node("other", "other", ["Other"])], "sources": [source("child", (20, 145)), source("other")], "expected": None},
    {"label": "resolved event marks observer participation", "nodes": [node("root", "parent", [], observed=False)], "sources": [source("parent")], "expected": "root", "marks": "root"},
    {"label": "unobserved sibling does not block the child", "nodes": [ROOT_NODE, CHILD_NODE], "contexts": [node("other", "other", ["Other"], observed=False)], "sources": [source("child", (20, 145)), source("parent")], "expected": "child"},
    {"label": "unobserved grandchild blocks the child", "nodes": [ROOT_NODE, CHILD_NODE], "contexts": [node("nested", "nested", ["Child", "Nested"], observed=False)], "sources": [source("child", (20, 145)), source("parent")], "expected": None},
    {"label": "native disabled descendant does not receive forwarded focus", "nodes": [ROOT_NODE], "contexts": [node("child", "child", ["Child"], observed=False, container_enabled=False)], "sources": [source("parent")], "expected": "root"},
    {"label": "provider disabled descendant can still own native focus", "nodes": [ROOT_NODE], "contexts": [node("child", "child", ["Child"], observed=False, enabled=False)], "sources": [source("parent")], "expected": None},
    {"label": "retired shared instance cannot become a unique sibling", "nodes": [node("right", "shared", ["Right"], (100, 0))], "sources": [source("shared", known=[{"id": "left", "origin": [0, 0]}])], "expected": None},
    {"label": "record scope change retains the same physical form", "nodes": [node("new-root", "parent", [], binding_key="root")], "sources": [source("parent", known=[{"id": "old-root", "bindingKey": "root", "origin": [0, 0]}])], "expected": "new-root"},
    {"label": "distinct native child names need no extra observer", "nodes": [ROOT_NODE], "contexts": [node("child", "child", ["Child"], observed=False, focus_names=("Other",))], "sources": [source("parent")], "expected": "root"},
    {"label": "unobserved form with no ordinary node", "nodes": [ROOT_NODE], "contexts": [node("child", "child", ["Child"], observed=False)], "sources": [source("parent")], "expected": None},
    {"label": "hidden parent forwards child focus", "nodes": [node("root", "parent", [], visible=False), CHILD_NODE], "sources": [source("child", (20, 145)), source("parent")], "expected": "child"},
    {"label": "disabled parent forwards child focus", "nodes": [node("root", "parent", [], enabled=False), CHILD_NODE], "sources": [source("child", (20, 145)), source("parent")], "expected": "child"},
    {"label": "unobserved descendant cannot lend parent evidence", "nodes": [ROOT_NODE, node("child", "child", ["Child"], observed=False)], "sources": [source("parent")], "expected": None},
    {"label": "retired child cannot lend parent evidence", "nodes": [ROOT_NODE, CHILD_NODE], "sources": [source("retired"), source("parent")], "expected": None},
    {"label": "disabled child cannot lend parent evidence", "nodes": [ROOT_NODE, node("child", "child", ["Child"], enabled=False)], "sources": [source("child"), source("parent")], "expected": None},
    {"label": "ancestor plus ambiguous descendants", "nodes": [ROOT_NODE, node("left", "shared", ["Left"]), node("right", "shared", ["Right"])], "sources": [source("shared"), source("parent")], "expected": None},
    {"label": "siblings with their parent", "nodes": [ROOT_NODE, node("left", "left", ["Left"]), node("right", "right", ["Right"])], "sources": [source("left"), source("parent"), source("right")], "expected": None},
    {"label": "old shared position plus parent", "nodes": [ROOT_NODE, node("left", "shared", ["Left"], (100, 0)), node("right", "shared", ["Right"])], "sources": [source("shared", known=[{"id": "left", "origin": [0, 0]}]), source("parent")], "expected": None},
    {"label": "too many event contexts", "nodes": [ROOT_NODE], "sources": [source("parent")], "ambiguous": True, "expected": None},
]
for case in CASES:
    case.setdefault("contexts", [])
    case.setdefault("ambiguous", False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    compiler = parser.add_mutually_exclusive_group(required=True)
    compiler.add_argument("--server", type=Path)
    compiler.add_argument("--tool4d", type=Path)
    args = parser.parse_args()
    for process in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", process], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential utility test")
    app = (args.server or args.tool4d).expanduser().resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != ("com.4D.4DServer" if args.server else "com.4D.tool"):
        parser.error("The application does not match --server/--tool4d")
    helper = ROOT / "host/OptionalMethods/AXB_FormEvent.4dm"
    BUILD.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="form-focus-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        methods = driver / "Project/Sources/Methods"
        shutil.copy2(helper, methods / helper.name)
        shutil.copy2(ROOT / "host/OptionalMethods/AXB_FormObserver.4dm", methods / "AXB_FormObserver.4dm")
        # Resolve does not call the native provider. This stub makes the other
        # entry path compilable without installing a graphical plugin.
        (methods / "AXB_Host.4dm").write_text('#DECLARE($operation : Text; $data : Object) -> $result : Object\n$result:=New object("ok"; False)\n')
        body = '''$result:=New object("cases"; New collection; "compiled"; Is compiled mode)
var $case; $registry; $data; $node; $owner; $source; $copy; $resolved; $entry : Object
var $label : Text
For each ($case; JSON Parse(''' + literal(json.dumps(CASES)) + '''))
 $data:=New object
 $registry:=New object("controls"; $case.nodes; "controlContexts"; New object; "formContexts"; New object; "focusObserverBindings"; New object; "bindings"; New object; "observedFocus"; New object("name"; "Name"; "sources"; New collection; "ambiguous"; $case.ambiguous=True))
 For each ($node; $case.nodes.copy().concat($case.contexts))
  $owner:=$node.owner
  $label:=$owner.data
  If ($data[$label]=Null)
   $data[$label]:=New object("label"; $label)
  End if
  $registry.bindings[$owner.bindingKey]:=$data[$label]
  $registry.controlContexts[$node.id]:=New object("bindingKey"; $owner.bindingKey; "path"; $owner.path; "formName"; $owner.formName; "origin"; $owner.origin; "focusNames"; $node.focusNames; "enabled"; $node.containerEnabled)
  $registry.formContexts[$owner.bindingKey]:=$registry.controlContexts[$node.id]
  $registry.focusObserverBindings[$owner.bindingKey]:=$node.observed
 End for each
 For each ($source; $case.sources)
  $label:=$source.data
  If ($data[$label]=Null)
   $data[$label]:=New object("label"; $label)
  End if
  $copy:=New object("name"; $source.name; "formName"; $source.formName; "origin"; $source.origin; "known"; $source.known; "data"; $data[$label])
  $registry.observedFocus.sources.push($copy)
 End for each
 AXB_FormRoots:=New object
 AXB_FormRoots[String(Current form window)]:=$registry
 $resolved:=AXB_FormEvent("resolve")
 $entry:=New object("label"; $case.label; "id"; $registry.observedFocus.id)
 If ($case.marks#Null)
  $entry.marked:=$registry.focusObserverBindings[$case.marks]=True
 End if
 $result.cases.push($entry)
End for each
// Pending notes are independent of application data and consumed once.
$registry:=New object("bindings"; New object; "focusObserverBindings"; New object)
AXB_FormRoots[String(Current form window)]:=$registry
var $view; $record : Object
$record:=New object("window"; Current form window; "focusObservers"; New collection(New object("formName"; "untitled"; "origin"; New collection(0; 0))))
AXB_Areas:=New object("owned"; $record)
AXB_FormObserver("transfer"; $record)
$view:=New object("bindingKey"; "first"; "formName"; "untitled"; "origin"; New collection(0; 0))
AXB_FormObserver("bind"; $view)
$result.pendingNoteBound:=$registry.focusObserverBindings.first=True
$view.bindingKey:="replacement"
AXB_FormObserver("bind"; $view)
$result.pendingNoteConsumed:=Not($registry.focusObserverBindings.replacement=True)
$registry.focusObservers.push(New object("formName"; "another"; "origin"; New collection(0; 0)))
AXB_FormObserver("forget"; Null)
$result.pendingNotesForgotten:=($registry.focusObservers=Null) & ($record.focusObservers=Null)
$result.knownLifetimePreserved:=$registry.focusObserverBindings.first=True
// Restart carries only observed physical paths and the same data objects.
$data:=New object("root"; New object; "child"; New object; "other"; New object)
$registry.bindings:=New object("root"; $data.root; "child"; $data.child; "other"; $data.other)
$registry.focusObserverBindings:=New object("root"; True; "child"; True; "other"; False)
$registry.formContexts:=New object("root"; New object("formName"; "untitled"; "origin"; New collection(0; 0); "path"; New collection); "child"; New object("formName"; "untitled"; "origin"; New collection(20; 100); "path"; New collection("Child")); "other"; New object("formName"; "untitled"; "origin"; New collection(20; 200); "path"; New collection("Other")))
$registry.focusObservers:=AXB_FormObserver("snapshot"; Null)
$result.restartCarriesOnlyObservedForms:=$registry.focusObservers.length=2
$registry.focusObserverBindings:=New object
$view:=New object("bindingKey"; "new-root"; "formName"; "untitled"; "origin"; New collection(0; 0); "path"; New collection; "data"; New object)
AXB_FormObserver("bind"; $view)
$result.carriedNoteRejectsReplacement:=Not($registry.focusObserverBindings["new-root"]=True)
$view.data:=$data.root
AXB_FormObserver("bind"; $view)
$result.restartRootBound:=$registry.focusObserverBindings["new-root"]=True
$view:=New object("bindingKey"; "new-child"; "formName"; "untitled"; "origin"; New collection(20; 50); "path"; New collection("Child"); "data"; $data.child)
AXB_FormObserver("bind"; $view)
$result.restartChildBoundAfterScroll:=$registry.focusObserverBindings["new-child"]=True
$registry.focusObserverBindings:=New object("root"; True; "child"; True; "other"; True)
var $notes : Collection
$notes:=AXB_FormObserver("snapshot"; New object("excludeSubform"; "Child"))
$result.invalidateCarriesUnaffectedForms:=($notes.length=2) && ($notes[0].path.indexOf("Child")<0) && ($notes[1].path.indexOf("Child")<0)
AXB_Areas:=Null
AXB_FormRoots:=Null'''
        result = run_utility(app / "Contents/MacOS" / info["CFBundleExecutable"], driver, body, 90)
    rows = result.get("cases", [])
    checks = [{"name": "all focus cases returned", "passed": len(rows) == len(CASES)}]
    checks.extend({"name": expected["label"], "passed": actual.get("label") == expected["label"] and actual.get("id") == expected["expected"]}
                  for expected, actual in zip(CASES, rows))
    checks.extend({"name": "resolved source recorded participation", "passed": actual.get("marked") is True}
                  for expected, actual in zip(CASES, rows) if expected.get("marks"))
    checks.extend({"name": name, "passed": result.get(name) is True}
                  for name in ("pendingNoteBound", "pendingNoteConsumed", "pendingNotesForgotten", "knownLifetimePreserved", "restartCarriesOnlyObservedForms", "carriedNoteRejectsReplacement", "restartRootBound", "restartChildBoundAfterScroll", "invalidateCarriesUnaffectedForms"))
    passed = all(check["passed"] for check in checks)
    report = {"passed": passed, "checks": checks, "result": result, "helper_sha256": sha(helper),
              "observer_sha256": sha(ROOT / "host/OptionalMethods/AXB_FormObserver.4dm"),
              "scope": "Real 4D object identity, production resolution, note transfer and restart/invalidation snapshots. Live event delivery and area startup are tested in the desktop fixture."}
    (BUILD / "form-focus-commands.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: {len(checks)} form-focus command checks")
    if not passed:
        print(json.dumps(report, indent=2))
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
