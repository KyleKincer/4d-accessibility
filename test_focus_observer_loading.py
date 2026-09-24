#!/usr/bin/env python3
"""Verify the form focus observer with optional packages in actual desktop On Load."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha
sys.path.insert(0, str(ROOT / 'tests'))
from fixture_desktop import wait_for_start
import doctor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    if not args.run or not doctor.desktop_session()['unlocked']:
        parser.error('--run and an unlocked desktop are required')
    if subprocess.run(['pgrep', '-x', '4D'], capture_output=True).returncode == 0:
        parser.error('Close 4D before running this owned fixture')
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server/'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.4D.4DServer'
    report = {'passed': False, 'cases': [],
        'native_sha256': sha(BUILD/'AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge'),
        'component_sha256': sha(PACKAGE/'AccessibilityBridge.4DZ')}
    output = BUILD/'focus-observer-loading-report.json'
    with tempfile.TemporaryDirectory(prefix='observer-loading-', dir=BUILD) as temporary:
        stage = Path(temporary)
        host = stage/'host'
        project_at(host, 'ObserverLoading')
        sources = host/'Project/Sources'
        for source in (ROOT/'host/OptionalMethods').glob('*.4dm'):
            shutil.copy2(source, sources/'Methods'/source.name)
        (sources/'Methods/Compiler_Observer.4dm').write_text('C_OBJECT(AXBO_Result)\n')
        (sources/'Methods/AXBO_Error.4dm').write_text('''File("/RESOURCES/result.json").setText(JSON Stringify(New object("runtimeError"; Error; "method"; Error method; "line"; Error line)))
QUIT 4D
ABORT
''')
        (sources/'Methods/AXBO_Form.4dm').write_text('''var $reply : Object
ARRAY LONGINT($events; 0)
$reply:=AXB_Form("event"; New object)
Case of
 : (Form event code=On Load)
  OBJECT GET EVENTS(*; ""; $events)
  AXBO_Result:=New object("result"; $reply; "gettingFocus"; Find in array($events; On Getting Focus)>0; "losingFocus"; Find in array($events; On Losing Focus)>0; "timerPreserved"; Find in array($events; On Timer)>0; "ticks"; 0)
  SET TIMER(6)
 : (Form event code=On Timer)
  AXBO_Result.ticks:=AXBO_Result.ticks+1
  AXBO_Result.observerDuringTimer:=$reply
  AXBO_Result.coverage:=AXB_Form("diagnostics"; New object)
  File("/RESOURCES/result.json").setText(JSON Stringify(AXBO_Result))
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
End case
''')
        (sources/'DatabaseMethods').mkdir()
        (sources/'DatabaseMethods/onStartup.4dm').write_text('''var $window : Integer
ON ERR CALL("AXBO_Error")
$window:=Open form window("Observer"; Plain form window)
DIALOG("Observer")
CLOSE WINDOW($window)
QUIT 4D
''')
        form = sources/'Forms/Observer'
        form.mkdir(parents=True)
        (form/'form.4DForm').write_text(json.dumps({'windowTitle': 'AXB observer loading fixture', 'width': 200, 'height': 100,
            'method': 'AXBO_Form', 'events': ['onLoad', 'onTimer'], 'pages': [None, {'objects': {
                'Status': {'type': 'text', 'text': 'Observer loading', 'left': 10, 'top': 10, 'width': 180, 'height': 24},
            }}]})+'\n')
        driver = stage/'driver'
        project_at(driver, 'Driver')
        compiled = run_utility(server/'Contents/MacOS'/info['CFBundleExecutable'], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$result:=Compile project(File({literal(host/"Project/ObserverLoading.4DProject")}); $options)', 90)
        report['compiler'] = compiled
        report['sources_sha256'] = {str(p.relative_to(host)): sha(p) for p in sources.rglob('*') if p.is_file()}
        assert compiled.get('success') is True and not compiled.get('errors'), compiled
        for native, component in [(False, False), (True, False), (False, True), (True, True)]:
            case = stage/f'case-{int(native)}-{int(component)}'
            shutil.copytree(host, case)
            if native:
                shutil.copytree(BUILD/'AccessibilityBridge.bundle', case/'Plugins/AccessibilityBridge.bundle')
            if component:
                shutil.copytree(PACKAGE, case/'Components/AccessibilityBridge.4dbase')
            project = case/'Project/ObserverLoading.4DProject'
            def state():
                try:
                    return json.loads((case/'Resources/result.json').read_text(encoding='utf-8-sig'))
                except (OSError, ValueError):
                    return None
            with (case/'desktop.log').open('w') as log:
                process = subprocess.Popen(['/usr/bin/arch', '-arm64', '/Applications/4D/4D.app/Contents/MacOS/4D',
                    '--project', str(project), '--dataless', '--opening-mode', 'interpreted', '--webadmin-auto-start', 'false'], stdout=log, stderr=log)
                try:
                    result, acknowledged = wait_for_start(process, project, state, BUILD)
                    available = native and component
                    expected = {'ok': True} if available else {'ok': False, 'error': 'dependencyUnavailable', 'native': native, 'component': component}
                    passed = result['result'] == expected and result['gettingFocus'] is available and result['losingFocus'] is available
                    passed = passed and result['timerPreserved'] and result['ticks'] > 0 and result['observerDuringTimer'] == {'ok': True}
                    passed = passed and result['coverage'].get('error') == 'unregisteredWindow'
                    report['cases'].append({'native': native, 'component': component, 'passed': passed, 'runtime': result, 'application_mode_notice_acknowledged': acknowledged})
                    output.write_text(json.dumps(report, indent=2)+'\n')
                    assert passed, result
                finally:
                    (case/'Resources/close.json').write_text('{}\n')
                    process.wait(timeout=15)
                assert process.returncode == 0
                print('PASS: observer On Load, native='+str(native)+', component='+str(component), flush=True)
    report['passed'] = True
    output.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
