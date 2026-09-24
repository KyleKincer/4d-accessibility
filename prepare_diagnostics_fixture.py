#!/usr/bin/env python3
"""Compile a form whose nested coverage problems can change at runtime."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "diagnostics-fixture"
TITLE = "AXB coverage diagnostics"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing this fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.4D.4DServer"
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("diagnostics-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Diagnostics")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for source in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(source, methods / source.name)
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''var $window : Integer
ON ERR CALL("DiagError")
$window:=Open form window("Root"; Plain form window)
DIALOG("Root"; New object("value"; "root-private"; "details"; New object("value"; "child-private"; "inner"; New object("value"; "nested-private"))))
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "DiagError.4dm").write_text('File("/RESOURCES/status.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (methods / "DiagForm.4dm").write_text('''var $reply; $state; $copy : Object
Case of
 : (Form event code=On Load)
  Form.start:=AXB_Form("start"; New object("label"; "Coverage example"))
  SET TIMER(6)
 : (Form event code=On Timer)
  $state:=New object("ready"; True; "start"; Form.start; "bridgeError"; Form.axbError; "failure"; Form.axbFailure)
  $state.diagnostics:=AXB_Form("diagnostics"; New object)
  $copy:=AXB_Form("diagnostics"; New object)
  $copy.issues.push(New object("object"; "injected"; "reason"; "not real"))
  $state.afterMutation:=AXB_Form("diagnostics"; New object)
  File("/RESOURCES/status.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
  File("/RESOURCES/closed.json").setText(JSON Stringify(AXB_Form("diagnostics"; New object)))
End case
''')
    (methods / "DiagAction.4dm").write_text('''var $options; $reply : Object
Case of
 : (OBJECT Get name(Object current)="Children")
  Form.hideChildren:=Not(Form.hideChildren=True)
  OBJECT SET VISIBLE(*; "Details"; Not(Form.hideChildren))
 : (OBJECT Get name(Object current)="Tabs")
  Form.hideTabs:=Not(Form.hideTabs=True)
  OBJECT SET VISIBLE(*; "UnsupportedTab"; Not(Form.hideTabs))
 : (OBJECT Get name(Object current)="Labels")
  $options:=New object("label"; "Coverage example"; "controls"; New object("Missing"; New object("label"; "Account")))
  $options.children:=New object("Details"; New object("controls"; New object("Missing"; New object("label"; "Contact")); "children"; New object("Inner"; New object("controls"; New object("Missing"; New object("label"; "Nested contact"))))))
  $reply:=AXB_Form("start"; $options)
End case
''')

    def form(name, objects, **properties):
        folder = sources / "Forms" / name
        folder.mkdir(parents=True)
        (folder / "form.4DForm").write_text(json.dumps({"width": 480, "height": 310, "pages": [None, {"objects": objects}], **properties}, indent=2) + "\n")

    field = {"type": "input", "dataSource": "Form.value", "left": 20, "top": 15, "width": 260, "height": 24}
    form("Leaf", {"Missing": field}, height=45)
    form("Child", {"Missing": field, "Inner": {"type": "subform", "detailForm": "Leaf", "dataSource": "Form.inner", "dataSourceTypeHint": "object", "left": 10, "top": 50, "width": 320, "height": 50}}, height=105)
    objects = {"Missing": field, "UnsupportedTab": {"type": "tab", "dataSource": "Form.tab", "labels": ["General", "Notes"], "left": 20, "top": 55, "width": 300, "height": 24},
               "Details": {"type": "subform", "detailForm": "Child", "dataSource": "Form.details", "dataSourceTypeHint": "object", "left": 20, "top": 95, "width": 350, "height": 115}}
    for i, (name, label) in enumerate([("Children", "Toggle details"), ("Tabs", "Toggle tabs"), ("Labels", "Name inputs"), ("Close", "Close")]):
        objects[name] = {"type": "button", "text": label, "left": 10 + 117 * i, "top": 240, "width": 112, "height": 28, "method": "DiagAction", "events": ["onClick"]}
    objects["Close"]["action"] = "cancel"
    form("Root", objects, windowTitle=TITLE, method="DiagForm", events=["onLoad", "onTimer", "onUnload"])
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="diagnostics-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    report = {"passed": compiled.get("success") is True and not compiled.get("errors"), "compiler": compiled, "sources_sha256": hashes,
              "native_sha256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"), "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ")}
    (BUILD / "diagnostics-compile-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "compiler": compiled}))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
