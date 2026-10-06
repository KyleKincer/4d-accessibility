"""Build an area-owned synthetic form with a splitter between two panes.

The left pane grows with the splitter. The splitter's object method records
On Clicked with its position and the pane's width, so a test can tell that
4D moved both through its own drag handling.
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

FIXTURE = BUILD / 'splitter-fixture'
TITLE = 'AX bridge splitter'

STARTUP = '''ON ERR CALL("AXBS_Error")
var $window : Integer
var $data : Object
$data:=New object("divider"; 0; "notes"; "Left pane"; "config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
File("/RESOURCES/events.jsonl").delete()
$window:=Open form window("Panes"; Plain form window)
DIALOG("Panes"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "failure"; $data.axbFailure)))
QUIT 4D
'''

EVENT = '''// Record each splitter event with its position and the left pane's width.
var $file : 4D.File
var $previous; $name : Text
var $left; $top; $right; $bottom; $paneLeft; $paneTop; $paneRight; $paneBottom : Integer
$name:=OBJECT Get name(Object current)
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
OBJECT GET COORDINATES(*; "Notes"; $paneLeft; $paneTop; $paneRight; $paneBottom)
$file:=File("/RESOURCES/events.jsonl")
If ($file.exists)
 $previous:=$file.getText()
End if
$file.setText($previous+JSON Stringify(New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "object"; $name; "event"; Form event code; "position"; $left; "paneWidth"; $paneRight-$paneLeft))+Char(10))
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
    project = project_at(FIXTURE, 'Splitter')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
        for path in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
            shutil.copy2(path, methods / path.name)
    (methods / 'AXBS_Error.4dm').write_text('File("/RESOURCES/errors.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\n')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP)
    form = {'windowTitle': TITLE, 'width': 520, 'height': 300, 'destination': 'detailScreen', 'pages': [None, {'objects': {
        'Notes': {'type': 'input', 'left': 20, 'top': 20, 'width': 200, 'height': 240, 'dataSource': 'Form.notes', 'sizingX': 'grow'},
        'Divider': {'type': 'splitter', 'left': 226, 'top': 20, 'width': 6, 'height': 240, 'dataSource': 'Form.divider', 'tooltip': 'Pane divider',
                    'method': 'ObjectMethods/Log.4dm', 'events': ['onClick']},
        'Done': {'type': 'button', 'text': 'Done', 'left': 420, 'top': 260, 'width': 80, 'height': 24, 'action': 'accept'},
    }}]}
    from install_host_methods import area_form
    named = form if args.no_bridge else area_form(json.loads(json.dumps(form)))
    form_path = sources / 'Forms/Panes'
    (form_path / 'ObjectMethods').mkdir(parents=True)
    (form_path / 'ObjectMethods/Log.4dm').write_text(EVENT)
    (form_path / 'form.4DForm').write_text(json.dumps(named, indent=2) + '\n')
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='splitter-compile-', dir=BUILD) as temporary:
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
    (BUILD / 'splitter-compile-report.json').write_text(json.dumps({'passed': passed, 'compiler': compiled, 'bridge': not args.no_bridge}, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': splitter fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
