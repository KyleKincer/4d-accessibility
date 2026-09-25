#!/usr/bin/env python3
"""Compile overlapping native controls without changing their layout."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / 'layered-fixture'
TITLE = 'AXB layered controls'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', required=True, type=Path)
    args = parser.parse_args()
    for process in ('4D', '4D Server'):
        if subprocess.run(['pgrep', '-x', process], capture_output=True).returncode == 0:
            parser.error('Close 4D before preparing the fixture')
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.4D.4DServer'
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ('layered-previous-' + uuid.uuid4().hex))
    project = project_at(FIXTURE, 'Layers')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
    shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
    for source in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
        shutil.copy2(source, methods / source.name)
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text('''ON ERR CALL("LayerError")
var $window : Integer
var $data : Object
$data:=New object("ticks"; 0; "backgroundClicks"; 0; "coveredClicks"; 0; "partialClicks"; 0; "foregroundClicks"; 0)
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / 'LayerError.4dm').write_text('File("/RESOURCES/status.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (methods / 'LayerClick.4dm').write_text('''Case of
 : (OBJECT Get name(Object current)="Background")
  Form.backgroundClicks:=Form.backgroundClicks+1
 : (OBJECT Get name(Object current)="Covered")
  Form.coveredClicks:=Form.coveredClicks+1
 : (OBJECT Get name(Object current)="Partial")
  Form.partialClicks:=Form.partialClicks+1
 : (OBJECT Get name(Object current)="Foreground")
  Form.foregroundClicks:=Form.foregroundClicks+1
End case
''')
    (methods / 'LayerForm.4dm').write_text('''var $reply : Object
Case of
 : (Form event code=On Load)
  Form.start:=AXB_Form("start"; New object("label"; "Layer test"; "controls"; New object("Background"; New object("label"; "Background action"; "layer"; -1))))
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  File("/RESOURCES/status.json").setText(JSON Stringify(New object("ready"; True; "compiled"; Is compiled mode; "start"; Form.start; "ticks"; Form.ticks; "failure"; Form.axbFailure; "backgroundClicks"; Form.backgroundClicks; "coveredClicks"; Form.coveredClicks; "partialClicks"; Form.partialClicks; "foregroundClicks"; Form.foregroundClicks)))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
''')
    objects = {'Background': {'type': 'button', 'display': False, 'left': 0, 'top': 0, 'width': 500, 'height': 200, 'events': ['onClick'], 'method': 'LayerClick'}}
    for i, (name, label) in enumerate([('Foreground', 'Foreground action'), ('Close', 'Close fixture')]):
        objects[name] = {'type': 'button', 'text': label, 'left': 20, 'top': 20 + 40*i, 'width': 260, 'height': 28, 'events': ['onClick']}
        objects[name].update({'action': 'cancel'} if name == 'Close' else {'method': 'LayerClick'})
    for name, left, top, width in [('Covered', 320, 20, 150), ('Cover', 320, 20, 150), ('Partial', 320, 100, 150), ('PartialCover', 400, 100, 70)]:
        objects[name] = {'type': 'button', 'text': name, 'left': left, 'top': top, 'width': width, 'height': 28, 'events': ['onClick'], 'method': 'LayerClick'}
    form = sources / 'Forms/Probe'
    form.mkdir(parents=True)
    (form / 'form.4DForm').write_text(json.dumps({'windowTitle': TITLE, 'width': 500, 'height': 200, 'method': 'LayerForm', 'events': ['onLoad', 'onTimer', 'onUnload'], 'pages': [None, {'objects': objects}]}, indent=2)+'\n')
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    with tempfile.TemporaryDirectory(prefix='layered-compile-', dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, 'Driver')
        result = run_utility(server / 'Contents/MacOS' / info['CFBundleExecutable'], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    report = {'passed': result.get('success') is True and not result.get('errors'), 'compiler': result, 'sources_sha256': hashes,
              'native_sha256': sha(FIXTURE / 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge'), 'component_sha256': sha(PACKAGE / 'AccessibilityBridge.4DZ')}
    (BUILD / 'layered-compile-report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(('PASS' if report['passed'] else 'FAIL') + ': layered fixture compilation')
    if not report['passed']:
        print(result)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
