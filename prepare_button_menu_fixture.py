"""Build an area-owned synthetic form with buttons that have pop-up menus.

Export is a bevel button with a linked menu; Search is a custom button with a separated
menu and its own On Clicked; Plain is a regular button with a separated menu, which draws
no arrow. Each object method records its events, and the menu it shows records the
item chosen, so a test can tell which of the application's own events ran.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / 'button-menu-fixture'
TITLE = 'AX bridge button menus'

STARTUP = '''ON ERR CALL("AXBM_Error")
var $window : Integer
var $data : Object
$data:=New object("config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
File("/RESOURCES/events.jsonl").delete()
$window:=Open form window("Buttons"; Plain form window)
DIALOG("Buttons"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "failure"; $data.axbFailure)))
QUIT 4D
'''

# Shows the button's menu on On Alternative Click and records each event and the choice.
EVENT = '''var $name; $menu; $choice : Text
var $items : Collection
var $item : Text
var $diagnostics : Object
$name:=OBJECT Get name(Object current)
If (Form.diagnosed=Null)
 // The bridge's coverage report, once, when the bridge is installed.
 Form.diagnosed:=True
 ON ERR CALL("AXBM_Ignore")
 EXECUTE METHOD("AXB_Form"; $diagnostics; "diagnostics"; New object)
 ON ERR CALL("AXBM_Error")
 AXBM_Log(New object("diagnostics"; $diagnostics))
End if
AXBM_Log(New object("object"; $name; "event"; Form event code))
If (Form event code=On Alternative Click)
 $items:=New object("Export"; New collection("PDF"; "CSV"); "Search"; New collection("Exact"; "Fuzzy"); "Plain"; New collection("One"; "Two"))[$name]
 $menu:=Create menu
 For each ($item; $items)
  APPEND MENU ITEM($menu; $item)
  SET MENU ITEM PARAMETER($menu; -1; Lowercase($item))
 End for each
 $choice:=Dynamic pop up menu($menu)
 RELEASE MENU($menu)
 AXBM_Log(New object("object"; $name; "choice"; $choice))
End if
'''

LOG = '''#DECLARE($entry : Object)
var $file : 4D.File
var $previous : Text
$file:=File("/RESOURCES/events.jsonl")
If ($file.exists)
 $previous:=$file.getText()
End if
$entry.runId:=Form.config.runId
$entry.compiled:=Is compiled mode
$file.setText($previous+JSON Stringify($entry)+Char(10))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--no-bridge', action='store_true', help='Native baseline with no plugin, component or bridge helpers')
    args = parser.parse_args()
    for name in ('4D', '4D Server'):
        if subprocess.run(['pgrep', '-x', name], capture_output=True).returncode == 0:
            parser.error('Close 4D before preparing this sequential fixture')
    verify_package(PACKAGE)
    if FIXTURE.exists():
        shutil.rmtree(FIXTURE)
    project = project_at(FIXTURE, 'ButtonMenus')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
        for path in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
            shutil.copy2(path, methods / path.name)
    (methods / 'AXBM_Error.4dm').write_text('File("/RESOURCES/errors.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\n')
    (methods / 'AXBM_Log.4dm').write_text(LOG)
    (methods / 'Compiler_ButtonMenus.4dm').write_text('C_OBJECT(AXBM_Log; $1)\n')
    (methods / 'AXBM_Ignore.4dm').write_text('// Ignore the missing bridge in the plugin-free baseline.\n')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP)
    events = ['onClick', 'onAlternateClick']
    button = {'type': 'button', 'width': 160, 'height': 24, 'method': 'ObjectMethods/Event.4dm', 'events': events}
    form = {'windowTitle': TITLE, 'width': 360, 'height': 180, 'destination': 'detailScreen', 'pages': [None, {'objects': {
        'Export': {**button, 'text': 'Export', 'style': 'bevel', 'popupPlacement': 'linked', 'left': 20, 'top': 20},
        'Search': {**button, 'text': 'Search', 'style': 'custom', 'popupPlacement': 'separated', 'left': 20, 'top': 60},
        'Plain': {**button, 'text': 'Plain', 'style': 'regular', 'popupPlacement': 'separated', 'left': 20, 'top': 100},
        'Done': {'type': 'button', 'text': 'Done', 'left': 260, 'top': 140, 'width': 80, 'height': 24, 'action': 'accept'},
    }}]}
    from install_host_methods import area_form
    named = form if args.no_bridge else area_form(json.loads(json.dumps(form)))
    form_path = sources / 'Forms/Buttons'
    (form_path / 'ObjectMethods').mkdir(parents=True)
    (form_path / 'ObjectMethods/Event.4dm').write_text(EVENT)
    (form_path / 'form.4DForm').write_text(json.dumps(named, indent=2) + '\n')
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='button-menu-compile-', dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, 'Driver')
        compiled = run_utility(server / 'Contents/MacOS' / info['CFBundleExecutable'], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n' +
            ('$options.components:=New collection\n' if args.no_bridge else
                f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n') +
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    changed = [name for name, digest in before.items() if sha(FIXTURE / name) != digest]
    passed = compiled.get('success') is True and not compiled.get('errors') and not changed
    (BUILD / 'button-menu-compile-report.json').write_text(json.dumps({'passed': passed, 'compiler': compiled, 'bridge': not args.no_bridge}, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': button menu fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
