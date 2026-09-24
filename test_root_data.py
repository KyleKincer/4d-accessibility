#!/usr/bin/env python3
"""Exercise real dialogs bound directly to entities, shared objects and plain data."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
import doctor
from fixture_desktop import activate_fixture, wait_for_start

TITLE = "AXB root data ownership fixture"


def prepare(server, kind, dynamic_mismatch=False):
    verify_package(PACKAGE)
    fixture = BUILD / ("root-data-" + uuid.uuid4().hex)
    project = project_at(fixture, "RootData")
    sources = fixture / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, fixture / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", fixture / "Plugins/AccessibilityBridge.bundle")
    for source in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(source, methods / source.name)
    table_id, field_id = uuid.uuid4().hex.upper(), uuid.uuid4().hex.upper()
    (sources / "catalog.4DCatalog").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n'
        f'<base name="RootData" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en"><schema name="DEFAULT_SCHEMA"/>'
        f'<table name="AXBRRecord" uuid="{table_id}" id="1"><field name="id" uuid="{field_id}" type="4" id="1"/>'
        f'<field name="name" uuid="{uuid.uuid4().hex.upper()}" type="10" id="2"/><primary_key field_name="id" field_uuid="{field_id}"/></table>'
        f'<index kind="regular" unique_keys="true" name="AXBRRecord_PK" uuid="{uuid.uuid4().hex.upper()}" type="7"><field_ref uuid="{field_id}" name="id"><table_ref uuid="{table_id}" name="AXBRRecord"/></field_ref></index></base>\n')
    code = {
        "Compiler_AXBR": 'C_OBJECT(AXBR_Status; AXBR_Data)\nC_TEXT(AXBR_Scope; $0)\nC_OBJECT(AXBR_Failed; $1)\n',
        "AXBR_Error": 'File("/RESOURCES/error.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n',
        "AXBR_Seed": '''ON ERR CALL("AXBR_Error")
var $record; $saved : Object
$record:=ds.AXBRRecord.new()
$record.id:=1
$record.name:="Original"
$saved:=$record.save()
File("/RESOURCES/seed.json").setText(JSON Stringify($saved))
QUIT 4D
''',
        "AXBR_Failed": '''#DECLARE($failure : Object)
AXBR_Status.failure:=$failure
AXBR_Status.handlerRestored:=Method called on error(ek local)="AXBR_Error"
AXBR_Status.detached:=AXB_FormContext=Null
''',
        "AXBR_Scope": '''#DECLARE() -> $scope : Text
var $invalid : Text
If (AXBR_Status.triggerFailure=True)
 $invalid:=File("/RESOURCES/intentional-missing-test-file").getText()
End if
$scope:="record-1"
''',
        "AXBR_Start": '''var $options : Object
$options:=New object("label"; "Root data"; "scope"; Formula(AXBR_Scope); "onError"; Formula(AXBR_Failed($1)))
$options.controls:=New object("Name"; New object("label"; "Name"))
AXBR_Status.start:=AXB_Form("start"; $options)
''',
        "AXBR_Form": '''var $reply; $context : Object
Case of
 : (Form event code=On Load)
  If (AXBR_Status.kind#"plain")
   AXBR_Status.registration:=AXB_Form("register"; New object("label"; "Child"))
   AXBR_Status.dynamic:=AXB_Dynamic(New object("pages"; New collection(Null)); Form; New object("label"; "Generated"); "start")
  End if
  AXBR_Status.originalLoad:=True
  If (Not(AXBR_Status.dynamicMismatch=True))
   AXBR_Start
  End if
  SET TIMER(6)
 : (Form event code=On Timer)
  AXBR_Status.ticks:=AXBR_Status.ticks+1
  AXBR_Status.name:=Form.name
  AXBR_Status.keys:=OB Keys(Form)
  AXBR_Status.diagnostics:=AXB_Form("diagnostics"; New object)
  $context:=AXB_FormContext
  AXBR_Status.active:=$context#Null
  If (($context#Null) && ($context.state#Null) && (Length($context.state)>0))
   AXBR_Status.windowActive:=JSON Parse($context.state).enabled
   AXBR_Status.focused:=JSON Parse($context.state).nodes.query("focused = :1"; True).extract("id")
  End if
  File("/RESOURCES/state.json").setText(JSON Stringify(AXBR_Status))
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
 : (Form event code=On Unload)
  AXBR_Status.originalUnload:=True
  If (AXBR_Status.dynamicMismatch=True)
   AXB_DynamicClose
  End if
  $reply:=AXB_Form("stop"; New object)
End case
''',
        "AXBR_Click": '''var $reply : Object
Case of
 : (OBJECT Get name(Object current)="Remember")
  AXBR_Status.remembered:=Form.name
 : (OBJECT Get name(Object current)="Change")
  If (OB Is shared(Form))
   Use (Form)
    Form.name:="Handler changed"
   End use
  Else
   Form.name:="Handler changed"
  End if
  AXBR_Status.clicks:=AXBR_Status.clicks+1
 : (OBJECT Get name(Object current)="Restart")
  $reply:=AXB_Form("stop"; New object)
  AXBR_Start
 : (OBJECT Get name(Object current)="Fail")
  AXBR_Status.triggerFailure:=True
End case
''',
    }
    for name, content in code.items():
        (methods / (name + ".4dm")).write_text(content)
    if kind == "instance":
        (sources / "Classes").mkdir()
        (sources / "Classes/RecordModel.4dm").write_text('Class constructor\nThis.id:=1\nThis.name:="Original"\n')
    database = sources / "DatabaseMethods"
    database.mkdir()
    data = {'entity': 'ds.AXBRRecord.get(1)', 'shared': 'New shared object("id"; 1; "name"; "Original")',
            'plain': 'New object("id"; 1; "name"; "Original")', 'instance': 'cs.RecordModel.new()'}[kind]
    (database / "onStartup.4dm").write_text(f'''ON ERR CALL("AXBR_Error")
var $window : Integer
AXBR_Data:={data}
AXBR_Status:=New object("kind"; "{kind}"; "compiled"; Is compiled mode; "ticks"; 0; "clicks"; 0)
$window:=Open form window("Root"; Plain form window)
DIALOG("Root"; AXBR_Data)
CLOSE WINDOW($window)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("keys"; OB Keys(AXBR_Data); "name"; AXBR_Data.name)))
QUIT 4D
''')
    objects = {"Name": {"type": "input", "dataSource": "Form.name", "multiline": "no", "enterable": kind != "shared", "left": 20, "top": 20, "width": 350, "height": 26}}
    for index, name in enumerate(["Remember", "Change", "Restart", "Fail", "Close"]):
        objects[name] = {"type": "button", "text": name, "left": 20 + index * 95, "top": 70, "width": 90, "height": 28,
                         **({"action": "cancel"} if name == "Close" else {"method": "AXBR_Click", "events": ["onClick"]})}
    folder = sources / "Forms/Root"
    folder.mkdir(parents=True)
    (folder / "form.4DForm").write_text(json.dumps({"windowTitle": TITLE, "width": 510, "height": 130, "method": "AXBR_Form",
        "events": ["onLoad", "onUnload", "onTimer"], "pages": [None, {"objects": objects}]}))
    if dynamic_mismatch:
        shutil.copy2(folder / "form.4DForm", fixture / "Resources/root-form.json")
        startup = database / "onStartup.4dm"
        text = startup.read_text().replace('var $window : Integer', 'var $window : Integer\nvar $prepared; $form : Object')
        text = text.replace('$window:=Open form window("Root"; Plain form window)\nDIALOG("Root"; AXBR_Data)',
            'AXBR_Status.dynamicMismatch:=True\n'
            '$prepared:=AXB_Dynamic(JSON Parse(File("/RESOURCES/root-form.json").getText()); New object; New object("label"; "Generated"); "start")\n'
            'AXBR_Status.prepared:=$prepared.ok\n$form:=$prepared.form\n'
            'File("/RESOURCES/prepared.json").setText(JSON Stringify(New object("ok"; $prepared.ok; "error"; $prepared.error; "form"; $form)))\n'
            '$window:=Open form window($form; Plain form window)\nDIALOG($form; AXBR_Data)')
        text = text.replace('"name"; AXBR_Data.name)', '"name"; AXBR_Data.name; "originalUnload"; AXBR_Status.originalUnload)')
        startup.write_text(text)
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    executable = server / "Contents/MacOS" / info["CFBundleExecutable"]
    with (fixture / "seed.log").open("w") as log:
        subprocess.run([str(executable), "--project", str(project), "--data", str(fixture / "synthetic.4dd"), "--create-data",
                        "--headless", "--utility", "--skip-onstartup", "--startup-method", "AXBR_Seed", "--webadmin-auto-start", "false"], stdout=log, stderr=log, check=True, timeout=60)
    assert json.loads((fixture / "Resources/seed.json").read_text(encoding="utf-8-sig"))["success"]
    with tempfile.TemporaryDirectory(dir=BUILD, prefix="root-data-compile-") as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(executable, driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(fixture / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    assert result.get("success") is True and not result.get("errors"), result
    return fixture, project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--kind", choices=["entity", "shared", "plain", "instance"], required=True)
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--dynamic-mismatch", action="store_true", help="Open a generated wrapper with data other than its prepared plain object")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, existing AX permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before testing the owned fixture")
    fixture, project = prepare(args.server.expanduser().resolve(), args.kind, args.dynamic_mismatch)
    report = {"passed": False, "kind": args.kind, "compiled": args.compiled, "dynamicMismatch": args.dynamic_mismatch, "checks": [],
              "fixture": str(fixture), "nativeSHA256": sha(fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "componentSHA256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
              "sourcesSHA256": {str(p.relative_to(fixture)): sha(p) for p in (fixture / "Project/Sources").rglob("*") if p.is_file()}}
    last = {}
    def state():
        nonlocal last
        error = fixture / "Resources/error.json"
        assert not error.exists(), error.read_text() if error.exists() else ""
        try:
            last = json.loads((fixture / "Resources/state.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        return last
    def check(condition, label):
        report["checks"].append({"passed": bool(condition), "name": label})
        print(("PASS: " if condition else "FAIL: ") + label, flush=True)
        assert condition, label
    with (fixture / "desktop.log").open("w") as log:
        process = subprocess.Popen(["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
            "--data", str(fixture / "synthetic.4dd"), "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
    try:
        wait_for_start(process, project, state, BUILD)
        if args.dynamic_mismatch:
            check(state().get("prepared") is True, "generated preparation succeeds on its private plain object")
            check(state()["compiled"] is args.compiled, "requested execution mode is running")
            check(state().get("originalLoad") is True, "wrong-data fallback forwards original On Load")
            ax.wait_for(lambda: state().get("ticks", 0) >= 3, "Original timer stopped after wrong-data fallback")
            check(not state().get("active"), "wrong-data fallback creates no unowned bridge session")
            check(state()["name"] == "Original", "wrong-data fallback preserves application values")
            if args.kind != "plain":
                check(sorted(state()["keys"]) == ["id", "name"], "wrapper adds no attributes to incompatible data")
            else:
                check("axbError" in state()["keys"], "plain data retains the compatibility failure property")
            (fixture / "Resources/close.json").write_text("{}")
            process.wait(timeout=10)
            closed = json.loads((fixture / "Resources/closed.json").read_text(encoding="utf-8-sig"))
            check(process.returncode == 0 and closed.get("originalUnload") is True, "wrong-data fallback forwards unload and closes normally")
            report["passed"] = True
            return
        check(state()["start"].get("ok") is True, "root starts directly on its existing data")
        check(state()["compiled"] is args.compiled, "requested execution mode is running")
        app, window = activate_fixture(process, project, TITLE)
        def group():
            pending = [window]
            while pending:
                node = pending.pop()
                if str(node.read("AXIdentifier") or "").startswith("axb.window."):
                    return node
                pending.extend(node.read("AXChildren") or [])
        root = ax.wait_for(group, "Root tree missing")
        def control(name):
            return ax.wait_for(lambda: next((n for n in root.read("AXChildren") or []
                if name in [n.read("AXTitle"), n.read("AXDescription")]), None), name + " missing")
        # This fixture has an initial native focus target. Activation precedes
        # its 4D focus event; wait for the resulting published state before
        # testing another control. A real intervening focus change must reject.
        ax.wait_for(lambda: state().get("diagnostics", {}).get("ready") and state().get("windowActive") and state().get("focused"), "Initial active focus was not published")
        if args.kind != "plain":
            check(sorted(state()["keys"]) == ["id", "name"], "bridge adds no properties to host data")
            check(state()["registration"].get("error") == "unsupportedRegistrationData", "explicit registration rejects incompatible data before mutation")
            check(state()["dynamic"].get("error") == "unsupportedDynamicData", "generated preparation returns a named error and original form")
        field = control("Name")
        check(field.read("AXValue") == "Original", "bound field is readable")
        if args.kind != "shared":
            check(field.set_text("AX edited 🎻") == 0, "normal editor accepts AXValue")
            ax.wait_for(lambda: field.read("AXValue") == "AX edited 🎻", "Native editor did not receive the text")
            ax.wait_for(lambda: root.read("AXHelp") == "Text entered in the editor; normal validation runs when editing ends", "Text operation did not finish")
            check(control("Remember").press() == 0, "ordinary button commits the existing editor")
            ax.wait_for(lambda: state().get("remembered") == "AX edited 🎻", "Editor did not update its original binding")
            ax.wait_for(lambda: root.read("AXHelp") == "Activation dispatched through the control's normal event path", "Commit button did not finish")
        check(control("Change").press() == 0, "existing business button accepts AXPress")
        ax.wait_for(lambda: state().get("name") == "Handler changed" and state().get("clicks") == 1, "Business handler did not run once")
        ax.wait_for(lambda: root.read("AXHelp") == "Activation dispatched through the control's normal event path", "Business button did not finish")
        previous = root.read("AXIdentifier")
        check(control("Restart").press() == 0, "lifecycle restart uses the existing root")
        root = ax.wait_for(lambda: group() if group() and group().read("AXIdentifier") != previous else None, "Replacement root missing")
        check(field.set_text("stale") != 0 or not field.actions(), "retired field cannot edit the replacement root")
        check(control("Fail").press() == 0, "callback failure trigger is accessible")
        ax.wait_for(lambda: state().get("failure"), "Failure callback missing")
        check(state()["failure"]["error"] == "callbackError" and state()["detached"], "failure detaches only the captured session")
        check(state()["handlerRestored"], "existing error handler is restored")
        ticks = state()["ticks"]
        ax.wait_for(lambda: state()["ticks"] > ticks, "Application timer stopped after bridge failure")
        check(state()["name"] == "Handler changed" and state()["clicks"] == 1, "failure and stale access preserve business state")
        (fixture / "Resources/close.json").write_text("{}")
        process.wait(timeout=10)
        check(process.returncode == 0, "application closes normally after bridge failure")
        closed = json.loads((fixture / "Resources/closed.json").read_text(encoding="utf-8-sig"))
        if args.kind != "plain":
            check(sorted(closed["keys"]) == ["id", "name"], "unload leaves host data unchanged")
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        try:
            state()
            if process.poll() is None:
                report["receipt"] = root.read("AXHelp")
                report["foreground"] = app.read("AXFrontmost")
        except Exception:
            pass
        raise
    finally:
        report["finalState"] = last
        suffix = "-dynamic-mismatch" if args.dynamic_mismatch else ""
        (BUILD / f"root-data-{args.kind}{suffix}-{'compiled' if args.compiled else 'interpreted'}.json").write_text(json.dumps(report, indent=2) + "\n")
        if process.poll() is None:
            (fixture / "Resources/close.json").write_text("{}")
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    main()
