#!/usr/bin/env python3
"""Prepare ordinary offscreen controls in repeated and nested page subforms."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "scroll-fixture"
TITLE = "AX bridge scrollable forms"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing this disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("scroll-fixture-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "ScrollFixture")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for path in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(path, methods / path.name)
    for path in (ROOT / "tests/4d").glob("AXBS_*.4dm"):
        shutil.copy2(path, methods / path.name)
    (methods / "Compiler_AXBS.4dm").write_text("C_OBJECT(AXBS_Read; $0)\nC_OBJECT(AXBS_PanelRead; $0)\n")
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text('''ON ERR CALL("AXBS_Error")
var $window : Integer
var $data : Object
$data:=New object("left"; New object("tag"; "Left"); "right"; New object("tag"; "Right"); "panel"; New object("inner"; New object("tag"; "Nested")))
$data.runId:=JSON Parse(File("/RESOURCES/launch.json").getText()).runId
$window:=Open form window("Root"; Plain form window)
DIALOG("Root"; $data)
CLOSE WINDOW($window)
QUIT 4D
''')

    def save(name, form):
        directory = sources / "Forms" / name
        directory.mkdir(parents=True)
        (directory / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")

    save("Child", {"width": 850, "height": 780, "method": "AXBS_Child", "events": ["onLoad"], "pages": [None, {"objects": {
        "FirstLabel": {"type": "text", "text": "First", "left": 10, "top": 15, "width": 60, "height": 24},
        "First": {"type": "input", "dataSource": "Form.first", "multiline": "no", "left": 80, "top": 15, "width": 240, "height": 26},
        "LastLabel": {"type": "text", "text": "Last", "left": 510, "top": 620, "width": 60, "height": 24},
        "Last": {"type": "input", "dataSource": "Form.last", "multiline": "no", "left": 580, "top": 620, "width": 240, "height": 26, "method": "AXBS_ChildEvent", "events": ["onDataChange"]},
        "Remember": {"type": "button", "text": "Remember last", "left": 580, "top": 665, "width": 180, "height": 28, "focusable": False, "method": "AXBS_ChildEvent", "events": ["onClick"]},
        "Wide": {"type": "button", "text": "Wide action", "left": 10, "top": 725, "width": 810, "height": 28, "focusable": False, "method": "AXBS_ChildEvent", "events": ["onClick"]},
    }}]})
    save("Panel", {"width": 850, "height": 720, "pages": [None, {"objects": {
        "Nested": {"type": "subform", "detailForm": "Child", "dataSource": "Form.inner", "left": 450, "top": 400, "width": 370, "height": 220, "scrollbarVertical": "visible", "scrollbarHorizontal": "visible"},
    }}]})
    objects = {}
    for name, x, y, form in [("Left", 20, 20, "Child"), ("Right", 420, 20, "Child"), ("Panel", 20, 280, "Panel")]:
        objects[name] = {"type": "subform", "detailForm": form, "dataSource": "Form." + name.lower(), "left": x, "top": y, "width": 370, "height": 220, "scrollbarVertical": "visible", "scrollbarHorizontal": "visible"}
    for i, (name, title) in enumerate([("Reset", "Reset scroll"), ("Hide", "Hide left"), ("Replace", "Replace left"), ("Record", "Change record"), ("Disable", "Disable right"), ("Close", "Close fixture")]):
        objects[name] = {"type": "button", "text": title, "left": 420, "top": 280 + i * 40, "width": 210, "height": 28, "method": "AXBS_Click", "events": ["onClick"]}
    objects["Close"]["action"] = "cancel"
    objects["Collapse"] = {"type": "button", "text": "Collapse left", "left": 650, "top": 280, "width": 150, "height": 28, "method": "AXBS_Click", "events": ["onClick"]}
    objects["ClipWindow"] = {"type": "button", "text": "Clip window", "left": 650, "top": 320, "width": 150, "height": 28, "method": "AXBS_Click", "events": ["onClick"]}
    objects["RestoreWindow"] = {"type": "button", "text": "Restore window", "left": 20, "top": 250, "width": 180, "height": 24, "method": "AXBS_Click", "events": ["onClick"]}
    save("Root", {"windowTitle": TITLE, "width": 830, "height": 550, "method": "AXBS_Form", "events": ["onLoad", "onTimer", "onUnload"], "pages": [None, {"objects": objects}]})
    (FIXTURE / "Resources/launch.json").write_text(json.dumps({"runId": uuid.uuid4().hex}) + "\n")
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="scroll-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    passed = compiled.get("success") is True and not compiled.get("errors")
    (BUILD / "scroll-compile-report.json").write_text(json.dumps({"passed": passed, "compiler": compiled, "sources_sha256": hashes,
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"), "native_sha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: scrollable form fixture compilation")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
