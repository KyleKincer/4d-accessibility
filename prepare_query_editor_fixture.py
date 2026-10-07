"""Build a project whose startup method opens 4D's Query editor on a small table.

The Orders table has text, number, Boolean and date fields and five records. The startup
method opens the Query editor with QUERY([Orders]) and records OK and the customers of the
resulting selection, then quits.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET
from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / 'query-editor-fixture'

STARTUP = '''var $i; $ok : Integer
var $config : Object
var $customers : Collection
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
File("/RESOURCES/result.json").delete()
If (Records in table([Orders])=0)
 For ($i; 1; 5)
  CREATE RECORD([Orders])
  [Orders]id:=$i
  [Orders]Customer:="Customer "+String($i)
  [Orders]Amount:=$i*10
  [Orders]Paid:=($i%2)=0
  [Orders]Due:=Add to date(!2026-01-01!; 0; $i; 0)
  SAVE RECORD([Orders])
 End for
End if
ALL RECORDS([Orders])
QUERY([Orders])
$ok:=OK
$customers:=New collection
ORDER BY([Orders]; [Orders]id; >)
FIRST RECORD([Orders])
While (Not(End selection([Orders])))
 $customers.push([Orders]Customer)
 NEXT RECORD([Orders])
End while
File("/RESOURCES/result.json").setText(JSON Stringify(New object("runId"; $config.runId; "compiled"; Is compiled mode; "ok"; $ok; "customers"; $customers)))
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
    project = project_at(FIXTURE, 'QueryEditor')
    sources = FIXTURE / 'Project/Sources'
    catalog = sources / 'catalog.4DCatalog'
    tree = ET.parse(catalog)
    table = ET.SubElement(tree.getroot(), 'table', name='Orders', uuid=uuid.uuid4().hex.upper(), id='1')
    key = uuid.uuid4().hex.upper()
    ET.SubElement(table, 'field', name='id', uuid=key, type='4', unique='true', never_null='true', id='1')
    for number, (name, kind) in enumerate((('Customer', '10'), ('Amount', '6'), ('Paid', '1'), ('Due', '8')), start=2):
        ET.SubElement(table, 'field', name=name, uuid=uuid.uuid4().hex.upper(), type=kind, id=str(number))
    ET.SubElement(table, 'primary_key', field_name='id', field_uuid=key)
    tree.write(catalog, encoding='unicode')
    (FIXTURE / 'Plugins').mkdir()
    (FIXTURE / 'Data').mkdir()
    if not args.no_bridge:
        shutil.copytree(PACKAGE, FIXTURE / 'Components/AccessibilityBridge.4dbase')
        shutil.copytree(BUILD / 'AccessibilityBridge.bundle', FIXTURE / 'Plugins/AccessibilityBridge.bundle')
    (sources / 'DatabaseMethods').mkdir()
    (sources / 'DatabaseMethods/onStartup.4dm').write_text(STARTUP)
    (FIXTURE / 'Resources/launch.json').write_text(json.dumps({'runId': uuid.uuid4().hex}) + '\n')
    before = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob('*') if p.is_file()}
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='query-editor-compile-', dir=BUILD) as temporary:
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
    (BUILD / 'query-editor-compile-report.json').write_text(json.dumps({'passed': passed, 'compiler': compiled, 'bridge': not args.no_bridge}, indent=2) + '\n')
    print(('PASS' if passed else 'FAIL') + ': query editor fixture compilation')
    if not passed:
        print(json.dumps(compiled, indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
