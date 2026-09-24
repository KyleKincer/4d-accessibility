#!/usr/bin/env python3
"""Compile repeated AreaList input subforms with synthetic, isolated bindings."""
import argparse
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package
from install_host_methods import AREA_METHODS

FIXTURE = BUILD / 'alp-subforms'
TITLE = 'AX bridge AreaList subforms'


def expected_warning(entry):
    if entry.get('isError') is not False or entry.get('message') != 'Missing parameter in the plug-in procedure call. (533.4)':
        return False
    name = entry.get('code', {}).get('methodName')
    if name not in ('AXBA_Child', 'LinePicker_Form'):
        return False
    lines = (FIXTURE / 'Project/Sources/Methods' / (name + '.4dm')).read_text().splitlines()
    number = entry.get('lineInFile')
    if not isinstance(number, int) or not 1 <= number <= len(lines):
        return False
    return lines[number - 1].strip().removeprefix('$error:=').startswith(('AL_SetArraysNam(', 'AL_SetHeaders(', 'AL_SetWidths(', 'AL_SetColumnLongProperty('))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    args = parser.parse_args()
    if subprocess.run(['pgrep', '-x', '4D'], capture_output=True).returncode == 0:
        parser.error('Close the desktop fixture before preparing another')
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.4D.4DServer':
        parser.error('--server must identify 4D Server')
    verify_package(PACKAGE)
    vendor = ROOT / 'fixture/Plugins/ALP.bundle'
    if not vendor.is_dir():
        parser.error('Install the vendor AreaList plugin in fixture/Plugins first')
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ('alp-subforms-previous-' + uuid.uuid4().hex))
    project = project_at(FIXTURE, 'ALPSubforms')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
    shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
    shutil.copytree(vendor, FIXTURE / 'Plugins/ALP.bundle')
    for path in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
        (methods / path.name).write_text(path.read_text())
    for name in AREA_METHODS:
        path = ROOT / 'host/Methods' / (name + '.4dm')
        (methods / path.name).write_text(path.read_text())
    declarations = (ROOT / 'host/Methods/Compiler_AXB.4dm').read_text().splitlines()
    (methods / 'Compiler_AXBA.4dm').write_text('\n'.join(line for line in declarations if any('('+name+';' in line for name in AREA_METHODS)) + '''
C_OBJECT(AXBA_Describe; $0)
C_OBJECT(AXBA_Apply; $0; $1)
C_OBJECT(AXBA_ParentDescribe; $0)
C_OBJECT(AXBA_ParentApply; $0; $1)
C_OBJECT(AXBA_State; $1)
C_OBJECT(AXBA_Failed; $1)
C_TEXT(AXBA_Change; $1)
C_OBJECT(oMethodMetrics)
C_TEXT(MethodMetric_Start; $1)
C_BOOLEAN(MethodMetric_End; $1)
C_TEXT(MethodMetric_End; $2)
''')
    (methods / 'MethodMetric_Start.4dm').write_text('#DECLARE($name : Text)\n')
    (methods / 'MethodMetric_End.4dm').write_text('#DECLARE($success : Boolean; $message : Text)\n')
    for path in (ROOT / 'tests/4d').glob('AXBA_*.4dm'):
        shutil.copy2(path, methods / path.name)
    walkthrough = ROOT / 'skills/4d-accessibility/references/examples/AREALIST-SUBFORM.md'
    snippets = re.findall(r'```4d\n// (\w+)\n(.*?)```', walkthrough.read_text(), re.S)
    if {name for name, _ in snippets} != {'LinePicker_Form', 'LinePicker_Describe', 'LinePicker_Apply', 'LinePicker_Stop', 'Compiler_LinePicker'}:
        raise RuntimeError('AreaList walkthrough methods changed; check the fixture mapping')
    for name, snippet in snippets:
        (methods / (name + '.4dm')).write_text(snippet)
    database = sources / 'DatabaseMethods'
    database.mkdir()
    (database / 'onStartup.4dm').write_text('AXBA_Open\n')
    # Each unnamed plugin-area variable belongs to its actual subform instance.
    grid = {'type': 'plugin', 'pluginAreaKind': '%AreaListPro', 'dataSource': '', 'dataSourceTypeHint': 'integer',
            'left': 10, 'top': 10, 'width': 340, 'height': 180, 'events': ['onLoad', 'onPluginArea'], 'method': 'AXBA_GridEvent'}
    child = {'width': 365, 'height': 220, 'method': 'AXBA_Child', 'events': ['onLoad', 'onUnload'],
             'pages': [None, {'objects': {'Grid': grid}}]}
    objects = {name: {'type': 'subform', 'detailForm': 'Lines', 'dataSource': 'Form.' + name.lower(),
                      'left': left, 'top': 20, 'width': 365, 'height': 220, 'borderStyle': 'none'}
               for name, left in (('Left', 20), ('Right', 410))}
    for name, left in (('Sort', 20), ('Hide', 150), ('Disable', 280), ('Replace', 410), ('Identity', 540), ('Close', 670)):
        objects[name] = {'type': 'button', 'text': name, 'left': left, 'top': 260, 'width': 115, 'height': 28,
                         'method': 'AXBA_Click', 'events': ['onClick']}
    objects['Close']['action'] = 'cancel'
    objects['Close'].pop('method')
    objects['Close'].pop('events')
    for name, left in [('Reload', 20), ('Loaded', 150), ('BadKey', 280)]:
        objects[name] = {'type': 'button', 'text': name, 'left': left, 'top': 300, 'width': 115, 'height': 28,
                         'method': 'AXBA_Click', 'events': ['onClick']}
    parent = {'windowTitle': TITLE, 'width': 800, 'height': 360, 'method': 'AXBA_Parent',
              'events': ['onLoad', 'onUnload', 'onTimer'], 'pages': [None, {'objects': objects}]}
    for name, form in (('Lines', child), ('AlternateLines', child), ('Parent', parent)):
        folder = sources / 'Forms' / name
        folder.mkdir(parents=True)
        (folder / 'method.4dm').write_text(form['method'] + '\n')
        form = dict(form, method='method.4dm')
        (folder / 'form.4DForm').write_text(json.dumps(form, indent=2) + '\n')
    # Optional existing license is copied without ever placing its value in logs.
    license_file = ROOT / 'fixture/Resources/alp.license'
    if license_file.exists():
        shutil.copy2(license_file, FIXTURE / 'Resources/alp.license')
        (FIXTURE / 'Resources/alp.license').chmod(0o600)
    config = {'runId': uuid.uuid4().hex, 'licenseMode': 'registered' if license_file.exists() else 'demo'}
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps(config) + '\n')
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    with tempfile.TemporaryDirectory(prefix='alp-subforms-compile-', dir=BUILD) as directory:
        driver = Path(directory)
        project_at(driver, 'Driver')
        body = '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
        body += f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
        body += f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
        body += f'$result:=Compile project(File({literal(project)}); $options)'
        compiled = run_utility(server / 'Contents/MacOS' / info['CFBundleExecutable'], driver, body, 90)
    diagnostics = compiled.get('errors', [])
    errors = [e for e in diagnostics if not expected_warning(e)]
    passed = compiled.get('success') is True and not errors
    report = {'passed': passed, 'compiler': compiled, 'sources_sha256': hashes, **config,
              'walkthrough_sha256': sha(walkthrough),
              'expectedVendorWarningCount': len(diagnostics) - len(errors), 'unexpectedDiagnosticCount': len(errors),
              'component_sha256': sha(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ'),
              'native_sha256': sha(FIXTURE / 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge')}
    (BUILD / 'alp-subforms-compile-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': AreaList subform compilation')
    for error in errors:
        print(error)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
