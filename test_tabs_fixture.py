#!/usr/bin/env python3
"""Read and activate real 4D tabs through external macOS accessibility."""
import argparse
import json
import subprocess
import sys
import time
from build_component import sha
from prepare_tabs_fixture import BUILD, FIXTURE, ROOT, TITLE
sys.path.insert(0, str(ROOT / 'tests'))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--compiled', action='store_true')
    parser.add_argument('--voiceover', action='store_true')
    parser.add_argument('--restart-only', action='store_true', help='Run the shortest open-form registration recovery check')
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error('--run and Accessibility permission are required')
    ax.require_test_input()
    if args.voiceover:
        from voiceover import VoiceOver
        if VoiceOver.pids('VoiceOver') or VoiceOver.pids('VoiceOver Quickstart'):
            parser.error('An existing VoiceOver session belongs to the user')
        subprocess.run(['xcrun', 'swiftc', str(ROOT / 'tests/ReadScreen.swift'), '-o', str(BUILD / 'read-fixture-screen')], check=True)
    for name in ('4D', '4D Server'):
        if subprocess.run(['pgrep', '-x', name], capture_output=True).returncode == 0:
            parser.error('Close 4D before this sequential fixture')
    compile_report = json.loads((BUILD / 'tabs-compile-report.json').read_text())
    narrow = compile_report.get('narrow', False)
    if not compile_report['passed']:
        parser.error('Prepare the tabs fixture first')
    for relative, digest in compile_report['sources_sha256'].items():
        if sha(FIXTURE / relative) != digest:
            parser.error('Fixture changed after compilation: ' + relative)
    for key, relative in (('component_sha256', 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ'),
                          ('native_sha256', 'Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge')):
        if sha(FIXTURE / relative) != compile_report[key]:
            parser.error('Fixture package changed after compilation')
    config = json.loads((FIXTURE / 'Resources/launch.json').read_text())
    for name in ('runtime-status.json', 'errors.json', 'closed.json'):
        (FIXTURE / 'Resources' / name).unlink(missing_ok=True)
    report = {'passed': False, 'checks': [], 'compiled': args.compiled, 'generated': compile_report['generated'],
        'voiceoverRequested': args.voiceover, 'restartOnly': args.restart_only, 'narrow': narrow, 'icons': compile_report.get('icons', False), 'scrollIcons': compile_report.get('scrollIcons', False),
        'clippedChildren': compile_report.get('clippedChildren', False),
        'native_sha256': compile_report['native_sha256'], 'component_sha256': compile_report['component_sha256'],
        'compile_report_sha256': sha(BUILD / 'tabs-compile-report.json')}
    last_state = {}

    def state():
        nonlocal last_state
        errors = FIXTURE / 'Resources/errors.json'
        if errors.exists():
            raise AssertionError(errors.read_text(encoding='utf-8-sig'))
        try:
            result = json.loads((FIXTURE / 'Resources/runtime-status.json').read_text(encoding='utf-8-sig'))
        except (OSError, ValueError):
            return last_state
        if result.get('runId') == config['runId']:
            last_state = result
        if last_state.get('failure'):
            raise AssertionError(json.dumps(last_state['failure']))
        return last_state

    def check(condition, description):
        report['checks'].append({'name': description, 'passed': bool(condition)})
        assert condition, description
        print('PASS: ' + description, flush=True)

    project = FIXTURE / 'Project/Tabs.4DProject'
    with (BUILD / 'tabs-desktop.log').open('w') as log:
        process = subprocess.Popen(['/Applications/4D/4D.app/Contents/MacOS/4D', '--project', str(project), '--dataless',
            '--opening-mode', 'compiled' if args.compiled else 'interpreted', '--webadmin-auto-start', 'false'], stdout=log, stderr=log)
        try:
            ready, _ = wait_for_start(process, project, state, BUILD)
            check(ready['compiled'] is args.compiled, 'actual requested desktop mode')
            report['architecture'] = ax.process_architecture(process.pid)
            app, window = activate_fixture(process, project, TITLE)
            group = ax.wait_for(lambda: next((e for e in window.read('AXChildren') or []
                if str(e.read('AXIdentifier')).startswith('axb/')), None), 'Area-owned provider', timeout=20)

            def find(label):
                pending = list(group.read('AXChildren') or [])
                while pending:
                    element = pending.pop(0)
                    if element.read('AXDescription') == label and element.read('AXRole') != 'AXStaticText':
                        return element
                    pending.extend(element.read('AXChildren') or [])
                return None

            def settle():
                def receipt_ready():
                    state()
                    return group.read('AXHelp') not in (None, 'Action queued', 'Waiting for the application to complete the action')
                ax.wait_for(receipt_ready,
                    'Final action receipt', timeout=20)
                assert 'rejected' not in str(group.read('AXHelp')).lower(), group.read('AXHelp')

            ax.wait_for(lambda: find('Page 1 text') and find('Page 1 text').read('AXFocused') == 1,
                '4D initial editor focus', timeout=20)
            categories = ax.wait_for(lambda: find('Categories'), 'Array tab group', timeout=20)
            pages = ax.wait_for(lambda: find('Pages'), 'Object tab group', timeout=20)
            choices = ax.wait_for(lambda: find('List choices'), 'List tab group', timeout=20)
            def assert_locators():
                pending = [group]
                identifiers = []
                while pending:
                    element = pending.pop()
                    identifier = element.read('AXIdentifier')
                    if identifier:
                        identifiers.append(identifier)
                    pending.extend(element.read('AXChildren') or [])
                check(len(identifiers) == len(set(identifiers)), 'root, controls, repeated children and synthesized tabs have unique public locators')
                check(pages.read('AXIdentifier').endswith('/ObjectTabs') and
                    all(t.read('AXIdentifier').startswith(pages.read('AXIdentifier')+'/tab/') for t in pages.read('AXTabs') or []),
                    'tab choices have distinct stable child paths under their object name')
            assert_locators()
            def restart():
                nonlocal group, categories, pages, choices
                previous_group = group
                previous_categories = categories
                previous_children = categories.read('AXTabs') or []
                previous_id = group.read('AXIdentifier')
                original_state = state()
                bindings = {key: original_state.get(key) for key in
                    ('array', 'index', 'page', 'bottomIndex', 'narrowObject', 'narrowList', 'leftChild', 'rightChild')}
                tab_events = [e for e in original_state['events'] if e['object'].endswith('Tabs')]
                check(find('Restart accessibility').press() == 0, 'restart request accepted through accessibility')
                group = ax.wait_for(lambda: next((e for e in window.read('AXChildren') or []
                    if str(e.read('AXIdentifier')).startswith('axb/') and
                    not e.same_as(previous_group)), None),
                    'Replacement area-owned provider', timeout=20)
                categories = ax.wait_for(lambda: find('Categories'), 'Tabs after registration restart', timeout=20)
                pages = ax.wait_for(lambda: find('Pages'), 'Page tabs after registration restart', timeout=20)
                choices = ax.wait_for(lambda: find('List choices'), 'List tabs after registration restart', timeout=20)
                ax.wait_for(lambda: state() and categories.read('AXRole') == ('AXPopUpButton' if narrow else 'AXTabGroup') and
                    (narrow or len(categories.read('AXTabs') or []) == 3) and
                    len(pages.read('AXTabs') or []) == len(choices.read('AXTabs') or []) == 3 and
                    (child := find('RightChild: Sections')) and len(child.read('AXTabs') or []) == 2,
                    'Repainted tab choices after restart', timeout=20)
                check(categories.read('AXRole') == ('AXPopUpButton' if narrow else 'AXTabGroup') and
                    pages.read('AXRole') == choices.read('AXRole') == 'AXTabGroup' and
                    len(find('RightChild: Sections').read('AXTabs') or []) == 2,
                    'restart restores original tab presentations and repeated child choices')
                after = state()
                check(all(after.get(key) == value for key, value in bindings.items()) and
                    [e for e in after['events'] if e['object'].endswith('Tabs')] == tab_events,
                    'restart preserves bindings and tab business handlers')
                check(previous_group.read('AXRole') is None and previous_categories.read('AXRole') is None and
                    all(t.press() != 0 for t in previous_children), 'restart retires the former tree and tab choices')
                check(group.read('AXIdentifier') == previous_id, 'restart preserves the logical screen locator')
                assert_locators()
            if args.restart_only:
                restart()
                check(find('Close fixture').press() == 0, 'restarted form closes through its ordinary action')
                process.wait(timeout=20)
                report['passed'] = True
                return

            def native_choices(target=None):
                assert (target or categories).press() == 0, 'Fallback popup activation rejected'
                menu = ax.wait_for(lambda: next((e for e in window.read('AXChildren') or [] if e.read('AXRole') == 'AXMenu'), None),
                    'Original fallback popup menu', timeout=20)
                return menu, menu.read('AXChildren') or []

            def select_array(slot):
                if narrow:
                    _, current = native_choices()
                    return current[slot].press()
                return categories.read('AXTabs')[slot].press()
            for label in ('Static choices', 'Bottom choices', 'LeftChild: Sections', 'RightChild: Sections', 'Empty choices',
                'Compact object choices', 'Compact list choices'):
                ax.wait_for(lambda label=label: find(label), label, timeout=20)
            check(all(e.read('AXRole') == 'AXTabGroup' for e in (pages, choices)), 'object and list sources expose native tab-group semantics')
            check(all(t.read('AXSubrole') == 'AXTabButton' for e in (pages, choices) for t in e.read('AXTabs')),
                'tab choices expose the native tab-button subrole')
            if narrow:
                check(categories.read('AXRole') == 'AXPopUpButton' and categories.read('AXValue') == 'Short', 'narrow tabs expose their actual popup presentation and value')
                before = state()
                menu, tabs = native_choices()
                check([t.read('AXTitle') for t in tabs] == ['Short', 'A much longer label', '🎹 Final tab'], 'native fallback menu exposes every actual choice')
                check(menu.perform('AXCancel') == 0, 'native fallback menu can be dismissed through accessibility')
                settle()
                check(state()['array'] == before['array'] and state()['events'] == before['events'], 'inspecting and dismissing the menu preserves business selection and handlers')
            else:
                check(categories.read('AXRole') == 'AXTabGroup', 'array source exposes native tab-group semantics')
                tabs = categories.read('AXTabs')
                check([t.read('AXDescription') for t in tabs] == ['Short', 'A much longer label', '🎹 Final tab'], 'all array choices have their actual visible names')
                check(all(t.read('AXRole') == 'AXRadioButton' for t in tabs), 'tab children have native selection semantics')
                check([t.read('AXValue') for t in tabs] == [1, 0, 0], 'initial selected tab is truthful')
                check(len(categories.read('AXSelectedChildren')) == 1, 'group relates its selected tab')
                check(categories.read('AXValue').read('AXIdentifier') == tabs[0].read('AXIdentifier'), 'tab-group value identifies its selected child')
            report['tabGeometry'] = [{'label': t.read('AXDescription'), 'position': t.read('AXPosition'), 'size': t.read('AXSize')}
                for t in ([categories] if narrow else tabs)]
            if not narrow:
                widths = [t.read('AXSize')[0] for t in tabs]
                check(widths[1] > widths[0] and widths[1] > widths[2], 'native geometry preserves unequal label widths')
                check(all(t.read('AXParent').read('AXIdentifier') == categories.read('AXIdentifier') for t in tabs), 'parent and child relationships agree')
            check(not find('Empty choices').read('AXTabs'), 'empty source has no invented choice')
            static = find('Static choices').read('AXTabs')
            check([t.read('AXDescription') for t in static] == ['Static first', 'Static last'], 'static choice lists expose their labels')
            check(static[1].press() == 0, 'static choice activation accepted')
            settle()
            ax.wait_for(lambda: static[1].read('AXValue') == 1, 'Static choice selection', timeout=20)
            bottom = find('Bottom choices').read('AXTabs')
            check(bottom[1].press() == 0, 'bottom-aligned choice activation accepted')
            settle()
            ax.wait_for(lambda: state()['bottomIndex'] == 1, 'Bottom-aligned native selection', timeout=20)
            left = find('LeftChild: Sections').read('AXTabs')
            right = find('RightChild: Sections').read('AXTabs')
            if compile_report.get('clippedChildren'):
                before = state()
                check(left[1].perform('AXScrollToVisible') == 0, 'clipped child tab can be revealed through accessibility')
                settle()
                x, y = ax.wait_for(lambda: left[1].read('AXPosition'), 'Retained tab after scrolling', timeout=5)
                width, height = left[1].read('AXSize')
                check(app.at_position(x + width/2, y + height/2).read('AXIdentifier') == left[1].read('AXIdentifier'),
                    'revealed child tab has its actual visible hit target')
                check(state()['leftChild'] == before['leftChild'] and state()['rightChild'] == before['rightChild'],
                    'revealing a tab preserves selection and child handlers')
            check(left[1].press() == 0, 'repeated child tab activation accepted')
            settle()
            ax.wait_for(lambda: state()['leftChild']['tabs']['index'] == 1, 'Left child tab selection', timeout=20)
            check(state()['rightChild']['tabs']['index'] == 0 and not state()['rightChild']['events'], 'child action preserves its identically named sibling')
            check(len([e for e in state()['leftChild']['events'] if e['object'] == 'Tabs' and e['event'] == 4]) == 1,
                'repeated child retains its original click handler exactly once')
            check(right[1].press() == 0, 'second repeated child activation accepted')
            settle()
            ax.wait_for(lambda: state()['rightChild']['tabs']['index'] == 1, 'Right child tab selection', timeout=20)
            previous_pages = pages
            previous_page_tabs = pages.read('AXTabs')
            check(find('Collapse or restore tabs').press() == 0, 'original collapse handler accepted')
            settle()
            ax.wait_for(lambda: find('Pages') is None, 'Collapsed tab group leaves the tree', timeout=20)
            check(previous_pages.read('AXRole') is None and all(t.press() != 0 for t in previous_page_tabs),
                'collapsed tabs retire their retained group and children')
            check(categories.read('AXRole') is not None and find('Page 1 text').read('AXEnabled') == 1 and state()['index'] == 0,
                'collapsed tabs preserve the rest of the form and selected data')
            check(find('Collapse or restore tabs').press() == 0, 'original restore handler accepted')
            settle()
            pages = ax.wait_for(lambda: (e if (e := find('Pages')) and len(e.read('AXTabs') or []) == 3 else None),
                'Restored tab group', timeout=20)
            for label, names, source, expected in (
                ('Compact object choices', ['Bound one', 'Bound two', 'Bound three'], 'narrowObject', 2),
                ('Compact list choices', ['Compact first', 'Compact second longer label', 'Compact last'], 'narrowList', {'reference': 203, 'label': 'Compact last'}),
            ):
                target = find(label)
                if source == 'narrowList' and compile_report.get('scrollIcons'):
                    names += [f'Compact extra {i}' for i in range(4, 13)]
                    expected = {'reference': 212, 'label': names[-1]}
                slot = len(names)-1
                strip = target.read('AXRole') == 'AXTabGroup'
                if strip:
                    assert compile_report.get('icons'), 'Unexpected compact tab presentation'
                    current = target.read('AXTabs')
                    check([item.read('AXDescription') for item in current] == names, label + ' icon strip retains every actual choice')
                else:
                    check(target.read('AXRole') == 'AXPopUpButton' and target.read('AXValue') == names[0], label + ' has its actual compact presentation and value')
                    _, current = native_choices(target)
                    check([t.read('AXTitle') for t in current] == names, label + ' keeps every native menu choice')
                check(current[slot].press() == 0, label + ' accepts native selection')
                settle()
                ax.wait_for(lambda: state()[source] == expected and (current[slot].read('AXValue') == 1 if strip else target.read('AXValue') == names[slot]),
                    label + ' selection and readback', timeout=20)
            before = state()
            for _ in range(15):
                categories.read('AXTabs'); categories.read('AXSelectedChildren')
                for t in tabs:
                    t.read('AXValue'); t.read('AXPosition'); t.read('AXSize')
            after = state()
            check(before['array'] == after['array'] and before['index'] == after['index'] and before['events'] == after['events'],
                'inspection leaves selection, page and original handlers unchanged')
            for slot in (2, 1, 0):
                prior = len([event for event in state()['events'] if event['object'] == 'ArrayTabs' and event['event'] == 4])
                check(select_array(slot) == 0, 'array choice activation accepted: ' + str(slot + 1))
                settle()
                ax.wait_for(lambda: state()['array'] == slot + 1, 'Requested array selection', timeout=20)
                events = [event for event in state()['events'] if event['object'] == 'ArrayTabs' and event['event'] == 4]
                check(len(events) == prior + 1 and events[-1]['array'] == slot + 1, 'one original click handler without intermediate selection: ' + str(slot + 1))
                ax.wait_for(lambda: categories.read('AXValue') == ['Short', 'A much longer label', '🎹 Final tab'][slot] if narrow else tabs[slot].read('AXValue') == 1,
                    'Selected choice readback', timeout=20)
            old_page = find('Page 1 text')
            page_tabs = pages.read('AXTabs')
            check(page_tabs[2].press() == 0, 'third page activation accepted')
            ax.wait_for(lambda: state()['page'] == 3 and state()['index'] == 2, 'Original gotoPage action', timeout=20)
            settle()
            check(find('Page 3 text') is not None and find('Page 1 text') is None, 'inactive page leaves the tree and the selected content is reachable')
            check(find('Page 3 text').read('AXIdentifier') in [e.read('AXIdentifier') for e in page_tabs[2].read('AXLinkedUIElements') or []],
                'selected standard-action tab relates to the actual active page content')
            check(not page_tabs[0].read('AXLinkedUIElements'), 'inactive choice does not claim active page content')
            check(old_page.set_text('stale write') != 0, 'retained inactive-page field cannot be edited')
            check(find('Page 3 text').set_text('AX page three') == 0, 'selected page retains native field editing')
            ax.wait_for(lambda: find('Page 3 text').read('AXValue') == 'AX page three', 'Selected-page native input', timeout=20)
            settle()
            check(page_tabs[0].press() == 0, 'first page activation accepted')
            ax.wait_for(lambda: state()['page'] == 1 and state()['page3'] == 'AX page three', 'Normal editor commit before page navigation', timeout=20)
            settle()
            check(find('Page 1 text') is not None, 'returning page is accessible')
            list_tabs = choices.read('AXTabs')
            check([t.read('AXDescription') for t in list_tabs] == ['List first', 'List second longer label', 'List last'], 'list references remain private and labels are readable')
            prior = len([e for e in state()['events'] if e['object'] == 'ListTabs' and e['event'] == 4])
            check(list_tabs[2].press() == 0, 'list tab activation accepted')
            ax.wait_for(lambda: len([e for e in state()['events'] if e['object'] == 'ListTabs' and e['event'] == 4]) == prior + 1,
                'Original list tab handler', timeout=20)
            settle()
            ax.wait_for(lambda: list_tabs[2].read('AXValue') == 1, 'Selected list choice', timeout=20)
            check(find('Relabel choice').press() == 0, 'original relabel action accepted')
            settle()
            if narrow:
                menu, new_tabs = native_choices()
                check(new_tabs[1].read('AXTitle') == 'Replacement label', 'fallback menu refreshes its original labels')
                assert menu.perform('AXCancel') == 0
                settle()
            else:
                ax.wait_for(lambda: any(t.read('AXDescription') == 'Replacement label' for t in categories.read('AXTabs') or []), 'Live replacement label', timeout=20)
                new_tabs = categories.read('AXTabs')
            if narrow:
                before = state()
                report['dismissedNativeChoiceStatus'] = tabs[1].press()
                time.sleep(0.5)
                check(state()['array'] == before['array'] and state()['events'] == before['events'], 'dismissed native menu cannot mutate the application')
            else:
                check(tabs[1].press() != 0, 'retained choice retires when labels are replaced')
            check(select_array(1) == 0, 'replacement choice activates through its current native presentation')
            ax.wait_for(lambda: state()['array'] == 2, 'Replacement selected tab', timeout=20)
            settle()
            if args.voiceover:
                vo = VoiceOver(process, project, TITLE, BUILD / 'tabs-voiceover', BUILD / 'read-fixture-screen')
                report['voiceover'] = vo.steps

                def read_key(key, **modifiers):
                    caption = vo.key(key, **modifiers)
                    assert 'not responding' not in caption.lower(), caption
                    return caption

                def reach(label, limit=10, require_group=False):
                    for _ in range(limit):
                        caption = read_key('right')
                        if label in caption and (not require_group or 'group' in caption.lower()):
                            return caption
                    raise AssertionError('VoiceOver did not reach ' + label)

                try:
                    vo.start()
                    caption = read_key('home', command=True)
                    for _ in range(4):
                        if 'close button' in caption.lower().replace(',', ''):
                            break
                        caption = read_key('home', command=True)
                    check('close button' in caption.lower().replace(',', ''), 'VoiceOver reaches the native window')
                    reach(TITLE, require_group=True)
                    read_key('down', shift=True)
                    before = state()
                    caption = read_key('home')
                    if 'Categories' not in caption:
                        caption = reach('Categories')
                    check(('pop' if narrow else 'tab') in caption.lower(), 'VoiceOver describes the actual array choice presentation')
                    if not narrow:
                        read_key('down', shift=True)
                        read_key('home')
                        caption = reach('Final tab', limit=5)
                        check('tab' in caption.lower() and 'radio button' not in caption.lower(), 'VoiceOver describes the choice as a tab')
                    check(state()['events'] == before['events'] and state()['array'] == before['array'],
                        'VoiceOver inspection does not select tabs or run original handlers')
                    prior = len([e for e in state()['events'] if e['object'] == 'ArrayTabs' and e['event'] == 4])
                    caption = read_key('space')
                    if narrow:
                        caption = read_key('down', voiceover=False)
                        check('Final tab' in caption, 'VoiceOver reads the actual compact menu choice')
                        read_key('return', voiceover=False)
                    ax.wait_for(lambda: state()['array'] == 3, 'VoiceOver requested array selection', timeout=20)
                    settle()
                    events = [e for e in state()['events'] if e['object'] == 'ArrayTabs' and e['event'] == 4]
                    check(len(events) == prior + 1, 'VoiceOver activation runs one original tab handler')
                    if narrow:
                        check(categories.read('AXValue') == '🎹 Final tab', 'VoiceOver compact menu has truthful selected readback')
                    else:
                        check(new_tabs[2].read('AXValue') == 1, 'VoiceOver activation has truthful selected readback')
                        caption = ax.wait_for(lambda: (spoken if 'selected' in (spoken := vo.read_caption()).lower() and 'Final tab' in spoken else None),
                            'VoiceOver selected-tab feedback without moving its cursor', timeout=5)
                        report['selectedTabSpeech'] = caption
                        check('selected' in caption.lower(), 'VoiceOver announces the completed tab selection')
                        read_key('up', shift=True)
                    # A dismissed AppKit menu restores prior keyboard focus.
                    # Resume linear reading at the form start in either layout.
                    read_key('home')
                    reach('List choices')
                    read_key('down', shift=True)
                    caption = read_key('home')
                    check('List first' in caption and 'tab' in caption.lower() and 'radio button' not in caption.lower(),
                        'VoiceOver reads a list-backed tab with native tab semantics')
                    prior = len([e for e in state()['events'] if e['object'] == 'ListTabs' and e['event'] == 4])
                    read_key('space')
                    ax.wait_for(lambda: list_tabs[0].read('AXValue') == 1, 'VoiceOver list selection readback', timeout=20)
                    settle()
                    check(len([e for e in state()['events'] if e['object'] == 'ListTabs' and e['event'] == 4]) == prior + 1,
                        'VoiceOver list activation runs one original handler')
                    caption = ax.wait_for(lambda: (spoken if 'selected' in (spoken := vo.read_caption()).lower() and 'List first' in spoken else None),
                        'VoiceOver list selection feedback without moving its cursor', timeout=5)
                    report['selectedListTabSpeech'] = caption
                    check('selected' in caption.lower(), 'VoiceOver announces the completed list selection')
                    read_key('up', shift=True)
                    read_key('home')
                    reach('Pages')
                    read_key('down', shift=True)
                    read_key('home')
                    reach('Third page', limit=5)
                    read_key('space')
                    ax.wait_for(lambda: state()['page'] == 3, 'VoiceOver standard page navigation', timeout=20)
                    settle()
                    check(find('Page 3 text') is not None, 'VoiceOver page activation exposes its current content')
                    caption = ax.wait_for(lambda: (spoken if 'Page 3 text' in (spoken := vo.read_caption()) else None),
                        'VoiceOver following the new page editor', timeout=5)
                    check('AX page three' in caption, 'VoiceOver can leave the tabs and read the page editor')
                finally:
                    vo.stop()
            selected = state()['array']
            before = len([e for e in state()['events'] if e['object'] == 'ArrayTabs'])
            for changed in (True, False):
                previous = categories
                previous_children = categories.read('AXTabs') or []
                check(find('Change tab presentation').press() == 0, 'original resize handler accepted')
                settle()
                wanted = 'AXTabGroup' if narrow == changed else 'AXPopUpButton'
                categories = ax.wait_for(lambda: (e if (e := find('Categories')) and e.read('AXRole') == wanted else None),
                    'Native presentation change', timeout=20)
                check(previous.read('AXRole') is None and all(t.press() != 0 for t in previous_children), 'retained old presentation and children retire')
                check(state()['array'] == selected and len([e for e in state()['events'] if e['object'] == 'ArrayTabs']) == before,
                    'presentation change preserves selected data and tab business handlers')
            if not narrow:
                new_tabs = ax.wait_for(lambda: categories.read('AXTabs'), 'Restored tab choices', timeout=20)
            for _ in range(2):
                restart()
            if not narrow:
                new_tabs = ax.wait_for(lambda: categories.read('AXTabs'), 'Restarted tab choices', timeout=20)
            check(find('Close fixture').press() == 0, 'original close action accepted')
            process.wait(timeout=20)
            check(categories.read('AXRole') is None and (narrow or new_tabs[1].press() != 0), 'closed bridge group and owned children retire')
            report['passed'] = True
        except Exception as error:
            report['failure'] = str(error)
            if process.poll() is None:
                target = BUILD / 'tabs-failure.png'
                ax.capture_window(process.pid, target, include_shadow=False)
                report['failure_image_sha256'] = sha(target)
            raise
        finally:
            if 'group' in locals():
                report['lastReceipt'] = group.read('AXHelp')
                if not report['passed']:
                    report['currentChildTabs'] = [{'id': t.read('AXIdentifier'), 'label': t.read('AXDescription'), 'frame': [t.read('AXPosition'), t.read('AXSize')]}
                        for t in (find('LeftChild: Sections').read('AXTabs') or [])] if find('LeftChild: Sections') else []
                    try:
                        state()
                    except Exception as error:
                        report.setdefault('failure', str(error))
            report['finalState'] = last_state
            mode = 'compiled' if args.compiled else 'interpreted'
            generated = 'generated-' if compile_report['generated'] else ''
            variant = 'narrow-' if compile_report.get('narrow') else ''
            variant += 'icons-' if compile_report.get('icons') else ''
            variant += 'scroll-' if compile_report.get('scrollIcons') else ''
            variant += 'clipped-' if compile_report.get('clippedChildren') else ''
            voiceover = '-voiceover' if args.voiceover else ''
            recovery = 'restart-only-' if args.restart_only else ''
            (BUILD / f'tabs-{recovery}{generated}{variant}{mode}{voiceover}.json').write_text(json.dumps(report, indent=2) + '\n')
            if process.poll() is None:
                process.terminate(); process.wait(timeout=10)


if __name__ == '__main__':
    main()
