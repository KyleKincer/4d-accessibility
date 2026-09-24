#!/usr/bin/env python3
"""Exercise independent AreaList subforms through AX and ordinary input."""
import argparse
import ctypes as c
import json
import subprocess
import sys
import time

from build_component import sha
from prepare_alp_subforms import BUILD, FIXTURE, ROOT, TITLE
sys.path.insert(0, str(ROOT / 'tests'))
from mac_ax import Element, application, process_architecture, release, signature, trusted, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--mode', choices=('interpreted', 'compiled'), required=True)
    args = parser.parse_args()
    if not args.run or not trusted():
        parser.error('--run and Accessibility permission are required')
    pids = subprocess.run(['pgrep', '-x', '4D'], capture_output=True, text=True).stdout.split()
    if len(pids) != 1:
        parser.error('Launch the disposable ALPSubforms project')
    pid = int(pids[0])
    command = subprocess.check_output(['ps', '-p', str(pid), '-o', 'command='], text=True)
    if '--project ' + str(FIXTURE / 'Project/ALPSubforms.4DProject') not in command:
        parser.error('Refusing another 4D project')
    compiled = json.loads((BUILD / 'alp-subforms-compile-report.json').read_text())
    if not compiled.get('passed'):
        parser.error('Prepare and compile the fixture first')
    for relative, expected in compiled['sources_sha256'].items():
        if sha(FIXTURE / relative) != expected:
            parser.error('Source changed after compilation: ' + relative)
    for key, relative in [('component_sha256', 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ'),
                          ('native_sha256', 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge')]:
        if sha(FIXTURE / relative) != compiled.get(key):
            parser.error('Package changed after preparation: ' + relative)
    config = json.loads((FIXTURE / 'Resources/launch.json').read_text())
    report = {'passed': False, 'checks': [], 'mode': args.mode, **config,
              'action_seconds': [],
              'compile_report_sha256': sha(BUILD / 'alp-subforms-compile-report.json'),
              'process_architecture': process_architecture(pid)}

    def check(condition, name):
        report['checks'].append({'name': name, 'passed': bool(condition)})
        print(('PASS: ' if condition else 'FAIL: ') + name, flush=True)
        if not condition:
            raise AssertionError(name)

    def state():
        for name in ['callback-failure.json', 'vendor-error.json']:
            path = FIXTURE / 'Resources' / name
            if path.exists():
                raise AssertionError(path.read_text(encoding='utf-8-sig'))
        try:
            data = json.loads((FIXTURE / 'Resources/runtime-status.json').read_text(encoding='utf-8-sig'))
        except (ValueError, OSError):
            return {}
        if data.get('phase') == 'failed':
            raise AssertionError(str(data))
        return data

    def walk(element):
        yield element
        for child in element.read('AXChildren') or []:
            if isinstance(child, Element):
                yield from walk(child)

    try:
        ready = wait_for(lambda: state() if state().get('runId') == config['runId'] else None, 'No current launch state', 15)
        check(ready['compiled'] is (args.mode == 'compiled'), 'actual host mode matches request')
        check(ready['left']['area'] > 0 and ready['right']['area'] > 0 and ready['left']['area'] != ready['right']['area'], 'repeated plugin object has distinct native area IDs')
        windows = [w for w in application(pid).read('AXWindows') or [] if w.read('AXTitle') == TITLE]
        check(len(windows) == 1, 'exact AreaList subform window is open')
        window = windows[0]
        group = wait_for(lambda: next((e for e in walk(window) if (e.read('AXIdentifier') or '').startswith('axb.window.')), None), 'Missing bridge group')

        def settle():
            wait_for(lambda: group.read('AXHelp') not in (None, 'Action queued', 'Waiting for the application to complete the action'), 'Missing native acknowledgment')

        def send(request):
            settle()
            before = (state().get('receipt') or {}).get('id')
            started = time.monotonic()
            code = request()
            wait_for(lambda: (state().get('receipt') or {}).get('id') not in (None, before), 'Missing application receipt')
            settle()
            report['action_seconds'].append(time.monotonic() - started)
            check(code == 0 and state()['receipt']['status'] == 'completed', 'application confirms requested action')

        def table(side):
            return next((e for e in walk(window) if e.read('AXRole') == 'AXTable' and e.read('AXDescription') == side + ' lines: ' + side + ' lines'), None)

        def row(side, key):
            return next((e for e in table(side).read('AXRows') or [] if (e.read('AXIdentifier') or '').endswith('.lines.' + key)), None)

        def rows(side):
            return table(side).read('AXRows') or []

        wait_for(lambda: table('Left') and table('Right') and len(rows('Right')) > 0, 'Both child grids must publish rows')
        check(0 < len(rows('Left')) < 200 and len(rows('Left')) == len(rows('Right')), 'both viewports publish only their visible rows')
        check(len(state()['left']['nodes']) < 201 and len(state()['right']['nodes']) < 201, 'two 200-row bindings publish viewport nodes within the shared budget')
        check(state()['left']['nodes'][1]['frame'] == state()['right']['nodes'][1]['frame'], 'AreaList window coordinates convert to the same child-local frame')
        left, right = row('Left', 'line-003'), row('Right', 'line-003')
        check(left.read('AXIdentifier') != right.read('AXIdentifier'), 'same stable key in repeated children has different AX identity')
        for side in ['Left', 'Right']:
            cell = row(side, 'line-003').read('AXChildren')[0]
            x, y = cell.read('AXPosition'); width, height = cell.read('AXSize')
            check(application(pid).at_position(x + width / 2, y + height / 2).read('AXIdentifier') == cell.read('AXIdentifier'),
                  side + ' vendor cell is discoverable by external screen-position lookup')
            tx, ty = table(side).read('AXPosition')
            tw, th = table(side).read('AXSize')
            check(all(tx <= r.read('AXPosition')[0] < tx + tw and ty <= r.read('AXPosition')[1] < ty + th
                      and r.read('AXPosition')[1] + r.read('AXSize')[1] <= ty + th for r in rows(side)), side + ' row frames stay inside the correct grid')
        send(lambda: table('Left').set_elements('AXSelectedRows', [left]))
        wait_for(lambda: state()['left']['selected'] == ['line-003'], 'Left selection not applied')
        check(state()['right']['selected'] == [], 'left selection leaves the sibling unchanged')
        send(lambda: table('Right').set_elements('AXSelectedRows', [right]))
        wait_for(lambda: state()['right']['selected'] == ['line-003'], 'Right selection not applied')
        check(state()['left']['selected'] == ['line-003'], 'right selection leaves the sibling unchanged')

        # An actual click at the published row frame verifies its geometry and
        # the vendor's ordinary selection path, independently of AX routing.
        graphics = c.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
        class Point(c.Structure):
            _fields_ = [('x', c.c_double), ('y', c.c_double)]
        create_mouse = signature(graphics, 'CGEventCreateMouseEvent', c.c_void_p, c.c_void_p, c.c_uint32, Point, c.c_uint32)
        post = signature(graphics, 'CGEventPost', None, c.c_uint32, c.c_void_p)
        set_integer = signature(graphics, 'CGEventSetIntegerValueField', None, c.c_void_p, c.c_uint32, c.c_longlong)
        def click(x, y, count=1):
            if application(pid).read('AXFrontmost') is not True:
                raise AssertionError('Fixture lost foreground before physical input')
            for kind in (5, 1, 2):
                event = create_mouse(None, kind, Point(x, y), 0)
                set_integer(event, 1, count)
                post(0, event)
                release(event)
                time.sleep(.08)
        target = row('Right', 'line-005')
        x, y = target.read('AXPosition'); width, height = target.read('AXSize')
        click(x + width / 2, y + height / 2)
        wait_for(lambda: state()['right']['selected'] == ['line-005'], 'Click at AX frame selected the wrong row')
        check(state()['left']['selected'] == ['line-003'], 'physical click at published right-row frame selects only that row')
        create_key = signature(graphics, 'CGEventCreateKeyboardEvent', c.c_void_p, c.c_void_p, c.c_uint16, c.c_bool)
        set_flags = signature(graphics, 'CGEventSetFlags', None, c.c_void_p, c.c_uint64)
        if application(pid).read('AXFrontmost') is not True:
            raise AssertionError('Fixture lost foreground before key')
        for down in [True, False]:
            event = create_key(None, 125, down)
            set_flags(event, 0)
            post(0, event); release(event); time.sleep(.08)
        wait_for(lambda: state()['right']['selected'] == ['line-006'], 'Ordinary Down arrow failed to move AreaList selection')
        check(True, 'ordinary keyboard selection continues after AX and mouse interaction')
        target = row('Right', 'line-006')
        check(target.is_settable('AXValue') is False, 'selection-only row exposes no AX text-write action')
        target.set_text('Unapproved AX edit')
        time.sleep(.25)
        check(target.read('AXValue') == 'DUPLICATE-SKU; Right line 6', 'unsupported AX write leaves application value unchanged')
        x, y = target.read('AXPosition'); width, height = target.read('AXSize')
        click(x + 280, y + height / 2)
        click(x + 280, y + height / 2, 2)
        set_unicode = signature(graphics, 'CGEventKeyboardSetUnicodeString', None, c.c_void_p, c.c_ulong, c.POINTER(c.c_uint16))
        def key(code, flags=0, text=None):
            if application(pid).read('AXFrontmost') is not True:
                raise AssertionError('Fixture lost foreground before edit')
            for down in [True, False]:
                event = create_key(None, code, down)
                set_flags(event, flags)
                if text is not None:
                    encoded = text.encode('utf-16-le')
                    chars = (c.c_uint16 * (len(encoded) // 2)).from_buffer_copy(encoded)
                    set_unicode(event, len(chars), chars)
                post(0, event); release(event); time.sleep(.08)
        # Send one character as a real key event. AreaList's legacy editor reads
        # one character per event, unlike ordinary Cocoa multi-character input.
        key(7, text='X')
        key(48)  # Tab commits through AreaList's normal data-entry path.
        key(53)  # Leave the next editor without changing that cell.
        wait_for(lambda: any(n.get('label') == 'DUPLICATE-SKU; Right line 6X' for n in state()['right']['nodes']), 'Ordinary cell edit was not committed and republished')
        check(True, 'ordinary cell editor commits and the row label refreshes')
        send(lambda: table('Right').set_elements('AXSelectedRows', [row('Right', 'line-006')]))
        wait_for(lambda: state()['right']['selected'] == ['line-006'], 'Selection did not resume after editing')
        for _ in range(20):
            key(125)
        wait_for(lambda: state()['right']['selected'] == ['line-026'] and row('Right', 'line-026'), 'Keyboard scrolling did not refresh the published viewport')
        check(row('Right', 'line-003') is None, 'ordinary keyboard scrolling exposes later rows and removes offscreen rows')
        right.press(); time.sleep(.3)
        check(state()['right']['selected'] == ['line-026'], 'retained offscreen row cannot change the scrolled selection')
        for _ in range(25):
            key(126)
        for _ in range(5):
            key(125)
        wait_for(lambda: state()['right']['selected'] == ['line-006'] and row('Right', 'line-003'), 'Keyboard navigation did not restore the original viewport')
        right = row('Right', 'line-003')
        check(True, 'ordinary keyboard navigation restores rows with usable fresh elements')
        send(lambda: window.find('.hide').press())
        wait_for(lambda: table('Left') is None, 'Hidden subform still exposed')
        old_selection = state()['left']['selected']
        left.press(); time.sleep(.35)
        check(state()['left']['selected'] == old_selection, 'retained hidden-child row cannot change selection')
        send(lambda: window.find('.hide').press())
        wait_for(lambda: table('Left') is not None, 'Shown subform did not return')
        send(lambda: window.find('.disable').press())
        check(table('Right').read('AXEnabled') is False, 'disabled ancestor disables its grid')
        right.press(); time.sleep(.35)
        check(state()['right']['selected'] == ['line-006'], 'retained disabled-child row cannot change selection')
        send(lambda: window.find('.disable').press())
        old_left = row('Left', 'line-003')
        old_id = old_left.read('AXIdentifier')
        send(lambda: window.find('.replace').press())
        wait_for(lambda: state().get('oldLeftStopped'), 'Old child not stopped before replacement')
        check(row('Left', 'line-003').read('AXIdentifier') != old_id, 'replaced child receives new AX identity')
        old_left.press(); time.sleep(.35)
        check(state()['left']['selected'] == [], 'retained replaced-child row cannot affect its replacement')
        old_record_row = row('Left', 'line-003')
        old_record_id = old_record_row.read('AXIdentifier')
        send(lambda: window.find('.reload').press())
        wait_for(lambda: table('Left') is None, 'Loading child still publishes incomplete bindings')
        check(table('Right') is not None, 'parent readiness gate removes only the loading child')
        old_record_row.press(); time.sleep(.3)
        check(state()['left']['selected'] == [], 'retained row cannot select during reload')
        send(lambda: window.find('.loaded').press())
        wait_for(lambda: table('Left') is not None, 'Loaded child did not resume')
        check(row('Left', 'line-003').read('AXIdentifier') != old_record_id, 'new record scope changes identity even with identical line keys')
        old_record_row.press(); time.sleep(.3)
        check(state()['left']['selected'] == [], 'retained old-record row cannot select the replacement record')
        send(lambda: window.find('.badkey').press())
        wait_for(lambda: len(state()['left']['nodes']) == 1 and not state()['left']['nodes'][0]['enabled'], 'Offscreen duplicate was ignored')
        check(True, 'offscreen duplicate key disables the whole adapter')
        send(lambda: window.find('.badkey').press())
        wait_for(lambda: table('Left') is not None and len(rows('Left')) > 0, 'Repaired keys did not restore rows')
        send(lambda: window.find('.identity').press())
        wait_for(lambda: row('Left', 'Case') and row('Left', 'case') and row('Left', 'café') and row('Left', 'cafe'), 'Case/accent keys were conflated')
        for key in ['Case', 'case', 'café', 'cafe']:
            send(lambda: table('Left').set_elements('AXSelectedRows', [row('Left', key)]))
            wait_for(lambda: state()['left']['selected'] == [key], 'Exact stable key not selected: ' + key)
            check(True, 'exact stable key survives selection: ' + key)
        send(lambda: table('Left').set_elements('AXSelectedRows', [row('Left', 'Case'), row('Left', 'case')]))
        wait_for(lambda: state()['left']['selected'] == ['Case', 'case'], 'Case-distinct multiselection failed')
        check(True, 'case-distinct rows can be selected together')
        # Use the real parent object method for sorting, then verify stable IDs
        # follow the reordered parallel arrays and leave the other area intact.
        click(*state()['screenCenters']['Sort'])
        wait_for(lambda: state()['humanEvents'] == 1 and state()['left']['nodes'][1]['id'] == 'lines.line-200', 'Human sort did not reorder arrays')
        wait_for(lambda: row('Left', 'line-200'), 'Sorted row was not published')
        send(lambda: table('Left').set_elements('AXSelectedRows', [row('Left', 'line-200')]))
        wait_for(lambda: state()['left']['selected'] == ['line-200'], 'Sorted identity mapped to wrong row')
        check(state()['right']['selected'] == ['line-006'], 'human sorting preserves sibling data and AX selects reordered key')
        check(state()['timerFirings'] > 2, 'existing parent timer keeps running')
        check(not (FIXTURE / 'Resources/vendor-error.json').exists(), 'no sticky AreaList error occurred')
        report['final_state'] = state()
        click(*state()['screenCenters']['Close'])
        path = FIXTURE / 'Resources/closed.json'
        wait_for(path.exists, 'Ordinary close did not finish')
        closed = json.loads(path.read_text(encoding='utf-8-sig'))
        check(closed['runId'] == config['runId'] and closed['closed'] and closed['stopped'], 'ordinary close detaches root bridge')
        wait_for(lambda: str(pid) not in subprocess.run(['pgrep', '-x', '4D'], capture_output=True, text=True).stdout.split(), 'Fixture failed to quit')
        report['passed'] = True
    finally:
        (BUILD / ('alp-subforms-' + args.mode + '-report.json')).write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
