#!/usr/bin/env python3
"""Compile ordinary application forms with area-owned bridge integration."""
import argparse
import json
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package
from install_host_methods import main as install

FIXTURE = BUILD / "area-fixture"
TITLE = "AXB area lifecycle"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--no-area", action="store_true", help="Pixel/control baseline with no bridge registration")
    parser.add_argument("--manual", action="store_true", help="Compare the same form using the existing manual lifecycle")
    parser.add_argument("--inherited", action="store_true", help="Inherit the root area from an unchanged shared base")
    parser.add_argument("--configuration", choices=["normal", "absent", "null", "disabled", "invalid", "error"], default="normal")
    parser.add_argument("--no-component", action="store_true", help="Exercise optional component absence")
    parser.add_argument("--no-plugin", action="store_true", help="Exercise optional native plugin absence")
    parser.add_argument("--pixel-focus", action="store_true", help="Start on a button for a caret-free pixel comparison")
    parser.add_argument("--yield-load", action="store_true", help="Yield during ordinary initialization before declaring it complete")
    parser.add_argument("--edit", action="store_true", help="Open the owned root in 4D's Form Editor instead of its dialog")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the fixture")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("area-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Area")
    sources = project.parent / "Sources"
    methods = sources / "Methods"
    if not args.no_component:
        shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    if not args.no_plugin:
        shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("AreaError")
