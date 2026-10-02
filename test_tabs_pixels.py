#!/usr/bin/env python3
"""Compare complete native tab forms with and without the bridge."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from PIL import Image, ImageChops
from prepare_tabs_fixture import BUILD, FIXTURE, ROOT, TITLE
from build_component import sha

sys.path.insert(0, str(ROOT / 'tests'))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--narrow', action='store_true')
    parser.add_argument('--icons', action='store_true')
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error('--run and Accessibility permission are required')
    ax.require_test_input()
    variant = ('-narrow' if args.narrow else '') + ('-icons' if args.icons else '')
    output = BUILD / ('tabs-pixels' + variant)
    output.mkdir(exist_ok=True)
    report = {'passed': False, 'compiled': True, 'narrow': args.narrow, 'icons': args.icons, 'images': {}, 'runs': {}}
    try:
        for bridge in (False, True):
            name = 'bridge' if bridge else 'baseline'
            subprocess.run([sys.executable, 'prepare_tabs_fixture.py', '--server', str(args.server), '--pixel-focus',
                *(['--narrow'] if args.narrow else []), *(['--icons'] if args.icons else []),
                *([] if bridge else ['--no-bridge'])], cwd=ROOT, check=True)
            compiled = json.loads((BUILD / 'tabs-compile-report.json').read_text())
            report['runs'][name] = {'compile_report_sha256': sha(BUILD / 'tabs-compile-report.json'),
                'original_form_sha256': sha(FIXTURE / 'Resources/form.json'),
                'native_sha256': compiled['native_sha256'], 'component_sha256': compiled['component_sha256']}
            if not bridge:
                assert not (FIXTURE / 'Components').exists() and not list((FIXTURE / 'Plugins').iterdir())
                assert not list((FIXTURE / 'Project/Sources/Methods').glob('AXB_*.4dm'))
            project = FIXTURE / 'Project/Tabs.4DProject'
            last_state = {}

            def state():
                nonlocal last_state
                errors = FIXTURE / 'Resources/errors.json'
                assert not errors.exists(), errors.read_text(encoding='utf-8-sig') if errors.exists() else ''
                try:
                    last_state = json.loads((FIXTURE / 'Resources/runtime-status.json').read_text(encoding='utf-8-sig'))
                except (OSError, ValueError):
                    pass
                assert not last_state.get('failure'), last_state
                return last_state

            with (output / (name + '.log')).open('w') as log:
                process = subprocess.Popen(['/Applications/4D/4D.app/Contents/MacOS/4D', '--project', str(project), '--dataless',
                    '--opening-mode', 'compiled', '--webadmin-auto-start', 'false'], stdout=log, stderr=log)
                try:
                    wait_for_start(process, project, state, BUILD)
                    activate_fixture(process, project, TITLE)
                    ax.wait_for(lambda: state().get('compiled') is True and
                        (not bridge or state().get('diagnostics', {}).get('ready')), 'Compiled native baseline readiness', timeout=20)
                    target = output / (name + '.png')
                    previous = None
                    for _ in range(15):
                        ax.capture_window(process.pid, target, include_shadow=False)
                        current = Image.open(target).convert('RGB')
                        if previous is not None and ImageChops.difference(previous, current).getbbox() is None:
                            break
                        previous = current
                        time.sleep(0.15)
                    else:
                        raise AssertionError('Native rendering did not settle')
                    assert state()['array'] == 1 and state()['index'] == 0 and not state()['events']
                    report['images'][name] = {'sha256': sha(target), 'size': list(current.size)}
                    (FIXTURE / 'Resources/close.json').write_text('{}')
                    process.wait(timeout=15)
                    assert process.returncode == 0
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=10)
        assert report['runs']['baseline']['original_form_sha256'] == report['runs']['bridge']['original_form_sha256']
        baseline = Image.open(output / 'baseline.png').convert('RGB')
        candidate = Image.open(output / 'bridge.png').convert('RGB')
        assert baseline.size == candidate.size, 'Window dimensions changed'
        difference = ImageChops.difference(baseline, candidate)
        difference.save(output / 'difference.png')
        report['differenceBounds'] = difference.getbbox()
        assert report['differenceBounds'] is None, 'Rendered native forms differ'
        report['passed'] = True
        print('PASS: complete tab window is pixel-identical; no masks or tolerance')
    except Exception as error:
        report['failure'] = str(error)
        raise
    finally:
        (BUILD / ('tabs-pixels' + variant + '.json')).write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
