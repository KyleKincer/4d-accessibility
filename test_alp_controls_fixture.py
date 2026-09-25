#!/usr/bin/env python3
"""Validate AreaList checkbox semantics through external AX and normal vendor callbacks."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

from build_component import sha
from prepare_alp_grid_fixture import BUILD, FIXTURE, ROOT, TITLE
import doctor

sys.path.insert(0, str(ROOT / 'tests'))
import mac_ax as ax
from fixture_desktop import activate_fixture, press_key, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--compiled', action='store_true')
    parser.add_argument('--voiceover', action='store_true')
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()['unlocked']:
        parser.error('--run, Accessibility permission and an unlocked desktop are required')
    if subprocess.run(['pgrep', '-x', '4D'], capture_output=True).returncode == 0:
        parser.error('Close 4D before launching this owned fixture')
    compiled = json.loads((BUILD / 'alp-grid-compile-report.json').read_text())
    assert compiled['passed'] and compiled['controls']
    for relative, digest in compiled['sources_sha256'].items():
        assert sha(FIXTURE / relative) == digest, 'Prepared source changed after compilation'
    for key, relative in [('native_sha256', 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge'),
                          ('component_sha256', 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')]:
        assert sha(FIXTURE / relative) == compiled[key]
    status = FIXTURE / 'Resources/runtime-status.json'
    status.unlink(missing_ok=True)
    checks = []
    report = {'passed': False, 'compiled': args.compiled, 'checks': checks,
              'sources_sha256': compiled['sources_sha256'], 'native_sha256': compiled['native_sha256'],
              'component_sha256': compiled['component_sha256'], 'areaListVersion': compiled['areaListVersion']}
    project = FIXTURE / 'Project/ALPGridFixture.4DProject'
    with (BUILD / 'alp-controls-desktop.log').open('w') as log:
        process = subprocess.Popen(['/Applications/4D/4D.app/Contents/MacOS/4D', '--project', str(project), '--dataless',
                                    '--opening-mode', 'compiled' if args.compiled else 'interpreted', '--webadmin-auto-start', 'false'], stdout=log, stderr=log)
    group = None

    def state():
        assert process.poll() is None, 'Owned fixture exited unexpectedly'
        try:
            result = json.loads(status.read_text(encoding='utf-8-sig'))
        except (OSError, ValueError):
            return {}
        assert result.get('phase') != 'failed' and not result.get('bridgeError') and not result.get('failure'), result
        return result

    def check(condition, message):
        checks.append({'passed': bool(condition), 'name': message})
        print(('PASS: ' if condition else 'FAIL: ') + message, flush=True)
        assert condition, message

    def wait(predicate, message):
        def ready():
            state()
            return predicate()
        return ax.wait_for(ready, message, timeout=15)

    try:
        ready, report['application_mode_notice_acknowledged'] = wait_for_start(process, project, lambda: state() or None, BUILD)
        check(ready['startResult']['ok'] and ready['compiled'] is args.compiled, 'one root adapter starts around repeated existing vendor forms')
        check(ready['registration'] == 0, 'vendor registration succeeds')
        app, window = activate_fixture(process, project, TITLE)
        pending = [window]
        while pending:
            item = pending.pop()
            if (item.read('AXIdentifier') or '').startswith('axb.window.'):
                group = item
                break
            if item.read('AXRole') != 'AXTable':
                pending.extend(item.read('AXChildren') or [])
        assert group is not None

        def find(label):
            return next((e for e in group.read('AXChildren') or [] if any(text == label or text.endswith(': ' + label) for text in (e.read('AXDescription') or '', e.read('AXTitle') or ''))), None)

        def settle():
            wait(lambda: group.read('AXHelp') not in (None, 'Action queued', 'Waiting for the application to complete the action'), 'Action did not settle')

        def press(label):
            settle()
            assert find(label).press() == 0
            settle()

        left = wait(lambda: find('Left lines'), 'Left grid missing')
        right = wait(lambda: find('Right lines'), 'Right grid missing')
        check(left.count('AXRows') == right.count('AXRows') == 599 and left.count('AXColumns') == 9, 'all rows and checkbox columns remain logically addressable')
        note = next(e for e in group.read('AXChildren') or [] if e.read('AXRole') == 'AXTextField' and e.read('AXValue') == 'Left note')

        def checkbox(table, column, row=598):
            cell = table.cell(column, row)
            return wait(lambda: next((e for e in cell.read('AXChildren') or [] if e.read('AXRole') == 'AXCheckBox'), None), 'Checkbox cell did not load')

        direct, focusable, mixed, numeric = [checkbox(left, column) for column in range(5, 9)]
        other = checkbox(right, 5)
        check([e.read('AXValue') for e in (direct, focusable, mixed, numeric)] == [0, 0, 2, 0], 'Boolean and integer controls expose typed unchecked and mixed states')
        check(direct.read('AXIdentifier') != other.read('AXIdentifier'), 'repeated grids keep separate checkbox identities')
        check(not direct.is_settable('AXFocused') and focusable.is_settable('AXFocused'), 'focus capabilities preserve the vendor column mode')
        check(not any(e.is_settable('AXValue') for e in (direct, focusable, mixed, numeric)), 'checkboxes expose activation instead of string assignment')
        blocked = checkbox(left, 5, 2)
        check(not blocked.read('AXEnabled') and 'AXPress' not in blocked.actions(), 'cell-level entry permission disables activation')
        for row in (3, 5):
            cell = left.cell(5, row)
            wait(lambda: cell.read('AXValue') == '', 'Hidden or protected checkbox leaked its state')
            check(not any(e.read('AXRole') == 'AXCheckBox' for e in cell.read('AXChildren') or []), 'hidden or protected checkbox state stays private')
        before = state()
        assert direct.press() == 0
        wait(lambda: state().get('leftControls', [None])[0] is True, 'Direct checkbox did not toggle')
        settle()
        after = state()
        check(after['leftStarts'] == before['leftStarts'] + 1 and after['leftEnds'] == before['leftEnds'] + 1,
              'non-focusable activation invokes existing entry and commit callbacks exactly once')
        check(after['rightControls'] == [False, False, 2, 0], 'activation changes only its owning repeated form')
        wait(lambda: direct.read('AXValue') == 1, 'Committed checkbox state did not publish')
        assert mixed.press() == 0
        wait(lambda: state().get('leftControls', [None] * 3)[2] != 2, 'Mixed checkbox did not activate')
        settle()
        check(state()['leftControls'][2] in (0, 1), 'three-state control uses the vendor transition from mixed')
        assert numeric.press() == 0
        wait(lambda: state().get('leftControls', [None] * 4)[3] == 1, 'Integer checkbox did not activate')
        settle()
        check(True, 'integer two-state checkbox uses normal vendor activation')
        before = state()
        assert focusable.set_boolean('AXFocused', True) == 0
        wait(lambda: state().get('editor', {}).get('column') == 9, 'Focusable checkbox did not enter its editor')
        settle()
        check(state()['leftControls'][1] is False and state()['editor']['checked'] == 0 and state()['leftStarts'] == before['leftStarts'] + 1,
              'keyboard focus opens the checkbox editor without changing its value')
        wait(lambda: focusable.read('AXFocused') is True, 'Checkbox did not report actual focus')
        assert focusable.press() == 0
        wait(lambda: state().get('editor', {}).get('checked') == 1, 'Focusable checkbox did not receive Space')
        settle()
        wait(lambda: focusable.read('AXValue') == 1, 'Uncommitted editor checkbox state did not publish')
        check(state()['leftControls'][1] is False and state()['leftEnds'] == before['leftEnds'], 'AX reports the uncommitted checkbox value without bypassing normal commit')
        press_key(process, project, TITLE, focusable.read('AXIdentifier'), 53)
        wait(lambda: not state().get('editor'), 'Escape did not leave the vendor editor')
        wait(lambda: focusable.read('AXValue') == 0, 'Cancelled checkbox value did not revert')
        check(state()['leftControls'][1] is False, 'ordinary Escape cancels the checkbox edit')
        assert focusable.press() == 0
        wait(lambda: state().get('editor', {}).get('checked') == 1, 'Second focusable activation failed')
        settle()
        assert note.set_boolean('AXFocused', True) == 0
        wait(lambda: state().get('leftControls', [None, None])[1] is True and not state().get('editor'), 'Normal focus transfer did not commit')
        settle()
        check(True, 'ordinary focus transfer commits through the existing vendor callback')
        text_cell = left.cell(1, 598)
        def text_editor_value():
            children = text_cell.read('AXChildren') or []
            return children[0].read('AXValue') if children else None
        wait(lambda: text_cell.read('AXValue') == 'Left line 0600', 'Text cell did not load')
        assert text_cell.set_text('Complete text before checkbox') == 0
        wait(lambda: text_editor_value() == 'Complete text before checkbox', 'Text editor did not receive complete value')
        settle()
        previous = state()['leftControls'][0]
        assert direct.press() == 0
        wait(lambda: state()['leftControls'][0] != previous, 'Checkbox did not activate after text editing')
        settle()
        check(state()['leftValue'] == 'Complete text before checkbox', 'checkbox activation commits the complete preceding text edit')
        wait(lambda: text_cell.read('AXValue') == 'Complete text before checkbox', 'Committed text did not refresh')
        assert text_cell.set_text('REJECT') == 0
        wait(lambda: text_editor_value() == 'REJECT', 'Rejected text did not enter')
        settle()
        previous = state()
        assert direct.press() == 0
        wait(lambda: state()['leftRejections'] > previous['leftRejections'], 'Text exit validation did not run before checkbox')
        settle()
        check(state()['leftControls'] == previous['leftControls'] and text_editor_value() == 'REJECT', 'rejected text exit prevents checkbox activation')
        assert text_cell.set_text('Corrected text before checkbox') == 0
        wait(lambda: text_editor_value() == 'Corrected text before checkbox', 'Corrected text did not enter')
        settle()
        assert direct.press() == 0
        wait(lambda: state()['leftControls'][0] != previous['leftControls'][0], 'Checkbox did not activate after text correction')
        settle()
        check(state()['leftValue'] == 'Corrected text before checkbox', 'corrected text permits normal checkbox activation')
        for mode, name in ((1, 'area'), (2, 'cell'), (3, 'column')):
            press('Edit')
            wait(lambda: state().get('permissionPhase') == mode and direct.read('AXEnabled') is False, 'Permission change did not publish')
            disabled = state()
            check('AXPress' not in direct.actions(), name + ' permissions remove the checkbox activation action')
            direct.press()
            wait(lambda: state().get('timerTicks', 0) > disabled['timerTicks'] + 2, 'Disabled action observation did not advance')
            check(state()['leftControls'] == disabled['leftControls'] and state()['leftStarts'] == disabled['leftStarts'],
                  name + ' permissions prevent mutation through a retained checkbox')
        press('Edit')
        wait(lambda: state().get('permissionPhase') == 4 and direct.read('AXEnabled') is True, 'Editable checkbox did not return')
        before_rejection = state()
        assert direct.press() == 0
        wait(lambda: state().get('leftRejections', 0) == before_rejection['leftRejections'] + 1, 'Existing validation did not run')
        settle()
        check(state()['leftControls'][0] == before_rejection['leftControls'][0] and group.read('AXHelp') == 'AreaList did not accept the checkbox state change',
              'application validation rejects the edit and its action receipt without bypass or retry')
        if state().get('editor'):
            focused = app.read('AXFocusedUIElement')
            press_key(process, project, TITLE, focused.read('AXIdentifier'), 53)
            wait(lambda: not state().get('editor'), 'Escape did not leave rejected vendor editing')
        press('Edit')
        identifier = direct.read('AXIdentifier')
        press('Sort')
        wait(lambda: left.cell(5, 0).read('AXChildren') and left.cell(5, 0).read('AXChildren')[0].read('AXIdentifier') == identifier, 'Sorted checkbox lost stable identity')
        check(True, 'checkbox identity follows its row key after vendor sorting')
        press('Loading')
        wait(lambda: direct.read('AXSize') in (None, (0, 0)), 'Loading left the old checkbox active')
        check('AXPress' not in direct.actions(), 'retired checkbox cannot mutate a replaced binding')
        press('Loading')
        if args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / 'alp-controls-voiceover', BUILD / 'read-fixture-screen')
            report['voiceover'] = vo.steps
            try:
                vo.start()
                caption = vo.key('home')
                for _ in range(20):
                    if 'Left lines' in caption and 'table' in caption.lower():
                        break
                    caption = vo.key('right')
                check('Left lines' in caption and 'table' in caption.lower(), 'VoiceOver reaches the repeated AreaList table')
                vo.key('down', shift=True)
                caption = vo.key('home')
                for _ in range(12):
                    if 'Direct' in caption and 'checkbox' in caption.replace(' ', '').lower():
                        break
                    caption = vo.key('right')
                check('Direct' in caption and 'checkbox' in caption.replace(' ', '').lower(), 'VoiceOver reads the checkbox label and control role')
                previous = state()
                vo.key('space')
                wait(lambda: state()['leftControls'][0] != previous['leftControls'][0], 'VoiceOver did not activate the existing checkbox')
                check(state()['leftStarts'] == previous['leftStarts'] + 1 and state()['leftEnds'] == previous['leftEnds'] + 1,
                      'VoiceOver activates the checkbox through the original entry and commit handlers')
                vo.key('up', shift=True)
                for _ in range(8):
                    caption = vo.key('right')
                    if 'Left note' in caption:
                        break
                check('Left note' in caption, 'VoiceOver leaves checkbox cells and reaches the ordinary form editor')
            finally:
                vo.stop()
        check(state()['leftError'] == state()['rightError'] == 0, 'provider calls leave the vendor error state clear')
        check(state()['timerTicks'] > before['timerTicks'], 'existing form timer continues during checkbox editing')
        assert find('Close').press() == 0
        process.wait(timeout=15)
        check(process.returncode == 0, 'normal host close succeeds')
        report['passed'] = True
    finally:
        if process.poll() is None:
            if group is not None:
                report['last_receipt'] = group.read('AXHelp')
            if not report['passed']:
                ax.capture_window(process.pid, BUILD / 'alp-controls-failure.png')
            process.terminate()
            process.wait(timeout=10)
        try:
            report['last_state'] = json.loads(status.read_text(encoding='utf-8-sig'))
        except (OSError, ValueError):
            pass
        name = 'alp-controls-voiceover-report.json' if args.voiceover else ('alp-controls-compiled-report.json' if args.compiled else 'alp-controls-interpreted-report.json')
        (BUILD / name).write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