var $window : Integer
var $data; $closed : Object
$data:=New object
For ($window; 1; 2)
 $window:=Open form window("Root"; Plain form window)
 DIALOG("Root"; $data)
 $closed:=New object("areas"; 0; "roots"; 0; "name"; $data.name; "childName"; $data.child.name)
 If (AXB_Areas#Null)
  $closed.areas:=OB Keys(AXB_Areas).length
 End if
 If (AXB_FormRoots#Null)
  $closed.roots:=OB Keys(AXB_FormRoots).length
 End if
 File("/RESOURCES/closed.json").setText(JSON Stringify($closed))
 CLOSE WINDOW($window)
End for
QUIT 4D
'''.replace('For ($window; 1; 2)', 'var $iteration : Integer\nFor ($iteration; 1; 2)'))
    (methods / "AreaError.4dm").write_text('File("/RESOURCES/state.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line; "formula"; Error formula)))\nQUIT 4D\nABORT\n')
    # These are ordinary business methods: no bridge startup/shutdown, no
    # lifecycle forwarding and no changes to their event masks.
    (methods / "AreaRoot.4dm").write_text('''Case of
 : (Form event code=On Load)
  Form.loaded:=True
  Form.name:="After initialization"
  Form.child:=New object("name"; "Child"; "clicks"; 0)
  Form.clicks:=0
  Form.ticks:=0
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  AreaState
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
End case
''')
    (methods / "AreaClick.4dm").write_text('Form.clicks:=Form.clicks+1\n')
    if args.yield_load:
        path = methods / "AreaRoot.4dm"
        path.write_text(path.read_text().replace('  Form.loaded:=True', '  Form.loaded:=False\n  DELAY PROCESS(Current process; 30)').replace('  SET TIMER(6)', '  Form.loaded:=True\n  SET TIMER(6)'))
    if args.pixel_focus:
        path = methods / "AreaRoot.4dm"
        path.write_text(path.read_text().replace('  SET TIMER(6)', '  GOTO OBJECT(*; "Remember")\n  SET TIMER(6)'))
    (methods / "AreaRestart.4dm").write_text('var $reply : Object\n$reply:=AXB_Form("start"; AXB_Configure(Current form name))\n')
    (methods / "AreaState.4dm").write_text('''var $state : Object
$state:=New object("runId"; AreaRun; "compiled"; Is compiled mode; "name"; Form.name; "child"; Form.child; "clicks"; Form.clicks; "ticks"; Form.ticks; "loaded"; Form.loaded)
$state.preparation:=AreaPreparation
$state.areas:=AXB_Area("diagnostics"; ""; "")
$state.diagnostics:=AXB_Form("diagnostics"; New object)
$state.focus:=AXB_Focus
$state.receipt:=AXB_FormContext.receipt
$state.handlerRestored:=Method called on error(ek local)="AreaError"
$state.dependencies:=AXB_Host("info"; New object)
File("/RESOURCES/state.json").setText(JSON Stringify($state))
''')
    (methods / "AXB_Configure.4dm").write_text('''#DECLARE($formName : Text) -> $options : Object
$options:=New object("label"; "Area lifecycle"; "controls"; New object("Name"; New object("label"; "Root name")); "children"; New object("Child"; New object("label"; "Child"; "controls"; New object("Name"; New object("label"; "Name")))))
If (Not(Form.loaded=True))
 $options:=Null
End if
''')
    (methods / "Compiler_Area.4dm").write_text('C_TEXT(AreaRun)\nC_OBJECT(AreaPreparation)\nC_TEXT(AXB_Configure; $1)\nC_OBJECT(AXB_Configure; $0)\n')
    if args.configuration == "absent":
        (methods / "AXB_Configure.4dm").unlink()
        (methods / "Compiler_Area.4dm").write_text('C_TEXT(AreaRun)\nC_OBJECT(AreaPreparation)\n')
        (methods / "AreaRestart.4dm").write_text('var $reply : Object\n$reply:=AXB_Form("start"; New object("label"; "Area lifecycle"))\n')
    elif args.configuration == "null":
        (methods / "AXB_Configure.4dm").write_text('#DECLARE($name : Text) -> $options : Object\n$options:=Null\n')
        (methods / "AreaRestart.4dm").write_text('var $reply : Object\n$reply:=AXB_Form("start"; New object("label"; "Area lifecycle"))\n')
    elif args.configuration == "disabled":
        (methods / "AXB_Configure.4dm").write_text('#DECLARE($name : Text) -> $options : Object\n$options:=New object("enabled"; False)\n')
    elif args.configuration == "invalid":
        (methods / "AXB_Configure.4dm").write_text('#DECLARE($name : Text) -> $options : Object\n$options:=New object("label"; "")\n')
    elif args.configuration == "error":
        (methods / "AXB_Configure.4dm").write_text('#DECLARE($name : Text) -> $options : Object\nvar $missing : Text\n$missing:=File("/RESOURCES/intentional-missing-config").getText()\n$options:=New object\n')
    startup = sources / "DatabaseMethods/onStartup.4dm"
    startup.write_text('AreaRun:=File("/RESOURCES/run.txt").getText()\n' + startup.read_text())
    def save(name, value):
        folder = sources / "Forms" / name
        folder.mkdir(parents=True)
        (folder / "form.4DForm").write_text(json.dumps(value, indent=2) + "\n")
    save("Child", {"width": 240, "height": 80, "pages": [None, {"objects": {
        "Name": {"type": "input", "dataSource": "Form.name", "tooltip": "Name", "left": 10, "top": 10, "width": 210, "height": 25},
        "Remember": {"type": "button", "text": "Remember child", "method": "AreaClick", "events": ["onClick"], "left": 10, "top": 45, "width": 200, "height": 25},
    }}]})
    save("Root", {"width": 430, "height": 250, "windowTitle": TITLE, "method": "AreaRoot", "events": ["onLoad", "onTimer"], "pages": [None, {"objects": {
        "Name": {"type": "input", "dataSource": "Form.name", "left": 20, "top": 20, "width": 380, "height": 25},
        "Remember": {"type": "button", "text": "Remember root", "method": "AreaClick", "events": ["onClick"], "left": 20, "top": 60, "width": 200, "height": 25},
        "Child": {"type": "subform", "detailForm": "Child", "dataSource": "Form.child", "dataSourceTypeHint": "object", "left": 20, "top": 100, "width": 240, "height": 80},
        "Close": {"type": "button", "text": "Close", "action": "cancel", "left": 20, "top": 200, "width": 150, "height": 25},
        "Restart": {"type": "button", "text": "Restart", "method": "AreaRestart", "events": ["onClick"], "left": 200, "top": 200, "width": 150, "height": 25},
    }}]})
    if args.inherited:
        save("Base", {"width": 430, "height": 250, "pages": [None, {"objects": {}}]})
        path = sources / "Forms/Root/form.4DForm"
        form = json.loads(path.read_text())
        form["inheritedForm"] = "Base"
        path.write_text(json.dumps(form, indent=2) + "\n")
    if args.manual:
        path = methods / "AreaRoot.4dm"
        path.write_text(path.read_text().replace('  SET TIMER(6)', '  var $reply : Object\n  $reply:=AXB_Form("start"; AXB_Configure(Current form name))\n  SET TIMER(6)').replace('End case', ' : (Form event code=On Unload)\n  $reply:=AXB_Form("stop"; New object)\nEnd case'))
        path = sources / "Forms/Root/form.4DForm"
        form = json.loads(path.read_text())
        form["events"].append("onUnload")
        path.write_text(json.dumps(form, indent=2) + "\n")
    before = {str(p.relative_to(sources)): json.loads(p.read_text()) for p in sources.rglob("form.4DForm")}
    install(["--project-dir", str(project.parent), *([] if args.no_area else ["--all-forms"])])
    (FIXTURE / "Resources/form-baseline.json").write_text(json.dumps(before, indent=2) + "\n")
    (methods / "AreaPrepareChecks.4dm").write_text('''var $form; $prepared; $again; $invalid : Object
var $original : Text
$form:=New object("method"; "ExistingBusiness"; "events"; New collection("onTimer"); "pages"; New collection(Null; New object("objects"; New object)))
$original:=JSON Stringify($form)
$prepared:=AXB_AreaForm($form; "GeneratedRoot")
AreaPreparation:=New object("generated"; ($prepared.ok=True) && ($prepared.form.pages[0].objects["__AXB_Bridge.GeneratedRoot"].pluginAreaKind="%AXB Area"); "originalUnchanged"; JSON Stringify($form)=$original; "methodUnchanged"; $prepared.form.method=$form.method; "eventsUnchanged"; JSON Stringify($prepared.form.events)=JSON Stringify($form.events))
$again:=AXB_AreaForm($prepared.form; "GeneratedRoot")
AreaPreparation.idempotent:=($again.ok=True) && (JSON Stringify($again.form)=JSON Stringify($prepared.form))
$invalid:=AXB_AreaForm($prepared.form; "DifferentKey")
AreaPreparation.conflict:=($invalid.error="conflictingLifecycleArea") && (New collection($prepared.form).indexOf($invalid.form)=0)
$invalid:=AXB_AreaForm($form; "bad key")
AreaPreparation.invalidKey:=($invalid.error="invalidAreaConfiguration") && (New collection($form).indexOf($invalid.form)=0)
$form.destination:="listScreen"
$invalid:=AXB_AreaForm($form)
AreaPreparation.outputRejected:=($invalid.error="unsupportedAreaDestination") && (New collection($form).indexOf($invalid.form)=0)
OB REMOVE($form; "destination")
$form.inheritedForm:="Base"
$invalid:=AXB_AreaForm($form)
AreaPreparation.inheritedRejected:=($invalid.error="inheritedAreaForm") && (New collection($form).indexOf($invalid.form)=0)
$invalid:=AXB_AreaForm(Null)
AreaPreparation.invalidForm:=$invalid.error="invalidAreaForm"
''')
    startup.write_text(startup.read_text().replace('ON ERR CALL("AreaError")', 'ON ERR CALL("AreaError")\nAreaPrepareChecks'))
    if args.edit:
        startup.write_text('ON ERR CALL("AreaError")\nFORM EDIT("Root")\n')
    (FIXTURE / "Resources/run.txt").write_text(uuid.uuid4().hex)
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="area-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n' +
            ('$options.components:=New collection\n' if args.no_component else f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n') +
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    passed = result.get("success") is True and not result.get("errors")
    (BUILD / "area-compile-report.json").write_text(json.dumps({"passed": passed, "compiler": result, "sources_sha256": hashes, "baseline": args.no_area, "manual": args.manual, "inherited": args.inherited, "configuration": args.configuration, "noComponent": args.no_component, "noPlugin": args.no_plugin}, indent=2) + "\n")
    print("PASS" if passed else "FAIL", "area fixture compilation")
    if not passed:
        print(json.dumps(result, indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
