#!/usr/bin/env python3
"""Compile a synthetic mixed-control form for automatic accessibility discovery."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "discovery-fixture"
TITLE = "AX bridge automatic discovery"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--dynamic", action="store_true", help="Open generated JSON through the generic lifecycle wrapper")
    args = parser.parse_args()
    if args.baseline and args.dynamic:
        parser.error("--baseline and --dynamic are separate fixture configurations")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("discovery-fixture-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Discovery")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for path in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(path, methods / path.name)
    for path in (ROOT / "tests/4d").glob("AXBF_*.4dm"):
        shutil.copy2(path, methods / path.name)
    (methods / "Compiler_AXBF.4dm").write_text('ARRAY TEXT(AXBF_Choices; 0)\nARRAY TEXT(AXBF_Tabs; 0)\nC_TIME(AXBF_Time)\n')
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("AXBF_Error")
var $window : Integer
var $data; $form : Object
$data:=New object("config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
If ($data.config.dynamic)
 $form:=JSON Parse(File("/RESOURCES/discovery.json").getText())
 $form:=AXB_Dynamic($form; $data; New object("label"; "Contact details"); "start").form
 $window:=Open form window($form; Plain form window)
 DIALOG($form; $data)
Else
 $window:=Open form window("Probe"; Plain form window)
 DIALOG("Probe"; $data)
End if
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "events"; $data.events; "dialogOK"; OK)))
CLOSE WINDOW($window)
QUIT 4D
''')
    (FIXTURE / "Resources/launch.json").write_text(json.dumps({"runId": uuid.uuid4().hex, "baseline": args.baseline, "dynamic": args.dynamic}) + "\n")
    objects = {
        "Heading": {"type": "text", "text": "Contact details", "left": 20, "top": 15, "width": 250, "height": 24},
        "NameLabel": {"type": "text", "text": "Name", "left": 20, "top": 52, "width": 100, "height": 24},
        "Name": {"type": "input", "dataSource": "Form.name", "multiline": "no", "left": 130, "top": 50, "width": 300, "height": 26,
                 "events": ["onBeforeDataEntry", "onBeforeKeystroke", "onAfterKeystroke", "onDataChange", "onGettingFocus", "onLosingFocus"]},
        "SecretLabel": {"type": "text", "text": "Password", "left": 20, "top": 90, "width": 100, "height": 24},
        "Secret": {"type": "input", "dataSource": "Form.secret", "fontFamily": "%password", "left": 130, "top": 88, "width": 300, "height": 26,
                   "events": ["onDataChange", "onGettingFocus", "onLosingFocus"]},
        "Allowed": {"type": "checkbox", "text": "", "tooltip": "Send updates", "dataSource": "Form.allowed", "left": 20, "top": 130,
                    "width": 200, "height": 25, "events": ["onClick"]},
        "Email": {"type": "radio", "text": "", "tooltip": "Email", "dataSource": "Form.email", "radioGroup": "ContactChannel", "left": 240, "top": 130,
                  "width": 100, "height": 25, "events": ["onClick"]},
        "Phone": {"type": "radio", "text": "Phone", "dataSource": "Form.phone", "radioGroup": "ContactChannel", "left": 350, "top": 130,
                  "width": 100, "height": 25, "events": ["onClick"]},
        "Country": {"type": "dropdown", "tooltip": "Country", "dataSource": "AXBF_Choices", "left": 20, "top": 175, "width": 190, "height": 26, "events": ["onClick"]},
        "Notes": {"type": "input", "dataSource": "Form.notes", "multiline": "yes", "left": 240, "top": 175, "width": 300, "height": 75,
                  "events": ["onAfterKeystroke", "onDataChange", "onGettingFocus", "onLosingFocus"]},
        "Summary": {"type": "input", "dataSource": "Form.summary", "left": 20, "top": 230, "width": 190, "height": 26, "enterable": False},
        "Amount": {"type": "input", "dataSource": "Form.amount", "dataSourceTypeHint": "real", "left": 20, "top": 320, "width": 150, "height": 26, "events": ["onDataChange"]},
        "DueDate": {"type": "input", "dataSource": "Form.dueDate", "dataSourceTypeHint": "date", "left": 190, "top": 320, "width": 170, "height": 26, "events": ["onDataChange"]},
        "Appointment": {"type": "input", "dataSource": "AXBF_Time", "dataSourceTypeHint": "time", "left": 20, "top": 355, "width": 150, "height": 26, "events": ["onDataChange"]},
        "Save": {"type": "button", "text": "Save contact", "tooltip": "Store the contact details", "left": 20, "top": 280, "width": 160, "height": 28, "events": ["onClick"]},
        "Help": {"type": "button", "text": "", "tooltip": "Explain form", "left": 190, "top": 355, "width": 160, "height": 28, "events": ["onClick"]},
        "Empty": {"type": "text", "text": "", "left": 370, "top": 355, "width": 170, "height": 26},
        "LongTip": {"type": "button", "text": "", "tooltip": "Detailed help " + "x" * 497 + "🎹" + "x" * 80, "left": 380, "top": 320, "width": 160, "height": 28, "events": ["onClick"]},
        "Disabled": {"type": "button", "text": "Disabled action", "left": 190, "top": 280, "width": 160, "height": 28, "enabled": False, "events": ["onClick"]},
        "Hidden": {"type": "button", "text": "Hidden action", "left": 360, "top": 280, "width": 160, "height": 28, "visibility": "hidden", "events": ["onClick"]},
        "Close": {"type": "button", "text": "Close fixture", "left": 380, "top": 400, "width": 160, "height": 28, "action": "cancel", "events": ["onClick"]},
    }
    form_path = sources / "Forms/Probe"
    (form_path / "ObjectMethods").mkdir(parents=True)
    (form_path / "method.4dm").write_text("AXBF_Form\n")
    for name, obj in objects.items():
        if obj.get("events"):
            (form_path / "ObjectMethods" / (name + ".4dm")).write_text("AXBF_Event\n")
            obj["method"] = "ObjectMethods/" + name + ".4dm"
    form = {"windowTitle": TITLE, "width": 560, "height": 450, "method": "method.4dm",
            "events": ["onLoad", "onUnload", "onTimer"], "pages": [None, {"objects": objects}]}
    (form_path / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    form["method"] = "AXBF_Form"
    for obj in objects.values():
        if obj.get("events"):
            obj["method"] = "AXBF_Event"
    (FIXTURE / "Resources/discovery.json").write_text(json.dumps(form, indent=2) + "\n")
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    before["Resources/discovery.json"] = sha(FIXTURE / "Resources/discovery.json")
    with tempfile.TemporaryDirectory(prefix="discovery-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    after = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    after["Resources/discovery.json"] = sha(FIXTURE / "Resources/discovery.json")
    passed = compiled.get("success") is True and not compiled.get("errors") and before == after
    (BUILD / "discovery-compile-report.json").write_text(json.dumps({
        "passed": passed, "sources_sha256": before, "compiler": compiled,
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
        "native_sha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
        "baseline": args.baseline,
        "dynamic": args.dynamic,
    }, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: discovery fixture compilation; {FIXTURE}")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
