"""Build a project whose startup method shows two windows of 4D's Progress component.

One progress is determinate, with a message and an enabled Stop button; the other is
indeterminate. The startup method advances the first when the test asks, records when
Progress Stopped reports a Stop press, and quits on a stop file or after a Stop press.
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

FIXTURE = BUILD / 'progress-fixture'

STARTUP = '''var $id; $other; $i : Integer
var $config : Object
var $advanced : Boolean
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
File("/RESOURCES/events.jsonl").delete()
$id:=Progress New
Progress SET TITLE($id; "Importing orders")
Progress SET MESSAGE($id; "Order 3 of 10")
Progress SET PROGRESS($id; 0.3)
Progress SET BUTTON ENABLED($id; True)
$other:=Progress New
Progress SET TITLE($other; "Waiting for server")
Progress SET PROGRESS($other; -1)
For ($i; 1; 3600)
 DELAY PROCESS(Current process; 5)
 If (Not($advanced) & File("/RESOURCES/advance.txt").exists)
  $advanced:=True
  Progress SET PROGRESS($id; 0.75)
  Progress SET MESSAGE($id; "Order 8 of 10")
 End if
 If (Progress Stopped($id))
  File("/RESOURCES/events.jsonl").setText(JSON Stringify(New object("runId"; $config.runId; "compiled"; Is compiled mode; "event"; "stopped"; "advanced"; $advanced))+Char(10))
  break
 End if
 If (File("/RESOURCES/stop.txt").exists)
  break
 End if
End for
Progress QUIT($other)
Progress QUIT($id)
QUIT 4D
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
    project = project_at(FIXTURE, 'Progress')
    sources = FIXTURE / 'Project/Sources'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP)
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    # The Progress component ships with 4D; the compiler needs it named to resolve its commands.
    components = [server / 'Contents/Components/4D Progress.4dbase/4D Progress.4DZ']
    if not args.no_bridge:
        components.append(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')
    with tempfile.TemporaryDirectory(prefix='progress-compile-', dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, 'Driver')
        compiled = run_utility(server / 'Contents/MacOS' / info['CFBundleExecutable'], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            '$options.components:=New collection(' + '; '.join(f'File({literal(path)})' for path in components) + ')\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    changed = [name for name, digest in before.items() if sha(FIXTURE / name) != digest]
    passed = compiled.get('success') is True and not compiled.get('errors') and not changed
    (BUILD / 'progress-compile-report.json').write_text(json.dumps({'passed': passed, 'compiler': compiled, 'bridge': not args.no_bridge}, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': progress fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
