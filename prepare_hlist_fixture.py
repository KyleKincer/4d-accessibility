"""Build an area-owned synthetic form with one classic hierarchical list.

The list has nested, expanded and collapsed groups and more items than fit, so
it scrolls. Its object method records every list event with the selection and
expansion, so a test can tell which of the application's own events ran.
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

FIXTURE = BUILD / 'hlist-fixture'
TITLE = 'AX bridge hierarchical list'
ACCESSORIES = ['Cables', 'Stands', 'Cases', 'Straps', 'Picks', 'Strings', 'Tuners', 'Capos', 'Pedals', 'Headphones']

STARTUP = '''ON ERR CALL("AXBH_Error")
var $list; $sub; $deep; $picks; $i : Integer
var $window : Integer
var $data : Object
$list:=New list
APPEND TO LIST($list; "Electronics"; 1)
$sub:=New list
APPEND TO LIST($sub; "Keyboards"; 11)
$deep:=New list
APPEND TO LIST($deep; "Workstations"; 111)
APPEND TO LIST($deep; "Stage pianos"; 112)
SET LIST ITEM($sub; 11; "Keyboards"; 11; $deep; False)
APPEND TO LIST($sub; "Synthesizers"; 12)
SET LIST ITEM($list; 1; "Electronics"; 1; $sub; True)
APPEND TO LIST($list; "Guitars"; 2)
$sub:=New list
APPEND TO LIST($sub; "Electric"; 21)
APPEND TO LIST($sub; "Acoustic"; 22)
SET LIST ITEM($list; 2; "Guitars"; 2; $sub; False)
__ACCESSORIES__
SELECT LIST ITEMS BY REFERENCE($list; 12)
// A flat list that accepts multiple selections.
$picks:=New list
For ($i; 1; 6)
 APPEND TO LIST($picks; "Pick "+String($i); 200+$i)
End for
SET LIST PROPERTIES($picks; 0; 0; 18; 0; 1; 0)
SELECT LIST ITEMS BY REFERENCE($picks; 201)
$data:=New object("tree"; $list; "picks"; $picks; "config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
File("/RESOURCES/events.jsonl").delete()
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "failure"; $data.axbFailure)))
CLEAR LIST($list; *)
CLEAR LIST($picks; *)
QUIT 4D
'''

EVENT = '''// Record each list event with the application's view of selection and expansion.
var $file : 4D.File
var $ref; $sub; $i : Integer
var $text : Text
var $expanded : Boolean
var $expandedItems : Collection
$expandedItems:=New collection
For ($i; 1; Count list items(Form.tree))
 GET LIST ITEM(Form.tree; $i; $ref; $text; $sub; $expanded)
 If ($expanded)
  $expandedItems.push($ref)
 End if
End for
$file:=File("/RESOURCES/events.jsonl")
var $previous : Text
If ($file.exists)
 $previous:=$file.getText()
End if
$file.setText($previous+JSON Stringify(New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "event"; Form event code; "selected"; Selected list items(Form.tree; *); "visible"; Count list items(Form.tree); "expanded"; $expandedItems))+Char(10))
'''


PICKS_EVENT = '''// Record each event of the multiple-selection list with its selected references.
var $file : 4D.File
var $previous : Text
var $count : Integer
var $selected : Collection
ARRAY LONGINT($refs; 0)
$count:=Selected list items(Form.picks; $refs; *)
$selected:=New collection
ARRAY TO COLLECTION($selected; $refs)
$file:=File("/RESOURCES/events.jsonl")
If ($file.exists)
 $previous:=$file.getText()
End if
$file.setText($previous+JSON Stringify(New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "object"; "Picks"; "event"; Form event code; "picks"; $selected))+Char(10))
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
    project = project_at(FIXTURE, 'HList')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
        for path in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
            shutil.copy2(path, methods / path.name)
    (methods / 'AXBH_Error.4dm').write_text('File("/RESOURCES/errors.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\n')
    (sources / 'DatabaseMethods').mkdir()
    accessories = '\n'.join(f'APPEND TO LIST($list; "{name}"; {30 + i})' for i, name in enumerate(ACCESSORIES))
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP.replace('__ACCESSORIES__', accessories))
    form = {'windowTitle': TITLE, 'width': 520, 'height': 360, 'destination': 'detailScreen', 'pages': [None, {'objects': {
        'Catalog': {'type': 'list', 'left': 20, 'top': 20, 'width': 240, 'height': 200, 'dataSource': 'Form.tree', 'dataSourceTypeHint': 'integer',
                    'tooltip': 'Product catalog', 'method': 'ObjectMethods/Catalog.4dm',
                    'events': ['onClick', 'onDoubleClick', 'onExpand', 'onCollapse', 'onSelectionChange']},
        'Picks': {'type': 'list', 'left': 290, 'top': 20, 'width': 200, 'height': 200, 'dataSource': 'Form.picks', 'dataSourceTypeHint': 'integer',
                  'tooltip': 'Picks', 'method': 'ObjectMethods/Picks.4dm', 'events': ['onClick', 'onSelectionChange']},
        'Done': {'type': 'button', 'text': 'Done', 'left': 420, 'top': 320, 'width': 80, 'height': 24, 'action': 'accept'},
    }}]}
    from install_host_methods import area_form
    named = form if args.no_bridge else area_form(json.loads(json.dumps(form)))
    form_path = sources / 'Forms/Probe'
    (form_path / 'ObjectMethods').mkdir(parents=True)
    (form_path / 'ObjectMethods/Catalog.4dm').write_text(EVENT)
    (form_path / 'ObjectMethods/Picks.4dm').write_text(PICKS_EVENT)
    (form_path / 'form.4DForm').write_text(json.dumps(named, indent=2) + '\n')
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='hlist-compile-', dir=BUILD) as temporary:
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
    report = {'passed': passed, 'compiler': compiled, 'sources_sha256': before, 'bridge': not args.no_bridge, 'changed_during_compile': changed,
              'native_sha256': None if args.no_bridge else sha(FIXTURE / 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge'),
              'component_sha256': None if args.no_bridge else sha(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')}
    (BUILD / 'hlist-compile-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': hierarchical list fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
