#!/usr/bin/env python3
"""Build an area-owned synthetic form with array, object and list-backed tabs."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import struct
import tempfile
import uuid
import zlib
from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / 'tabs-fixture'
TITLE = 'AX bridge tab controls'


def write_icon(path):
    """A fixture-owned PNG, with no dependency on a system icon or Pillow."""
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + bytes((35, 90 + y * 5, 180, 255)) * 16 for y in range(16))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 16, 16, 8, 6, 0, 0, 0)) +
        chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--dynamic', action='store_true')
    parser.add_argument('--no-bridge', action='store_true', help='Native baseline with no plugin, component or bridge helpers')
    parser.add_argument('--pixel-focus', action='store_true', help='Start on a button for a caret-free pixel comparison')
    parser.add_argument('--narrow', action='store_true', help='Exercise choices wider than their tab control')
    parser.add_argument('--icons', action='store_true', help='Use original list item icons in both wide and compact tabs')
    parser.add_argument('--scroll-icons', action='store_true', help='Force native icon overflow and scroll arrows')
    parser.add_argument('--clipped-children', action='store_true', help='Keep child tabs in a smaller scrolling viewport')
    args = parser.parse_args()
    args.icons = args.icons or args.scroll_icons
    if args.no_bridge and args.dynamic:
        parser.error('Use the named native baseline for pixel comparison')
    for name in ('4D', '4D Server'):
        if subprocess.run(['pgrep', '-x', name], capture_output=True).returncode == 0:
            parser.error('Close 4D before preparing this sequential fixture')
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ('tabs-fixture-previous-' + uuid.uuid4().hex))
    project = project_at(FIXTURE, 'Tabs')
    sources = FIXTURE / 'Project/Sources'
    methods = sources / 'Methods'
    (FIXTURE / 'Plugins').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
        for path in (ROOT / 'host/OptionalMethods').glob('*.4dm'):
            shutil.copy2(path, methods / path.name)
    (methods / 'Compiler_Tabs.4dm').write_text('ARRAY TEXT(AXBT_Array; 0)\nARRAY TEXT(AXBT_Empty; 0)\n')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text('''ON ERR CALL("AXBT_Error")
var $window : Integer
var $form; $data; $prepared : Object
$data:=New object("config"; JSON Parse(File("/RESOURCES/launch.json").getText()))
$data.leftChild:=New object("tabs"; New object("values"; New collection("Local first"; "Local second"); "index"; 0); "events"; New collection; "text"; "Left editor")
$data.rightChild:=New object("tabs"; New object("values"; New collection("Local first"; "Local second"); "index"; 0); "events"; New collection; "text"; "Right editor")
If ($data.config.dynamic)
 $prepared:=AXB_AreaForm(JSON Parse(File("/RESOURCES/form.json").getText()); "GeneratedTabs")
 If (Not($prepared.ok=True))
  File("/RESOURCES/errors.json").setText(JSON Stringify($prepared))
  QUIT 4D
  return
 End if
 $form:=$prepared.form
 $window:=Open form window($form; Plain form window)
 DIALOG($form; $data)
Else
 $window:=Open form window("Probe"; Plain form window)
 DIALOG("Probe"; $data)
End if
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "events"; $data.events)))
CLEAR LIST($data.list)
CLEAR LIST($data.narrowList)
CLOSE WINDOW($window)
QUIT 4D
''')
    if args.no_bridge:
        path = sources / 'DatabaseMethods/onStartup.4dm'
        path.write_text(path.read_text().replace('$prepared:=AXB_AreaForm(JSON Parse(File("/RESOURCES/form.json").getText()); "GeneratedTabs")',
            '$prepared:=New object("ok"; True; "form"; JSON Parse(File("/RESOURCES/form.json").getText()))'))
    (methods / 'AXBT_Error.4dm').write_text('''var $errors : Collection
$errors:=Last errors
File("/RESOURCES/errors.json").setText(JSON Stringify($errors))
''')
    (methods / 'AXBT_Form.4dm').write_text('''Case of
 : (Form event code=On Load)
  Form.events:=New collection
  ARRAY TEXT(AXBT_Array; 3)
  AXBT_Array{1}:="Short"
  AXBT_Array{2}:="A much longer label"
  AXBT_Array{3}:="🎹 Final tab"
  AXBT_Array:=1
  ARRAY TEXT(AXBT_Empty; 0)
  Form.bottomTabs:=New object("values"; New collection("Lower one"; "Lower two"); "index"; 0)
  Form.objectTabs:=New object("values"; New collection("First page"; "Second page longer label"; "Third page"); "index"; 0)
  Form.narrowObject:=New object("values"; New collection("Bound one"; "Bound two"; "Bound three"); "index"; 0)
  Form.list:=New list
  APPEND TO LIST(Form.list; "List first"; 101)
  APPEND TO LIST(Form.list; "List second longer label"; 102)
  APPEND TO LIST(Form.list; "List last"; 103)
  Form.narrowList:=New list
  APPEND TO LIST(Form.narrowList; "Compact first"; 201)
  APPEND TO LIST(Form.narrowList; "Compact second longer label"; 202)
  APPEND TO LIST(Form.narrowList; "Compact last"; 203)
  Form.narrow:=Form.config.narrow
  Form.collapsed:=False
  Form.page1:="Editable page one"
  Form.page2:="Editable page two"
  Form.page3:="Editable page three"
  SET TIMER(6)
 : (Form event code=On Timer)
  AXBT_State
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
End case
''')
    if args.icons:
        write_icon(FIXTURE / 'Resources/tab-icon.png')
        path = methods / 'AXBT_Form.4dm'
        path.write_text('var $icon : Picture\n' + path.read_text().replace('  Form.narrow:=Form.config.narrow',
            '  READ PICTURE FILE(File("/RESOURCES/tab-icon.png").platformPath; $icon)\n' +
            ''.join(f'  SET LIST ITEM ICON(Form.{name}; {reference}; $icon)\n'
                for name, references in (('list', range(101, 104)), ('narrowList', range(201, 204))) for reference in references) +
            '  Form.narrow:=Form.config.narrow'))
    if args.scroll_icons:
        path = methods / 'AXBT_Form.4dm'
        path.write_text(path.read_text().replace('  Form.narrow:=Form.config.narrow',
            ''.join(f'  APPEND TO LIST(Form.narrowList; "Compact extra {i}"; {200+i})\n  SET LIST ITEM ICON(Form.narrowList; {200+i}; $icon)\n'
                for i in range(4, 13)) + '  Form.narrow:=Form.config.narrow'))
    if args.pixel_focus:
        path = methods / 'AXBT_Form.4dm'
        path.write_text(path.read_text().replace('  SET TIMER(6)', '  GOTO OBJECT(*; "Close")\n  SET TIMER(6)'))
    (methods / 'AXBT_Event.4dm').write_text('''var $name : Text
var $reply : Object
$name:=OBJECT Get name(Object current)
Form.events.push(New object("object"; $name; "event"; Form event code; "page"; FORM Get current page; "array"; AXBT_Array; "index"; Form.objectTabs.index))
If ((Form event code=On Clicked) & ($name="Relabel"))
 AXBT_Array{2}:="Replacement label"
Else
 If ((Form event code=On Clicked) & ($name="Collapse"))
  Form.collapsed:=Not(Form.collapsed)
  OBJECT SET COORDINATES(*; "ObjectTabs"; 20; 80; Choose(Form.collapsed; 20; 580); Choose(Form.collapsed; 80; 105))
 Else
  If ((Form event code=On Clicked) & ($name="Presentation"))
   Form.narrow:=Not(Form.narrow)
   OBJECT SET COORDINATES(*; "ArrayTabs"; 20; 20; Choose(Form.narrow; 120; 580); 45)
  End if
 End if
End if
AXBT_State
''')
    if not args.no_bridge:
        path = methods / 'AXBT_Event.4dm'
        path.write_text(path.read_text().replace('AXBT_State\n', '''If ((Form event code=On Clicked) & ($name="Restart"))
 $reply:=AXB_Form("start"; New object("label"; "Tab controls"))
 If (Not($reply.ok=True))
  Form.axbFailure:=$reply
 End if
End if
AXBT_State
'''))
    (methods / 'AXBT_State.4dm').write_text('''var $state; $context : Object
var $reference : Integer
var $text : Text
$context:=AXB_FormContext
$state:=New object("runId"; Form.config.runId; "compiled"; Is compiled mode; "page"; FORM Get current page; "events"; Form.events; "array"; AXBT_Array; "index"; Form.objectTabs.index; "page1"; Form.page1; "page2"; Form.page2; "page3"; Form.page3; "leftChild"; Form.leftChild; "rightChild"; Form.rightChild; "bottomIndex"; Form.bottomTabs.index)
$state.failure:=Form.axbFailure
$state.narrowObject:=Form.narrowObject.index
GET LIST ITEM(Form.narrowList; *; $reference; $text)
$state.narrowList:=New object("reference"; $reference; "label"; $text)
If ($context#Null)
 $state.diagnostics:=$context.diagnostics
End if
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
''')
    if args.no_bridge:
        path = methods / 'AXBT_State.4dm'
        path.write_text(path.read_text().replace('$context:=AXB_FormContext\n', '').replace(
            'If ($context#Null)\n $state.diagnostics:=$context.diagnostics\nEnd if\n', ''))
    objects = {
        'ArrayTabs': {'type': 'tab', 'dataSource': 'AXBT_Array', 'tooltip': 'Categories', 'left': 20, 'top': 20, 'width': 560, 'height': 25, 'events': ['onClick']},
        'ObjectTabs': {'type': 'tab', 'dataSource': 'Form.objectTabs', 'tooltip': 'Pages', 'left': 20, 'top': 80, 'width': 560, 'height': 25, 'action': 'gotoPage', 'events': ['onClick']},
        'ListTabs': {'type': 'tab', 'dataSource': 'Form.list', 'tooltip': 'List choices', 'left': 20, 'top': 140, 'width': 560, 'height': 25, 'events': ['onClick']},
        'Relabel': {'type': 'button', 'text': 'Relabel choice', 'left': 20, 'top': 270, 'width': 170, 'height': 28, 'events': ['onClick']},
        'Collapse': {'type': 'button', 'text': 'Collapse or restore tabs', 'left': 210, 'top': 270, 'width': 170, 'height': 28, 'events': ['onClick']},
        'Close': {'type': 'button', 'text': 'Close fixture', 'left': 410, 'top': 270, 'width': 170, 'height': 28, 'action': 'cancel'},
        'Restart': {'type': 'button', 'text': 'Restart accessibility', 'left': 20, 'top': 300, 'width': 170, 'height': 24, 'events': ['onClick']},
        'StaticTabs': {'type': 'tab', 'labels': ['Static first', 'Static last'], 'tooltip': 'Static choices', 'left': 20, 'top': 330, 'width': 270, 'height': 25, 'events': ['onClick']},
        'BottomTabs': {'type': 'tab', 'dataSource': 'Form.bottomTabs', 'labelsPlacement': 'bottom', 'tooltip': 'Bottom choices', 'left': 320, 'top': 330, 'width': 260, 'height': 25, 'events': ['onClick']},
        'LeftChild': {'type': 'subform', 'detailForm': 'Child', 'dataSource': 'Form.leftChild', 'dataSourceTypeHint': 'object', 'left': 20, 'top': 390, 'width': 260, 'height': 120},
        'RightChild': {'type': 'subform', 'detailForm': 'Child', 'dataSource': 'Form.rightChild', 'dataSourceTypeHint': 'object', 'left': 320, 'top': 390, 'width': 260, 'height': 120},
        'EmptyTabs': {'type': 'tab', 'dataSource': 'AXBT_Empty', 'tooltip': 'Empty choices', 'left': 20, 'top': 560, 'width': 270, 'height': 25},
        'NarrowObject': {'type': 'tab', 'dataSource': 'Form.narrowObject', 'tooltip': 'Compact object choices', 'left': 320, 'top': 560, 'width': 100, 'height': 25, 'events': ['onClick']},
        'NarrowList': {'type': 'tab', 'dataSource': 'Form.narrowList', 'tooltip': 'Compact list choices', 'left': 440, 'top': 560, 'width': 140, 'height': 25, 'events': ['onClick']},
        'Presentation': {'type': 'button', 'text': 'Change tab presentation', 'left': 320, 'top': 595, 'width': 260, 'height': 28, 'events': ['onClick']},
    }
    if args.narrow:
        objects['ArrayTabs']['width'] = 100
    if args.scroll_icons:
        objects['NarrowList']['width'] = 90
    if args.clipped_children:
        objects['LeftChild'].update(width=140, scrollbarHorizontal='visible')
    for obj in objects.values():
        if obj.get('events'):
            obj['method'] = 'AXBT_Event'
    pages = [{'objects': objects}]
    for i in range(1, 4):
        pages.append({'objects': {f'Page{i}Label': {'type': 'text', 'text': f'Page {i} text', 'left': 20, 'top': 212, 'width': 110, 'height': 24},
            f'Page{i}': {'type': 'input', 'dataSource': f'Form.page{i}', 'left': 140, 'top': 210, 'width': 400, 'height': 26, 'events': ['onDataChange'], 'method': 'AXBT_Event'}}})
    child_path = sources / 'Forms/Child'
    (child_path / 'ObjectMethods').mkdir(parents=True)
    (child_path / 'ObjectMethods/Event.4dm').write_text('Form.events.push(New object("object"; OBJECT Get name(Object current); "event"; Form event code; "index"; Form.tabs.index; "text"; Form.text))\n')
    child = {'width': 260, 'height': 120, 'pages': [None, {'objects': {
        'Tabs': {'type': 'tab', 'dataSource': 'Form.tabs', 'tooltip': 'Sections', 'left': 10, 'top': 10, 'width': 240, 'height': 25, 'events': ['onClick'], 'method': 'ObjectMethods/Event.4dm'},
        'TextLabel': {'type': 'text', 'text': 'Child text', 'left': 10, 'top': 62, 'width': 70, 'height': 24},
        'Text': {'type': 'input', 'dataSource': 'Form.text', 'left': 90, 'top': 60, 'width': 150, 'height': 26, 'events': ['onDataChange'], 'method': 'ObjectMethods/Event.4dm'},
    }}]}
    (child_path / 'form.4DForm').write_text(json.dumps(child, indent=2) + '\n')
    form = {'windowTitle': TITLE, 'width': 600, 'height': 630, 'method': 'AXBT_Form', 'events': ['onLoad', 'onTimer'], 'pages': pages}
    form_path = sources / 'Forms/Probe'
    form_path.mkdir(parents=True)
    (form_path / 'form.4DForm').write_text(json.dumps(form, indent=2) + '\n')
    (FIXTURE / 'Resources/form.json').write_text(json.dumps(form, indent=2) + '\n')
    from install_host_methods import area_form
    named = json.loads(json.dumps(form)) if args.no_bridge else area_form(json.loads(json.dumps(form)))
    named['method'] = 'method.4dm'
    (form_path / 'method.4dm').write_text('AXBT_Form\n')
    (form_path / 'ObjectMethods').mkdir()
    for page in named['pages']:
        if not page:
            continue
        for name, obj in page['objects'].items():
            if obj.get('method') == 'AXBT_Event':
                (form_path / 'ObjectMethods' / (name + '.4dm')).write_text('AXBT_Event\n')
                obj['method'] = 'ObjectMethods/' + name + '.4dm'
    (form_path / 'form.4DForm').write_text(json.dumps(named, indent=2) + '\n')
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex, 'dynamic': args.dynamic, 'narrow': args.narrow, 'icons': args.icons, 'scrollIcons': args.scroll_icons, 'clippedChildren': args.clipped_children}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    before['Resources/form.json'] = sha(FIXTURE / 'Resources/form.json')
    if args.icons:
        before['Resources/tab-icon.png'] = sha(FIXTURE / 'Resources/tab-icon.png')
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='tabs-compile-', dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, 'Driver')
        compiled = run_utility(server / 'Contents/MacOS' / info['CFBundleExecutable'], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n' +
            ('$options.components:=New collection\n' if args.no_bridge else
                f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n') +
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    changed = [name for name, digest in before.items() if sha(FIXTURE / name) != digest]
    passed = compiled.get('success') is True and not compiled.get('errors') and not changed
    report = {'passed': passed, 'compiler': compiled, 'sources_sha256': before, 'generated': args.dynamic, 'bridge': not args.no_bridge, 'narrow': args.narrow, 'icons': args.icons, 'scrollIcons': args.scroll_icons, 'clippedChildren': args.clipped_children,
        'changed_during_compile': changed,
        'native_sha256': None if args.no_bridge else sha(FIXTURE / 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge'),
        'component_sha256': None if args.no_bridge else sha(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')}
    (BUILD / 'tabs-compile-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': tabs fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
