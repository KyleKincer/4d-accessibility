#!/usr/bin/env python3
"""Prepare and compile an optional-host fixture with no AreaList dependency."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package


FIXTURE = BUILD / "host-api-fixture"
TITLE = "AX bridge optional host fixture"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable host fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("host-api-fixture-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "HostAPIProbe")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for path in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(path, methods / path.name)
    for path in (ROOT / "tests/4d").glob("AXBH_*.4dm"):
        shutil.copy2(path, methods / path.name)
    (methods / "Compiler_AXBH.4dm").write_text(
        'C_TEXT(AXBH_Apply; $1; $2)\nC_VARIANT(AXBH_Apply; $3)\nC_OBJECT(AXBH_Apply; $0)\n'
    )
    (methods / "AXBH_Click.4dm").write_text(
        'var $reply : Object\n$reply:=AXBH_Apply(Lowercase(OBJECT Get name(Object current)); "press"; "")\n'
    )
    (methods / "AXBH_NameChanged.4dm").write_text(
        'var $reply : Object\n$reply:=AXBH_Apply("name"; "setValue"; Form.name)\n'
    )
    (methods / "AXBH_AllowedChanged.4dm").write_text(
        'var $reply : Object\n$reply:=AXBH_Apply("allowed"; "humanChange"; "")\n'
    )
    (methods / "AXBH_Error.4dm").write_text(
        'File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n'
    )
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text('''ON ERR CALL("AXBH_Error")
var $config; $data; $form : Object
var $window : Integer
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
$data:=New object("runId"; $config.runId; "dynamic"; $config.dynamic)
If ($config.dynamic)
 $form:=JSON Parse(File("/RESOURCES/dynamic-form.json").getText())
 $window:=Open form window($form; Plain form window)
 DIALOG($form; $data)
Else
 $window:=Open form window("Probe"; Plain form window)
 DIALOG("Probe"; $data)
End if
CLOSE WINDOW($window)
QUIT 4D
''')
    (FIXTURE / "Resources/launch.json").write_text(json.dumps({"runId": "manual", "dynamic": False}) + "\n")
    objects = {
        "Name": {"type": "input", "dataSource": "Form.name", "left": 25, "top": 25, "width": 470, "height": 26,
                 "events": ["onDataChange"], "method": "AXBH_NameChanged"},
        "Allowed": {"type": "checkbox", "text": "Allow submit", "dataSource": "Form.allowed", "left": 25, "top": 65,
                    "width": 250, "height": 26, "events": ["onClick"], "method": "AXBH_AllowedChanged"},
        "Status": {"type": "input", "dataSource": "Form.message", "left": 25, "top": 165, "width": 470,
                   "height": 55, "enterable": False, "multiline": True},
    }
    for name, title, x, y in (("Submit", "Submit", 25, 110), ("Hide", "Toggle name", 185, 110),
                              ("Restart", "Restart bridge", 345, 110), ("Close", "Close fixture", 345, 245)):
        objects[name] = {"type": "button", "text": title, "left": x, "top": y, "width": 150, "height": 28,
                         "events": ["onClick"], "method": "AXBH_Click"}
    form = {"windowTitle": TITLE, "width": 520, "height": 300, "method": "AXBH_Form",
            "events": ["onLoad", "onUnload", "onTimer"], "pages": [None, {"objects": objects}]}
    (FIXTURE / "Resources/dynamic-form.json").write_text(json.dumps(form, indent=2) + "\n")
    form_path = sources / "Forms/Probe"
    (form_path / "ObjectMethods").mkdir(parents=True)
    (form_path / "method.4dm").write_text("AXBH_Form\n")
    form["method"] = "method.4dm"
    for name, obj in objects.items():
        if "method" in obj:
            (form_path / "ObjectMethods" / f"{name}.4dm").write_text(obj["method"] + "\n")
            obj["method"] = f"ObjectMethods/{name}.4dm"
    (form_path / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    before["Resources/dynamic-form.json"] = sha(FIXTURE / "Resources/dynamic-form.json")
    with tempfile.TemporaryDirectory(prefix="host-api-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    after = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    after["Resources/dynamic-form.json"] = sha(FIXTURE / "Resources/dynamic-form.json")
    passed = compiled.get("success") is True and not compiled.get("errors") and before == after
    (BUILD / "host-api-compile-report.json").write_text(json.dumps({
        "passed": passed, "sources_sha256": before, "compiler": compiled,
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
        "scope": "Static and JSON-generated basic-control fixture; synthetic data only",
    }, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: optional host fixture compilation; {FIXTURE}")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
