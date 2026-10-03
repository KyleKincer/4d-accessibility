#!/usr/bin/env python3
"""Prepare a bridge-free native hierarchy probe; this is not adapter acceptance."""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, ROOT, literal, project_at, run_utility, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--diagnostic-plugin", type=Path)
    args = parser.parse_args()
    for name in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential probe")
    fixture = BUILD / "hierarchy-probe"
    if fixture.exists():
        fixture.rename(BUILD / ("hierarchy-probe-previous-" + uuid.uuid4().hex))
    project = project_at(fixture, "Hierarchy")
    sources = project.parent / "Sources"
    methods = sources / "Methods"
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text('''ON ERR CALL("AXHP_Error")
var $window : Integer
var $data : Object
$data:=New object("runId"; File("/RESOURCES/run-id.txt").getText())
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.runId)))
CLEAR LIST($data.tree; *)
CLOSE WINDOW($window)
QUIT 4D
''')
    for path in (ROOT / "tests/4d").glob("AXHP_*.4dm"):
        shutil.copy2(path, methods / path.name)
    (methods / "Compiler_Hierarchy.4dm").write_text('''ARRAY TEXT(AXHP_Group; 0)
ARRAY TEXT(AXHP_Subgroup; 0)
ARRAY TEXT(AXHP_Label; 0)
ARRAY LONGINT(AXHP_Key; 0)
ARRAY BOOLEAN(AXHP_Selection; 0)
ARRAY LONGINT(AXHP_Control; 0)
C_OBJECT(AXHP_Command; $0)
C_OBJECT(AXHP_Command; $1)
C_OBJECT(AXHP_Topology; $0)
C_LONGINT(AXHP_Topology; $1)
C_COLLECTION(AXHP_Topology; $2)
C_OBJECT(AXHP_ListState; $0)
C_TEXT(AXHP_ListState; $1)
C_OBJECT(AXHP_GroupedRead; $0)
C_TEXT(AXHP_GroupedRead; $1)
C_OBJECT(AXHP_GroupedSentinel; $0)
C_TEXT(AXHP_GroupedSentinel; $1)
C_TEXT(AXHP_GroupedCase; $1)
''')
    if args.diagnostic_plugin:
        shutil.copytree(args.diagnostic_plugin, fixture / "Plugins/AccessibilityBridge.bundle")
        state = methods / "AXHP_State.4dm"
        state.write_text(state.read_text().replace("// Native probe result, when installed.",
            '$state.native:=JSON Parse(AXB Native layout(Current form window; "hierarchyProbe"))'))
    objects = {}
    for name, left in (("TreeA", 20), ("TreeB", 350)):
        objects[name] = {"type": "list", "dataSource": "Form.tree", "left": left,
            "top": 20, "width": 300, "height": 230, "fontSize": 13,
            "enterable": True, "selectionMode": "multiple",
            "scrollbarVertical": "visible", "scrollbarHorizontal": "hidden",
            "events": ["onClick", "onSelectionChange", "onExpand", "onCollapse", "onDataChange"],
            "method": "ObjectMethods/" + name + ".4dm"}
    columns = []
    for name, source, width in (("Group", "AXHP_Group", 160),
            ("Subgroup", "AXHP_Subgroup", 160), ("Label", "AXHP_Label", 270)):
        columns.append({"name": name, "dataSource": source, "width": width,
            "enterable": name == "Label", "header": {"name": name + "Header", "text": name}})
    objects["Grouped"] = {"type": "listbox", "dataSource": "AXHP_Selection", "rowControlSource": "AXHP_Control",
        "left": 20, "top": 280, "width": 630, "height": 220,
        "rowHeight": 24, "headerHeight": 24, "selectionMode": "multiple",
        "scrollbarVertical": "visible", "scrollbarHorizontal": "automatic",
        "columns": columns, "events": ["onClick", "onSelectionChange", "onExpand", "onCollapse", "onDataChange"],
        "method": "ObjectMethods/Grouped.4dm"}
    objects["Close"] = {"type": "button", "text": "Close probe", "action": "cancel",
        "left": 520, "top": 520, "width": 130, "height": 28}
    form = {"windowTitle": "AX native hierarchy probe", "width": 680, "height": 570,
        "method": "method.4dm", "events": ["onLoad", "onTimer"],
        "pages": [None, {"objects": objects}]}
    form_path = sources / "Forms/Probe"
    (form_path / "ObjectMethods").mkdir(parents=True)
    (form_path / "method.4dm").write_text("AXHP_Form\n")
    for name in ("TreeA", "TreeB", "Grouped"):
        (form_path / "ObjectMethods" / (name + ".4dm")).write_text("AXHP_Event\n")
    (form_path / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    (fixture / "Resources/run-id.txt").write_text(uuid.uuid4().hex)
    before = {str(p.relative_to(fixture)): sha(p) for p in sources.rglob("*") if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="hierarchy-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        body = '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
        if args.diagnostic_plugin:
            body += '$options.plugins:=Folder(' + literal(fixture / "Plugins") + ')\n'
        body += '$result:=Compile project(File(' + literal(project) + '); $options)'
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver, body, 90)
    changed = [name for name, digest in before.items() if sha(fixture / name) != digest]
    passed = compiled.get("success") is True and not compiled.get("errors") and not changed
    report = {"passed": passed, "compiler": compiled, "sources_sha256": before,
        "changed_during_compile": changed, "scope": "Native command and control probe, no bridge adapter acceptance"}
    report["sourceCommit"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["preparerSHA256"] = sha(Path(__file__))
    if args.diagnostic_plugin:
        report["diagnosticNativeSHA256"] = sha(
            fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")
    (BUILD / "hierarchy-probe-compile.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS" if passed else json.dumps(report, indent=2))
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
