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
    parser.add_argument("--nonblocking", action="store_true", help="Probe duplicate-named root/child editors in a nonblocking root")
    parser.add_argument("--generated", action="store_true", help="Use generated root and child JSON in the nonblocking focus probe")
    parser.add_argument("--initial-focus", choices=("button", "field", "explicit-field"), default="button", help="Initial native focus for the nonblocking probe")
    parser.add_argument("--root-only-area", action="store_true", help="Probe a generated root with an unchanged named child and no child lifecycle area")
    parser.add_argument("--compound", action="store_true", help="Probe early observed focus and replacement of a duplicate-named child in a generated nonblocking form")
    parser.add_argument("--pointer-focus", action="store_true", help="Use unique native dynamic variables and an unobserved child in the compound probe")
    parser.add_argument("--early-manual-start", action="store_true", help="Verify pending observer transfer to a root registered by its existing On Load method")
    parser.add_argument("--shared-pointer-guard", action="store_true", help="Verify duplicate native pointers with a missing child observer reject ambiguous editor focus")
    parser.add_argument("--close-during-load", action="store_true", help="Close during business initialization before deferred area registration")
    args = parser.parse_args()
    if args.compound:
        args.nonblocking = True
        args.generated = True
        args.root_only_area = True
        args.initial_focus = "explicit-field"
    if (args.pointer_focus or args.early_manual_start or args.shared_pointer_guard) and not args.compound:
        parser.error("--pointer-focus and --early-manual-start require --compound")
    if args.close_during_load and (args.nonblocking or args.no_area or args.manual or args.edit or args.yield_load):
        parser.error("--close-during-load requires the ordinary area-owned dialog")
    if args.root_only_area and not (args.nonblocking and args.generated):
        parser.error("--root-only-area currently requires --nonblocking --generated")
    if args.generated and not args.nonblocking:
        parser.error("--generated currently requires the nonblocking focus probe")
    if args.nonblocking and (args.no_area or args.manual or args.inherited or args.configuration != "normal" or args.no_component or args.no_plugin or args.edit):
        parser.error("--nonblocking probes the normal matching-package root and child")
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
 $closed:=New object("compiled"; Is compiled mode; "areas"; 0; "roots"; 0; "name"; $data.name; "childName"; $data.child.name)
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
    if args.nonblocking:
        startup = sources / "DatabaseMethods/onStartup.4dm"
        startup.write_text('ON ERR CALL("AreaError")\nvar $window : Integer\nvar $data : Object\n$data:=New object\n$window:=Open form window("Root"; Plain form window)\nDIALOG("Root"; $data; *)\n')
        path = methods / "AreaRoot.4dm"
        path.write_text(path.read_text().replace('End case', ' : (Form event code=On Unload)\n  SET TIMER(0)\n  CALL WORKER(Current process; "AreaFinish"; Form)\nEnd case'))
        (methods / "AreaFinish.4dm").write_text('''#DECLARE($data : Object)
var $closed : Object
$closed:=New object("areas"; 0; "roots"; 0; "name"; $data.name; "childName"; $data.child.name)
If (AXB_Areas#Null)
 $closed.areas:=OB Keys(AXB_Areas).length
End if
If (AXB_FormRoots#Null)
 $closed.roots:=OB Keys(AXB_FormRoots).length
End if
File("/RESOURCES/closed.json").setText(JSON Stringify($closed))
QUIT 4D
''')
    (methods / "AreaClick.4dm").write_text('Form.clicks:=Form.clicks+1\n')
    if args.close_during_load:
        path = methods / "AreaRoot.4dm"
        path.write_text(path.read_text().replace('  SET TIMER(6)', '  SET TIMER(6)\n  CANCEL'))
    if args.yield_load:
        path = methods / "AreaRoot.4dm"
        path.write_text(path.read_text().replace('  Form.loaded:=True', '  Form.loaded:=False\n  DELAY PROCESS(Current process; 30)').replace('  SET TIMER(6)', '  Form.loaded:=True\n  SET TIMER(6)'))
    if args.pixel_focus or (args.nonblocking and args.initial_focus != "field"):
        path = methods / "AreaRoot.4dm"
        focus_name = "Name" if args.nonblocking and args.initial_focus == "explicit-field" else "Remember"
        focus_setup = f'  SET TIMER(6)\n  GOTO OBJECT(*; "{focus_name}")' if args.initial_focus == "explicit-field" else f'  GOTO OBJECT(*; "{focus_name}")\n  SET TIMER(6)'
        path.write_text(path.read_text().replace('  SET TIMER(6)', focus_setup))
    (methods / "AreaRestart.4dm").write_text('var $reply : Object\n$reply:=AXB_Form("start"; AXB_Configure(Current form name))\n')
    (methods / "AreaState.4dm").write_text('''var $state : Object
$state:=New object("runId"; AreaRun; "compiled"; Is compiled mode; "name"; Form.name; "child"; Form.child; "clicks"; Form.clicks; "ticks"; Form.ticks; "loaded"; Form.loaded)
$state.nativeFocus:=AXB_Host("focus"; New object)
$state.focusedObject:=OBJECT Get name(Object with focus)
$state.editing:=Is editing text
$state.replaced:=Form.replaced
$state.restarted:=Form.restarted
$state.preparation:=AreaPreparation
$state.areas:=AXB_Area("diagnostics"; ""; "")
$state.diagnostics:=AXB_Form("diagnostics"; New object)
$state.focus:=AXB_Focus
$state.observedID:=AXB_FormRoots[String(Current form window)].observedFocus.id
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
    if args.compound:
        configuration = methods / "AXB_Configure.4dm"
        configuration.write_text(configuration.read_text().replace('If (Not(Form.loaded=True))', '$options.controls.Status:=New object("label"; "Status")\nIf (Not(Form.loaded=True))'))
        observer = 'var $observed : Object\n$observed:=AXB_Form("event"; New object)\n'
        path = methods / "AreaRoot.4dm"
        path.write_text(observer + path.read_text().replace('  AreaState', '''  If (File("/RESOURCES/replace.json").exists)
   File("/RESOURCES/replace.json").delete()
   var $child; $prepared; $invalidated : Object
   $child:=JSON Parse(File("/RESOURCES/Child.json").getText())
   $prepared:=AXB_AreaForm($child; "Child")
   $invalidated:=AXB_Form("invalidate"; New object("subform"; "Child"))
   $child:=$prepared.form
   OBJECT SET SUBFORM(*; "Child"; $child)
   Form.replaced:=True
  End if
  If (File("/RESOURCES/restart.json").exists)
   File("/RESOURCES/restart.json").delete()
   AreaRestart
   Form.restarted:=True
  End if
  AreaState'''))
        (methods / "AreaChild.4dm").write_text(observer)
        if args.early_manual_start:
            path.write_text(path.read_text().replace('  GOTO OBJECT(*; "Name")', '  var $started : Object\n  $started:=AXB_Form("start"; AXB_Configure(Current form name))\n  GOTO OBJECT(*; "Name")').replace(' : (Form event code=On Unload)', ' : (Form event code=On Unload)\n  $started:=AXB_Form("stop"; New object)'))
        if args.pointer_focus or args.shared_pointer_guard:
            path.write_text(path.read_text().replace('  GOTO OBJECT(*; "Name")', '  var $name : Pointer\n  $name:=OBJECT Get pointer(Object named; "Name")\n  $name->:=Form.name\n  GOTO OBJECT(*; "Name")'))
            (methods / "AreaChild.4dm").write_text('If (Form event code=On Load)\n var $name : Pointer\n $name:=OBJECT Get pointer(Object named; "Name")\n $name->:="Child"\nEnd if\n')
            (methods / "AreaClick.4dm").write_text('var $name : Pointer\n$name:=OBJECT Get pointer(Object named; "Name")\nForm.name:=$name->\nForm.clicks:=Form.clicks+1\n')
            if args.shared_pointer_guard:
                compiler = methods / "Compiler_Area.4dm"
                compiler.write_text(compiler.read_text() + 'C_TEXT(AreaSharedName)\n')
                (methods / "AreaFocusName.4dm").write_text('GOTO OBJECT(*; "Name")\n')
                path = methods / "AreaClick.4dm"
                path.write_text(path.read_text() + 'EXECUTE METHOD IN SUBFORM("Child"; "AreaFocusName")\n')
        for name in ("Root", "Child"):
            path = sources / "Forms" / name / "form.4DForm"
            form = json.loads(path.read_text())
            objects = form["pages"][1]["objects"]
            if args.pointer_focus:
                objects["Name"].update(dataSource="", dataSourceTypeHint="text")
            if args.shared_pointer_guard:
                objects["Name"].update(dataSource="AreaSharedName", dataSourceTypeHint="text")
            if name == "Root":
                form["width"] = 450
                objects["Name"]["width"] = 300
                objects["Remember"]["width"] = 100
                objects["Status"] = {"type": "input", "dataSource": "Form.name", "enterable": False, "tooltip": "Status", "left": 20, "top": 100, "width": 380, "height": 25}
                objects["Child"].update(top=145, height=90)
                objects.pop("Close")
                objects.pop("Restart")
            else:
                form.update(method="AreaChild", events=["onLoad"], height=90)
                objects["Remember"].update(top=50, width=120)
            path.write_text(json.dumps(form, indent=2) + "\n")
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
    if args.nonblocking:
        compiler = methods / "Compiler_Area.4dm"
        compiler.write_text(compiler.read_text() + 'C_OBJECT(AreaFinish; $1)\n')
        path = sources / "Forms/Root/form.4DForm"
        form = json.loads(path.read_text())
        form["events"].append("onUnload")
        path.write_text(json.dumps(form, indent=2) + "\n")
    before = {str(p.relative_to(sources)): json.loads(p.read_text()) for p in sources.rglob("form.4DForm")}
    install(["--project-dir", str(project.parent), *([] if args.no_area else (["--form", "Root"] if args.root_only_area else ["--all-forms"]))])
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
    if args.generated:
        for name in ("Root", "Child"):
            original = before[f"Forms/{name}/form.4DForm"]
            (FIXTURE / "Resources" / (name + ".json")).write_text(json.dumps(original, indent=2) + "\n")
        startup.write_text(startup.read_text().replace('var $data : Object', 'var $data; $formObject; $prepared : Object').replace(
            '$window:=Open form window("Root"; Plain form window)',
            '$formObject:=JSON Parse(File("/RESOURCES/Root.json").getText())\n$prepared:=AXB_AreaForm($formObject; "Root")\nAreaPreparation.generatedLiveRoot:=$prepared.ok=True\n$formObject:=$prepared.form\n$window:=Open form window($formObject; Plain form window)').replace(
            'DIALOG("Root"; $data; *)', 'DIALOG($formObject; $data; *)'))
        if not args.root_only_area:
            path = methods / "AreaRoot.4dm"
            path.write_text(path.read_text().replace('  Form.clicks:=0', '  var $child; $prepared : Object\n  $child:=JSON Parse(File("/RESOURCES/Child.json").getText())\n  $prepared:=AXB_AreaForm($child; "Child")\n  AreaPreparation.generatedLiveChild:=$prepared.ok=True\n  $child:=$prepared.form\n  OBJECT SET SUBFORM(*; "Child"; $child)\n  Form.clicks:=0'))
    if args.edit:
        startup.write_text('ON ERR CALL("AreaError")\nFORM EDIT("Root")\n')
    (FIXTURE / "Resources/run.txt").write_text(uuid.uuid4().hex)
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    if args.generated:
        hashes.update({str(p.relative_to(FIXTURE)): sha(p) for p in (FIXTURE / "Resources").glob("*.json")})
    with tempfile.TemporaryDirectory(prefix="area-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n' +
            ('$options.components:=New collection\n' if args.no_component else f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n') +
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    passed = result.get("success") is True and not result.get("errors")
    (BUILD / "area-compile-report.json").write_text(json.dumps({"passed": passed, "compiler": result, "sources_sha256": hashes, "native_sha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"), "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"), "baseline": args.no_area, "manual": args.manual, "inherited": args.inherited, "configuration": args.configuration, "noComponent": args.no_component, "noPlugin": args.no_plugin, "nonblocking": args.nonblocking, "generated": args.generated, "initialFocus": args.initial_focus, "rootOnlyArea": args.root_only_area, "compound": args.compound, "pointerFocus": args.pointer_focus, "earlyManualStart": args.early_manual_start, "sharedPointerGuard": args.shared_pointer_guard, "closeDuringLoad": args.close_during_load}, indent=2) + "\n")
    print("PASS" if passed else "FAIL", "area fixture compilation")
    if not passed:
        print(json.dumps(result, indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
