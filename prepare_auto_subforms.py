#!/usr/bin/env python3
"""Prepare isolated automatic children, including shared and implicit bindings."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "auto-subforms"
TITLE = "AX bridge automatic child forms"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--implicit", action="store_true", help="Open the root dialog without a data argument")
    parser.add_argument("--shared-focus", action="store_true", help="Share non-text bindings and observe focus in the reusable child form")
    parser.add_argument("--scroll-focus", action="store_true", help="Place shared controls outside scrolling child viewports")
    parser.add_argument("--no-focus-observer", action="store_true", help="Negative control for shared-binding focus")
    parser.add_argument("--generated-children", action="store_true", help="Replace child definitions with JSON forms; keep automatic ownership and shared data")
    args = parser.parse_args()
    if (args.scroll_focus or args.no_focus_observer) and not args.shared_focus:
        parser.error("Focus variants require --shared-focus")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("auto-subforms-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "AutoSubforms")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    for path in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(path, methods / path.name)
    for path in (ROOT / "tests/4d").glob("AXBC_*.4dm"):
        shutil.copy2(path, methods / path.name)
    (methods / "Compiler_AXBC.4dm").write_text("C_OBJECT(AXBC_Config; AXBC_RootStart)\nC_COLLECTION(AXBC_Events)\nC_TEXT(AXBC_Scalar; AXBC_UnboundName)\nC_LONGINT(AXBC_UnboundClicks)\nC_OBJECT(AXBC_Read; $0)\nC_OBJECT(AXBC_Nested; $0)\n")
    if args.shared_focus:
        with (methods / "Compiler_AXBC.4dm").open("a") as stream:
            stream.write("C_LONGINT(AXBC_SharedButton)\n")
        child_method = methods / "AXBC_Child.4dm"
        if not args.no_focus_observer:
            child_method.write_text('AXB_Form("event"; New object)\n' + child_method.read_text().replace(
                "// Ordinary application initialization. There are no bridge hooks in children.\n", ""))
        with (methods / "AXBC_Read.4dm").open("a") as stream:
            stream.write('var $button : Pointer\n$button:=OBJECT Get pointer(Object named; "Remember")\n'
                         '$result.sharedButtonBinding:=($button=->AXBC_SharedButton)\n')
        with (methods / "AXBC_Event.4dm").open("a") as stream:
            stream.write('''If (($name="Name") & (Form event code=On Data Change) && (Form.name="Redirect shared focus"))
 CALL SUBFORM CONTAINER(-915)
End if
''')
        (methods / "AXBC_Redirect.4dm").write_text('''If (Form event code=-915)
 EXECUTE METHOD IN SUBFORM("Right"; "AXBC_FocusName")
End if
''')
        (methods / "AXBC_FocusName.4dm").write_text('GOTO OBJECT(*; "Name")\n')
    (methods / "AXBC_Error.4dm").write_text('File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("AXBC_Error")
var $window : Integer
AXBC_Config:=JSON Parse(File("/RESOURCES/launch.json").getText())
$window:=Open form window("Parent"; Plain form window)
If (AXBC_Config.implicit)
 DIALOG("Parent")
Else
 DIALOG("Parent"; New object)
End if
CLOSE WINDOW($window)
QUIT 4D
''')

    def save(name, form):
        folder = sources / "Forms" / name
        folder.mkdir(parents=True)
        (folder / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")

    child = {"width": 280, "height": 120, "method": "AXBC_Child", "events": ["onLoad"], "pages": [None, {"objects": {
        "Label": {"type": "text", "text": "Name", "left": 10, "top": 12, "width": 50, "height": 24},
        "Name": {"type": "input", "multiline": "no", "dataSource": "Form.name", "left": 70, "top": 10, "width": 190, "height": 26, "events": ["onDataChange"], "method": "AXBC_Event"},
        "Remember": {"type": "button", "text": "Remember", "left": 70, "top": 55, "width": 130, "height": 28, "events": ["onClick"], "method": "AXBC_Event"},
    }}]}
    if args.shared_focus:
        child["pages"][1]["objects"]["Remember"]["dataSource"] = "AXBC_SharedButton"
        child["pages"][1]["objects"]["Remember"]["focusable"] = True
    if args.scroll_focus:
        child["height"] = 420
        for name in ["Label", "Name", "Remember"]:
            child["pages"][1]["objects"][name]["top"] += 280
    save("Child", child)
    process_child = json.loads(json.dumps(child))
    process_child["pages"][1]["objects"]["Name"]["dataSource"] = "AXBC_UnboundName"
    save("ChildProcess", process_child)
    nested = {"type": "subform", "detailForm": "Child", "dataSource": "Form.inner", "dataSourceTypeHint": "object", "left": 10, "top": 10, "width": 280, "height": 120}
    if args.scroll_focus:
        nested["scrollbarVertical"] = "visible"
    save("Panel", {"width": 300, "height": 140, "pages": [None, {"objects": {"Nested": nested}}]})
    objects = {}
    for name, x, y, binding, hint, definition in [
        ("Left", 20, 40, "Form.left", "object", "Child"),
        ("Right", 340, 40, "Form.right", "object", "Child"),
        ("Scalar", 20, 200, "AXBC_Scalar", "text", "Child"),
        ("Unbound", 340, 200, "", "object", "ChildProcess"),
        ("Panel", 20, 360, "Form.panel", "object", "Panel"),
    ]:
        objects[name] = {"type": "subform", "detailForm": definition, "dataSource": binding, "dataSourceTypeHint": hint, "left": x, "top": y, "width": 300, "height": 140}
        if args.shared_focus and name == "Left":
            objects[name]["method"] = "AXBC_Redirect"
        if args.scroll_focus:
            objects[name]["scrollbarVertical"] = "visible"
    for i, (name, label) in enumerate([( "Replace", "Replace left"), ("Hide", "Hide left"), ("Disable", "Disable right"), ("Record", "Change record"), ("Close", "Close fixture")]):
        objects[name] = {"type": "button", "text": label, "left": 350, "top": 350 + i * 40, "width": 200, "height": 28, "events": ["onClick"], "method": "AXBC_Event"}
    objects["Close"]["action"] = "cancel"
    objects["OpenShared"] = {"type": "button", "text": "Open shared-data window", "left": 20, "top": 530, "width": 290, "height": 28, "events": ["onClick"], "method": "AXBC_OpenRoot"}
    save("Parent", {"windowTitle": TITLE, "width": 660, "height": 570, "method": "AXBC_Parent", "events": ["onLoad", "onUnload", "onTimer"], "pages": [None, {"objects": objects}]})
    save("SharedRoot", {"windowTitle": "AX bridge shared-data root", "width": 400, "height": 180,
        "method": "AXBC_RootForm", "events": ["onLoad", "onUnload", "onTimer"], "pages": [None, {"objects": {
        "Name": {"type": "input", "dataSource": "Form.shared.name", "multiline": "no", "left": 20, "top": 20, "width": 340, "height": 28},
        "RememberRoot": {"type": "button", "text": "Remember shared value", "left": 20, "top": 65, "width": 250, "height": 28, "events": ["onClick"], "method": "AXBC_RootForm"},
        "CloseRoot": {"type": "button", "text": "Close shared window", "left": 20, "top": 110, "width": 250, "height": 28, "action": "cancel"},
    }}]})
    if args.generated_children:
        # Automatic JSON children use the same parent configuration and data;
        # they need neither explicit providers nor AXB_Dynamic registration.
        for name in ("Child", "ChildProcess", "Panel"):
            shutil.copy2(sources / f"Forms/{name}/form.4DForm", FIXTURE / f"Resources/{name}.json")
        parent = methods / "AXBC_Parent.4dm"
        setup = '\n'.join(f'  $generated:=JSON Parse(File("/RESOURCES/{definition}.json").getText())\n  OBJECT SET SUBFORM(*; "{container}"; $generated)'
                          for container, definition in [("Left", "Child"), ("Right", "Child"), ("Scalar", "Child"), ("Unbound", "ChildProcess"), ("Panel", "Panel")])
        setup += '\n  EXECUTE METHOD IN SUBFORM("Panel"; "AXBC_GenerateNested")\n'
        parent.write_text(parent.read_text().replace('var $reply; $options : Object', 'var $reply; $options; $generated : Object').replace('  Form.start:=', setup + '  Form.start:='))
        (methods / "AXBC_GenerateNested.4dm").write_text('var $generated : Object\n$generated:=JSON Parse(File("/RESOURCES/Child.json").getText())\nOBJECT SET SUBFORM(*; "Nested"; $generated)\n')
        event = methods / "AXBC_Event.4dm"
        event.write_text(event.read_text().replace('var $reply : Object', 'var $reply; $generated : Object').replace('OBJECT SET SUBFORM(*; "Left"; "Child")', '$generated:=JSON Parse(File("/RESOURCES/Child.json").getText())\n  OBJECT SET SUBFORM(*; "Left"; $generated)'))
    (FIXTURE / "Resources/launch.json").write_text(json.dumps({"runId": uuid.uuid4().hex, "implicit": args.implicit, "sharedFocus": args.shared_focus, "scrollFocus": args.scroll_focus, "focusObserver": not args.no_focus_observer, "generatedChildren": args.generated_children}) + "\n")
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="auto-child-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    after = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    passed = compiled.get("success") is True and not compiled.get("errors") and before == after
    (BUILD / "auto-subforms-compile-report.json").write_text(json.dumps({"passed": passed, "sources_sha256": before, "compiler": compiled,
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"), "native_sha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}, indent=2) + "\n")
    print("PASS" if passed else "FAIL", "automatic child fixture compilation")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
