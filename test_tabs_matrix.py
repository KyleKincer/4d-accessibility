#!/usr/bin/env python3
"""Run sequential named/generated tab acceptance and preserve matching reports."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

from build_component import BUILD, ROOT, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    if not args.run:
        parser.error('--run is required for live desktop and VoiceOver tests')
    output = BUILD / ('tabs-acceptance-' + uuid.uuid4().hex)
    output.mkdir()
    files = sorted((ROOT / 'src').glob('*')) + sorted((ROOT / 'host').glob('*/*.4dm'))
    files += [ROOT / name for name in ('manifest.json', 'VERSION', 'prepare_tabs_fixture.py', 'test_tabs_fixture.py', 'test_tabs_matrix.py')]
    sources = {str(p.relative_to(ROOT)): sha(p) for p in files if p.is_file()}
    report = {'passed': False, 'sources_sha256': sources, 'cases': [], 'directory': output.name}

    def save():
        (output / 'matrix.json').write_text(json.dumps(report, indent=2) + '\n')
        (BUILD / 'tabs-matrix.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(command, log):
        print('RUN: ' + ' '.join(command), flush=True)
        with log.open('w') as stream:
            subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True)

    try:
        for name, flags in (
            ('named', []),
            ('generated-icons', ['--dynamic', '--icons']),
            ('named-narrow-overflow-clipped', ['--narrow', '--scroll-icons', '--clipped-children']),
            ('generated-narrow-overflow-clipped', ['--dynamic', '--narrow', '--scroll-icons', '--clipped-children']),
        ):
            directory = output / name
            directory.mkdir()
            case = {'name': name, 'flags': flags, 'runs': []}
            report['cases'].append(case)
            run([sys.executable, 'prepare_tabs_fixture.py', '--server', str(args.server), *flags], directory / 'prepare.log')
            compile_path = BUILD / 'tabs-compile-report.json'
            compiled = json.loads(compile_path.read_text())
            case['compile_report'] = compiled
            case['compile_report_sha256'] = sha(compile_path)
            shutil.copy2(compile_path, directory / 'compile.json')
            for native in (False, True):
                label = 'compiled-voiceover' if native else 'interpreted'
                run([sys.executable, 'test_tabs_fixture.py', '--run', *(['--compiled', '--voiceover'] if native else [])], directory / (label + '.log'))
                variant = ('generated-' if compiled['generated'] else '') + ('narrow-' if compiled['narrow'] else '')
                variant += 'icons-' if compiled['icons'] else ''
                variant += 'scroll-' if compiled['scrollIcons'] else ''
                variant += 'clipped-' if compiled['clippedChildren'] else ''
                path = BUILD / ('tabs-' + variant + label + '.json')
                result = json.loads(path.read_text())
                assert result['passed'] and result['compile_report_sha256'] == case['compile_report_sha256']
                case['runs'].append({'report_sha256': sha(path), 'report': result})
                shutil.copy2(path, directory / (label + '.json'))
                save()
                print(f'PASS: {name}, {label}, {len(result["checks"])} checks', flush=True)
        changed = [name for name, digest in sources.items() if sha(ROOT / name) != digest]
        assert not changed, 'Sources changed during acceptance: ' + ', '.join(changed)
        report['passed'] = True
        report['checkCount'] = sum(len(run['report']['checks']) for case in report['cases'] for run in case['runs'])
        print(f'PASS: complete tab matrix, {report["checkCount"]} checks; reports in {output}', flush=True)
    except Exception as error:
        report['failure'] = str(error)
        for name in ('tabs-failure.png', 'tabs-desktop.log'):
            if (BUILD / name).exists():
                shutil.copy2(BUILD / name, output / name)
        raise
    finally:
        save()


if __name__ == '__main__':
    main()
