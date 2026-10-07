"""Build a project with an ordinary form that has no bridge area: the plugin alone describes it.

The Customer form has captions with inputs, a checkbox, two radio buttons, a drop-down list,
a titled button, an untitled button with a help tip, and Done. The Save button's method records
the form's values, so a test can tell what each control holds after it is operated.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from build_component import BUILD, PACKAGE, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / 'generic-form-fixture'
TITLE = 'AX bridge generic form'

STARTUP = '''var $window : Integer
var $data : Object
$data:=New object("name"; ""; "city"; "Lyon"; "active"; False; "retail"; 1; "wholesale"; 0; "config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
$data.tier:=New object("values"; New collection("Gold"; "Silver"; "Bronze"); "index"; 0)
File("/RESOURCES/events.jsonl").delete()
$window:=Open form window("Customer"; Plain form window)
DIALOG("Customer"; $data)
QUIT 4D
'''

# Records each event, and the form's values when Save or Help is pressed.
EVENT = '''var $file : 4D.File
var $previous : Text
var $entry : Object
$entry:=New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "object"; OBJECT Get name(Object current); "event"; Form event code)
If (Form event code=On Clicked)
 $entry.values:=New object("name"; Form.name; "city"; Form.city; "active"; Form.active; "retail"; Form.retail; "wholesale"; Form.wholesale; "tier"; Form.tier.index)
End if
$file:=File("/RESOURCES/events.jsonl")
If ($file.exists)
 $previous:=$file.getText()
End if
$file.setText($previous+JSON Stringify($entry)+Char(10))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--no-bridge', action='store_true', help='Native baseline with no plugin or component')
    args = parser.parse_args()
    for name in ('4D', '4D Server'):
        if subprocess.run(['pgrep', '-x', name], capture_output=True).returncode == 0:
            parser.error('Close 4D before preparing this sequential fixture')
    verify_package(PACKAGE)
    if FIXTURE.exists():
        shutil.rmtree(FIXTURE)
    project = project_at(FIXTURE, 'GenericForm')
    sources = FIXTURE / 'Project/Sources'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP)
    logged = {'method': 'ObjectMethods/Event.4dm', 'events': ['onClick']}
    form = {'windowTitle': TITLE, 'width': 420, 'height': 300, 'destination': 'detailScreen', 'pages': [None, {'objects': {
        'title': {'type': 'text', 'text': 'Customer details', 'left': 20, 'top': 16, 'width': 300, 'height': 18},
        'labelName': {'type': 'text', 'text': 'Name:', 'left': 20, 'top': 50, 'width': 60, 'height': 17},
        'inputName': {'type': 'input', 'dataSource': 'Form.name', 'left': 90, 'top': 48, 'width': 200, 'height': 18, 'placeholder': 'Full name'},
        'labelCity': {'type': 'text', 'text': 'City:', 'left': 20, 'top': 80, 'width': 60, 'height': 17},
        'inputCity': {'type': 'input', 'dataSource': 'Form.city', 'left': 90, 'top': 78, 'width': 200, 'height': 18},
        'checkActive': {'type': 'checkbox', 'text': 'Active', 'dataSource': 'Form.active', 'left': 20, 'top': 112, 'width': 120, 'height': 20, **logged},
        'radioRetail': {'type': 'radio', 'text': 'Retail', 'dataSource': 'Form.retail', 'radioGroup': 'kind', 'left': 20, 'top': 142, 'width': 120, 'height': 20, **logged},
        'radioWholesale': {'type': 'radio', 'text': 'Wholesale', 'dataSource': 'Form.wholesale', 'radioGroup': 'kind', 'left': 150, 'top': 142, 'width': 120, 'height': 20, **logged},
        'dropdownTier': {'type': 'dropdown', 'dataSource': 'Form.tier', 'tooltip': 'Tier', 'left': 20, 'top': 174, 'width': 160, 'height': 22, **logged},
        'btnSave': {'type': 'button', 'text': 'Save', 'left': 20, 'top': 220, 'width': 90, 'height': 24, **logged},
        'btnHelp': {'type': 'button', 'style': 'custom', 'tooltip': 'Help', 'left': 120, 'top': 220, 'width': 24, 'height': 24, **logged},
        'btnUnnamed': {'type': 'button', 'style': 'custom', 'left': 150, 'top': 220, 'width': 24, 'height': 24},
        'btnDone': {'type': 'button', 'text': 'Done', 'action': 'accept', 'left': 310, 'top': 260, 'width': 90, 'height': 24},
    }}]}
    form_path = sources / 'Forms/Customer'
    (form_path / 'ObjectMethods').mkdir(parents=True)
    (form_path / 'ObjectMethods/Event.4dm').write_text(EVENT)
    (form_path / 'form.4DForm').write_text(json.dumps(form, indent=2) + '\n')
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='generic-form-compile-', dir=BUILD) as temporary:
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
    (BUILD / 'generic-form-compile-report.json').write_text(json.dumps({'passed': passed, 'compiler': compiled, 'bridge': not args.no_bridge}, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': generic form fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
