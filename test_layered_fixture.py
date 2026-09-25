#!/usr/bin/env python3
"""Verify native activation of existing controls with declared overlap layers."""
import argparse
import json
import subprocess
import sys
import doctor
from build_component import sha
from prepare_layered_fixture import BUILD, FIXTURE, ROOT, TITLE
sys.path.insert(0, str(ROOT / 'tests'))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--compiled', action='store_true')
    parser.add_argument('--voiceover', action='store_true')
    parser.add_argument('--keep-open', action='store_true')
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()['unlocked']:
        parser.error('--run, Accessibility permission and an unlocked desktop are required')
    if subprocess.run(['pgrep', '-x', '4D'], capture_output=True).returncode == 0:
        parser.error('Close 4D before launching the owned fixture')
    built = json.loads((BUILD / 'layered-compile-report.json').read_text())
    assert built['passed']
    for path, expected in built['sources_sha256'].items():
        assert sha(FIXTURE / path) == expected, path
    for key, path in [('native_sha256', 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge'), ('component_sha256', 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')]:
        assert sha(FIXTURE / path) == built[key]
    status = FIXTURE / 'Resources/status.json'
    status.unlink(missing_ok=True)
    report = {'passed': False, 'compiled': args.compiled, 'checks': [], 'compile_report_sha256': sha(BUILD / 'layered-compile-report.json')}
    def check(ok, name):
        report['checks'].append({'passed': bool(ok), 'name': name})
        print(('PASS: ' if ok else 'FAIL: ') + name, flush=True)
        assert ok, name
    def state(check_errors=True):
        if not status.exists(): return {}
        try: value = json.loads(status.read_text(encoding='utf-8-sig'))
        except (ValueError, OSError): return {}
        if check_errors:
            assert not value.get('error') and not value.get('failure'), value
        return value
    project = FIXTURE / 'Project/Layers.4DProject'
    with (BUILD / 'layered-desktop.log').open('w') as log:
        process = subprocess.Popen(['/usr/bin/arch', '-arm64', '/Applications/4D/4D.app/Contents/MacOS/4D', '--project', str(project), '--dataless', '--opening-mode', 'compiled' if args.compiled else 'interpreted', '--webadmin-auto-start', 'false'], stdout=log, stderr=log)
    try:
        ready, report['mode_notice_acknowledged'] = wait_for_start(process, project, state, BUILD)
        check(ready['compiled'] is args.compiled and ready['start']['ok'], 'parent runs in the requested mode with its automatic bridge')
        app, window = activate_fixture(process, project, TITLE)
        def root(w): return next((e for e in w.read('AXChildren') or [] if str(e.read('AXIdentifier')).startswith('axb.window.')), None)
        parent = ax.wait_for(lambda:root(window), 'Parent tree', timeout=15)
        def find(group, label): return next((e for e in group.read('AXChildren') or [] if e.read('AXDescription') == label), None)
        def settle():
            ax.wait_for(lambda:parent.read('AXHelp') == "Activation dispatched through the control's normal event path", 'Action receipt missing', timeout=15)
        assert find(parent, 'Foreground action').press() == 0
        ax.wait_for(lambda:state().get('foregroundClicks') == 1, 'Foreground action blocked', timeout=15)
        settle()
        check(True, 'foreground control invokes its existing handler above a background button')
        check(state()['backgroundClicks'] == 0, 'foreground controls never invoke the background handler')
        assert find(parent, 'Covered').press() == 0
        ax.wait_for(lambda:parent.read('AXHelp') == 'Control is overlapped', 'Covered control was not rejected', timeout=15)
        check(state()['coveredClicks'] == 0, 'fully covered control never invokes either handler')
        assert find(parent, 'Partial').press() == 0
        ax.wait_for(lambda:state().get('partialClicks') == 1, 'Visible part of overlapping button not activated', timeout=15)
        settle()
        check(True, 'partly covered control uses its unobscured native click region')
        assert find(parent, 'Background action').press() == 0
        ax.wait_for(lambda:state().get('backgroundClicks') == 1, 'Background action did not find a free region', timeout=15)
        settle()
        check(state()['coveredClicks'] == 0 and state()['partialClicks'] == 1 and state()['opaqueClicks'] == 0, 'background action avoids foreground controls and the grid without its own accessibility provider')
        stacked = [e for e in parent.read('AXChildren') or [] if e.read('AXDescription') == 'Stacked action']
        check(len(stacked) == 1, 'coincident buttons expose only the declared front button')
        front = stacked[0]
        assert front.press() == 0
        ax.wait_for(lambda:state().get('frontClicks') == 1, 'Front button did not run', timeout=15)
        settle()
        back = ax.wait_for(lambda:find(parent, 'Stacked action') if find(parent, 'Stacked action') and not find(parent, 'Stacked action').same_as(front) else None, 'Covered button did not reappear', timeout=15)
        check(front.read('AXEnabled') is not True and state()['backClicks'] == 0, 'hiding the front button exposes the original back button and retires the front action')
        assert back.press() == 0
        ax.wait_for(lambda:state().get('backClicks') == 1, 'Revealed button did not run', timeout=15)
        settle()
        restored = ax.wait_for(lambda:find(parent, 'Stacked action') if find(parent, 'Stacked action') and not find(parent, 'Stacked action').same_as(back) else None, 'Restored front button did not cover the back button', timeout=15)
        check(restored.read('AXEnabled') is True and back.read('AXEnabled') is not True and front.read('AXEnabled') is not True and state()['frontClicks'] == 1, 'restoring the front button republishes it while retained hidden actions remain retired')
        if args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / 'layered-voiceover', BUILD / 'read-fixture-screen')
            try:
                vo.start()
                for counter in ['frontClicks', 'backClicks']:
                    caption = vo.key('home', command=True)
                    entered = False
                    for _ in range(30):
                        assert 'not responding' not in caption.lower(), caption
                        if 'Stacked action' in caption and 'button' in caption.lower():
                            vo.key('space')
                            ax.wait_for(lambda:state().get(counter) == 2, 'VoiceOver did not invoke the exposed button', timeout=15)
                            settle()
                            check(True, 'VoiceOver reads and activates the exposed ' + counter + ' button')
                            break
                        if not entered and 'Layer test' in caption and 'group' in caption.lower():
                            entered = True
                            caption = vo.key('down', shift=True)
                        else:
                            caption = vo.key('right')
                    else:
                        raise AssertionError('VoiceOver did not reach the exposed stacked button')
            finally:
                vo.stop()
        assert find(parent, 'Close fixture').press() == 0
        process.wait(timeout=15)
        check(process.returncode == 0, 'ordinary close exits the fixture')
        report['passed'] = True
    finally:
        if 'parent' in locals(): report['lastReceipt'] = parent.read('AXHelp')
        report['lastState'] = state(check_errors=False)
        mode = 'compiled' if args.compiled else 'interpreted'
        (BUILD / ('layered-runtime-' + mode + ('-voiceover' if args.voiceover else '') + '.json')).write_text(json.dumps(report, indent=2)+'\n')
        if process.poll() is None:
            ax.capture_window(process.pid, BUILD / 'layered-last.png')
            if not args.keep_open:
                process.terminate()
                process.wait(timeout=10)
            else:
                print('Owned fixture PID', process.pid, flush=True)


if __name__ == '__main__':
    main()
