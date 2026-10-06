"""Build an area-owned synthetic form with 4D's picture-based controls.

Two button grids (one with configured cell labels), a picture button, a spinner,
a configured picture popup menu and a splitter. Each control's object method records its
events with its value, so a test can tell which of the application's own events ran.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import uuid
import zlib
from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / 'picture-fixture'
TITLE = 'AX bridge picture controls'

STARTUP = '''ON ERR CALL("AXBP_Error")
var $window : Integer
var $data : Object
$data:=New object("align"; 0; "palette"; 0; "mode"; 1; "busy"; 1; "color"; 1; "config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
File("/RESOURCES/events.jsonl").delete()
$window:=Open form window("Controls"; Plain form window)
DIALOG("Controls"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "failure"; $data.axbFailure)))
QUIT 4D
'''

EVENT = '''// Record each event with the control's value.
var $file : 4D.File
var $previous; $name : Text
$name:=OBJECT Get name(Object current)
$file:=File("/RESOURCES/events.jsonl")
If ($file.exists)
 $previous:=$file.getText()
End if
$file.setText($previous+JSON Stringify(New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "object"; $name; "event"; Form event code; "value"; OBJECT Get value($name)))+Char(10))
'''

CONFIGURE = '''// Application configuration: the alignment grid's and color menu's pictures need words.
#DECLARE($form : Text) -> $options : Object
If ($form="Controls")
 $options:=New object("controls"; New object("Align"; New object("cells"; New collection("Left"; "Center"; "Right")); \
  "Color"; New object("cells"; New collection("Blue"; "Indigo"; "Violet"))))
End if
'''


def write_strip(path, columns, rows):
    """A fixture-owned picture divided into distinct colored cells."""
    width, height = columns * 32, rows * 32
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    lines = b''.join(b'\0' + b''.join(bytes(((x // 32) * 80 % 256, (y // 32) * 110 % 256, 190)) for x in range(width)) for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(lines)) + chunk(b'IEND', b''))


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
    project = project_at(FIXTURE, 'Pictures')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
        for path in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
            shutil.copy2(path, methods / path.name)
        (methods / 'AXB_Configure.4dm').write_text(CONFIGURE)
        (methods / 'Compiler_AXBP.4dm').write_text('C_TEXT(AXB_Configure; $1)\nC_OBJECT(AXB_Configure; $0)\n')
    (methods / 'AXBP_Error.4dm').write_text('File("/RESOURCES/errors.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\n')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP)
    write_strip(FIXTURE / 'Resources/align.png', 3, 1)
    write_strip(FIXTURE / 'Resources/palette.png', 2, 2)
    write_strip(FIXTURE / 'Resources/states.png', 3, 1)
    logged = {'method': 'ObjectMethods/Log.4dm', 'events': ['onClick']}
    form = {'windowTitle': TITLE, 'width': 520, 'height': 300, 'destination': 'detailScreen', 'pages': [None, {'objects': {
        'Align': {'type': 'buttonGrid', 'left': 20, 'top': 20, 'width': 192, 'height': 40, 'columnCount': 3, 'rowCount': 1,
                  'picture': '/RESOURCES/align.png', 'dataSource': 'Form.align', 'tooltip': 'Alignment', **logged},
        'Palette': {'type': 'buttonGrid', 'left': 20, 'top': 90, 'width': 120, 'height': 80, 'columnCount': 2, 'rowCount': 2,
                    'picture': '/RESOURCES/palette.png', 'dataSource': 'Form.palette', 'tooltip': 'Palette', **logged},
        'Mode': {'type': 'pictureButton', 'left': 260, 'top': 20, 'width': 32, 'height': 32, 'columnCount': 3, 'rowCount': 1,
                 'picture': '/RESOURCES/states.png', 'dataSource': 'Form.mode', 'tooltip': 'Mode', **logged},
        'Busy': {'type': 'spinner', 'left': 260, 'top': 90, 'width': 32, 'height': 32, 'dataSource': 'Form.busy', 'tooltip': 'Loading'},
        'Color': {'type': 'picturePopup', 'left': 340, 'top': 20, 'width': 32, 'height': 32, 'columnCount': 3, 'rowCount': 1,
                  'picture': '/RESOURCES/states.png', 'dataSource': 'Form.color', 'tooltip': 'Color', **logged},
        'Divider': {'type': 'splitter', 'left': 230, 'top': 10, 'width': 6, 'height': 240},
        'Done': {'type': 'button', 'text': 'Done', 'left': 420, 'top': 260, 'width': 80, 'height': 24, 'action': 'accept'},
    }}]}
    from install_host_methods import area_form
    named = form if args.no_bridge else area_form(json.loads(json.dumps(form)))
    form_path = sources / 'Forms/Controls'
    (form_path / 'ObjectMethods').mkdir(parents=True)
    (form_path / 'ObjectMethods/Log.4dm').write_text(EVENT)
    (form_path / 'form.4DForm').write_text(json.dumps(named, indent=2) + '\n')
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='picture-compile-', dir=BUILD) as temporary:
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
    (BUILD / 'picture-compile-report.json').write_text(json.dumps({'passed': passed, 'compiler': compiled, 'bridge': not args.no_bridge}, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': picture controls fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
