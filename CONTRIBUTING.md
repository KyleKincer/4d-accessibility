# Build and test

Use Python 3.12 or newer, macOS and Xcode Command Line Tools. Source and generated fixtures use synthetic data. Install 4D and any vendor plugins separately for live tests.

```sh
python3 build.py
python3 build_component.py --tool4d /path/to/tool4d.app
```

Alternatively, use `--server /path/to/4D\ Server.app` with a licensed 4D Server. Run 4D compiler drivers sequentially. Build the native plugin before the component; the component compiler loads its commands. Outputs are `build/AccessibilityBridge.bundle` and `build/AccessibilityBridge.4dbase`. Local native builds are ad hoc signed.

The public CI toolchain is pinned in `ci/tool4d.json`. `python3 ci/download_tool4d.py` downloads the official archive, checks its SHA-256 and prints the application path. No 4D license or AreaList key is needed for this headless component build.

## Checks without a live 4D application

```sh
python3 test.py
python3 test_grids.py
python3 test_install_host_methods.py
python3 test_native.py
python3 ci/check_repository.py
```

`test_native.py` compiles the AppKit provider tests. Add `--run` only in an unlocked graphical session. Live fixture scripts also require 4D desktop and appropriate Accessibility permission. Screen recording is needed for visual/VoiceOver probes.

Version 0.21.0 has [tab-control acceptance cases](tests/TABS.md#run-the-acceptance-cases) for named/generated forms, repeated children and compact native menus. Keep its plugin, component and helpers together when preparing a fixture.

## Area-owned integration

Version 0.20.0 adds a lifecycle area to ordinary forms without changing their business methods or event masks. Build both packages first, then run the smallest end-to-end case:

```sh
python3 prepare_area_fixture.py --server /path/to/4D\ Server.app
python3 test_area_fixture.py --run
python3 test_area_fixture.py --run --compiled
```

The test edits duplicate-named root/child fields, observes their original handlers, deliberately restarts registration, closes without an `On Unload` bridge hook, and reopens the form. Prepare with `--inherited` to exercise a shared base, `--yield-load` to yield during business initialization, or `--configuration absent` to use automatic defaults. `--no-component`, `--no-plugin`, `--configuration invalid` and `--configuration error` exercise dependency and configuration failures while the ordinary form remains usable.

Prepare with `--compound` for a generated nonblocking root, duplicate-named object-property editors, early focus and child replacement. Run the same desktop driver in interpreted and compiled modes; add `--intel` for Rosetta or `--voiceover --compiled` for spoken reading and activation. The driver checks initial focus, intentional restart and retirement of the old observed editor. `--pointer-focus` tests unique native variables with an unobserved child; `--early-manual-start` tests an area beside an existing manual registration. `--shared-pointer-guard` verifies that a missing child observer and shared native pointer never publish a guessed editor. `--nonblocking`, `--generated`, `--root-only-area` and `--initial-focus` select smaller variants. `--close-during-load` verifies cleanup before the first idle callback. `--edit` opens the owned form in 4D's Form Editor; save and compare original definitions and the canonical area, then check installer idempotence.

For classic list subforms, use [the dedicated acceptance fixture](tests/LIST-SUBFORMS.md). It exercises automatic parent discovery, generated metadata, native row selection and original editors without per-form integration hooks. Preparation requires a licensed `--server` application. Its compiler and desktop runs must also remain sequential.

For native web areas beside ordinary controls, use [web-area acceptance](tests/WEB-AREAS.md). Supply a complete matching kit and licensed `--server` compiler. The loopback fixture checks browser-owned validation/submission, 4D handler preservation, compiled VoiceOver and whole-window pixels. The accepted 0.22.0 system-engine fixture retains a mixed reading-order gap. The exact 0.22.1 main-CI kit passes visual interleaving for eligible containers. Preserve the full matrix, individual VoiceOver stops and reverse navigation after Close. Run `test_native_interop.py --run` separately for native containment, hits, focus and metadata restoration. Embedded Chromium and broader web layouts remain open.

For Appium Mac2/XCTest discovery and original-handler activation, use [Appium acceptance](tests/APPIUM.md). It operates the disposable classic list parent through stable identifiers and independently verifies fixture state. This is separate from real application or SQUASH runner acceptance.

For the remaining hierarchy adapter, use [native hierarchy probes](tests/HIERARCHY-PROBES.md). These compare read-only state, native tree arrows, process-targeted `POST KEY` and grouped mouse disclosure. The optional observer records public native views and drawing with distinct test binaries. Neither these probes nor their compilation establishes hierarchy accessibility.

The optional `--grouped-states` cases and `summarize_grouped_probe.py` require Pillow 12.1 or later. They validate sampled selection/disclosure state and native image round trips; they do not add production hierarchy support.

The production native outline provider has a separate [AppKit acceptance fixture](tests/NATIVE-OUTLINES.md). It tests supplied topology, disclosure relationships, unknown selection, group labels, retained-handle retirement and VoiceOver levels/offscreen navigation. It does not supply a 4D hierarchy adapter or disclosure action.

The development [read-only grouped adapter gate](tests/GROUPED-OUTLINES.md) adds owning-form capture for text/date array breaks. It tests both 4D modes, compiled VoiceOver, caption/binding rejection and recovery, exact packages, cold-value speech and complete-window baseline pixels. It leaves disclosure, selection, reveal, editing and actual Symphony hierarchy workflows pending.

The 0.24.0 development [grouped disclosure gate](tests/GROUPED-DISCLOSURE.md) adds an explicit application controller, both desktop modes, compiled VoiceOver row/triangle activation, repeated nested ownership, pending editor preservation and fault retirement. Its publisher also requires the read-only gate and package-free whole-window baselines on the same immutable project and binaries. Selection, reveal, editing, classic trees and actual Symphony workflows remain pending.

The separate `--grouped-inputs` cases and `summarize_grouped_inputs.py` check center clicks followed by native keyboard disclosure on visible later/nested breaks. They need no Pillow dependency and cannot combine with `--grouped-states`. Selection-preserving disclosure, arbitrary/offscreen targets and action races remain unvalidated. Both evidence publishers reject stale prepared method sets; CI runs four deletion/rename fault regressions.

`python3 test_form_focus.py --server /path/to/4D\ Server.app` exercises production focus resolution with real 4D object identities and child paths. It covers forwarded ancestor events, shared bindings, unobserved descendants, retired/disabled controls and conflicting contexts. Run it sequentially with every other 4D compiler or graphical fixture. It complements the live event and VoiceOver checks.

`test_area_pixels.py --server /path/to/4D\ Server.app --run` compares the complete rendered synthetic window with and without the area. It requires Pillow and accepts no changed pixels, masks or tolerance.

For persisted entities, shared objects and class instances, run `test_root_data.py --server /path/to/4D\ Server.app --kind entity --area --generated --no-error-callback --run`, then add `--compiled`. Replace `entity` with `shared`, `instance` or `plain`. This checks unchanged data ownership, failure diagnostics without an application callback, deliberate recovery and cleanup of the replacement registration.

Add `--area` to the ordinary discovery, automatic-subform, native-grid and AreaList fixture preparers below to exercise the same adapters with area-owned startup and teardown. These fixture migrations remove only their known test lifecycle code. The public installer never rewrites application methods. The manual lifecycle suites remain useful compatibility checks.

For delayed grid values, without a 4D installation:

```sh
python3 test_grid_value_speech.py --run
```

This builds the production native provider in an owned synthetic window and starts its own VoiceOver session. Nine cases verify speech when a cold cell loads, navigation between pending cells, leaving the grid, unrelated AX inspection, reloading the same value and delayed checkbox/popup roles. Each case observes speech without moving the reading cursor, then checks its position. Existing user VoiceOver sessions are left alone. Reports and synthetic caption images stay under ignored `build/grid-value-speech/`. Use `--case single` for the shortest reproduction or omit `--run` to compile only. `test_native_grids.py --run --voiceover` separately tests all 50,000 logical rows and 24 columns.

For standard `ALERT`, `CONFIRM` and `Request` windows, with 4D desktop at `/Applications/4D/4D.app`:

```sh
python3 test_native_messages.py --baseline
python3 test_native_messages.py --run
python3 test_native_messages.py --run --voiceover
```

`--baseline` records the plugin-free windows, advancing with Return only as setup. `--run` then requires identical pixels before acting through AX. `--voiceover` navigates, types and activates with VoiceOver and records only the fixture's speech. It reads speech through VoiceOver's AppleScript `last phrase`, so "Allow VoiceOver to be controlled with AppleScript" must be enabled. Add `--intel` for Rosetta, or `--compiled --server /path/to/4D\ Server.app` to compile the copy first. Reports stay under ignored `build/`.

For focus after a host mode change, without a 4D installation:

```sh
python3 test_focus_replacement_speech.py --run
```

An owned synthetic window publishes a focused read-only note beside forty sibling fields, then makes every field editable in one refresh, as a 4D form does when it enters Modify. VoiceOver must announce the note as editable text in every trial rather than moving to the containing group. It starts its own VoiceOver session and reads speech with VoiceOver's AppleScript `last phrase`, so "Allow VoiceOver to be controlled with AppleScript" must be enabled. Omit `--run` to compile only.

For button grids and other picture-based controls, with 4D desktop and a licensed `--server` compiler:

```sh
python3 test_picture_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_picture_fixture.py --server /path/to/4D\ Server.app --run
python3 test_picture_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

Add `--compiled` or `--intel` for the other modes. [Picture-based controls](tests/PICTURE-CONTROLS.md) describes what each run checks.

For VoiceOver test-session cleanup:

```sh
python3 tests/test_voiceover_cleanup.py
swiftc tests/ReadScreen.swift -o build/ReadScreen
python3 test_voiceover_cleanup_fixture.py --ocr build/ReadScreen
```

The unit checks block system input. The live AppKit fixture closes its own window or moves foreground to a second owned app. Cleanup must preserve the original guard failure and stop every captured VoiceOver and Quickstart process. The report records whether a hidden caption baseline needed restoration; a run with an already visible caption panel does not establish that case. Existing user VoiceOver sessions prevent the live run. Run it sequentially with other graphical fixtures.

For example, after building the two packages:

```sh
python3 prepare_grid_fixture.py --server /path/to/4D\ Server.app --collection --row-states --cell-controls
python3 test_grid_controls_fixture.py --run --compiled --voiceover
```

Omit `--compiled` for interpreted execution or `--voiceover` for the external AX action suite alone. Add `--subform --repeated` when preparing to test independent copies of the widget grid in child forms.

For classic current/named-selection grids, run the real-command checks, then the external AX suite:

```sh
python3 test_classic_selection.py --server /path/to/4D\ Server.app --run
python3 prepare_selection_fixture.py --server /path/to/4D\ Server.app
python3 test_selection_fixture.py --run
```

Prepare a fresh fixture before every driver run: native edits deliberately persist. Add `--compiled` to the driver for compiled action tests, or `--compiled --voiceover` for spoken navigation, native selection and checkbox feedback. Add `--named` to preparation to exercise a named selection with a different order. The suite checks loaded, modified, unloaded and unsaved-new record states, distant values, native text/checkbox commits, sorting and hidden stale cells. [Integration and limitations](skills/4d-accessibility/references/GRIDS.md#use-a-classic-current-or-named-selection).

`test_selection_pixels.py --server /path/to/4D\ Server.app --run` separately prepares bridge-free and integrated compiled forms and compares every window pixel. It requires Pillow and the desktop application at `/Applications/4D/4D.app`. It replaces the disposable selection fixture, so archive earlier reports first. Add `--named` for the named-selection baseline; neither comparison uses masks or tolerance.

For native array identities, prepare with `prepare_grid_fixture.py --key-type integer` or `--key-type longint`, plus `--row-states --described`. Run `test_grid_fixture.py --run` and then `--compiled` to exercise both desktop modes. Keep the required `--server` argument when preparing.

For a slow selection controller and an offscreen row, prepare with `--slow-distant-selection`. Run `test_grid_fixture.py --run` and `--run --compiled`. The controller deliberately takes 150 ticks. The checks require the selected row to become visible, exactly one controller call and preservation of a later application rejection. `--slow-visible-selection` separately checks a slow scope callback for a row already in view.

For legacy Boolean hidden-row arrays, prepare with `--boolean-hidden` and the required `--server`. Run `test_grid_fixture.py --run` in interpreted and `--compiled` modes. The same editing, selection and sort suite also hides and restores a distant row, checking retained-cell rejection and identity. Add `--voiceover` for the separate spoken-navigation check.

For generated repeated/nested children sharing ordinary data, with parent-owned discovery:

```sh
python3 prepare_auto_subforms.py --generated-children --server /path/to/4D\ Server.app
python3 test_auto_subforms.py --run --launch
python3 test_auto_subforms.py --run --launch --compiled
```

The launcher verifies the project and window before sending input and closes only its disposable process. Compiled desktop execution needs the appropriate local 4D license.

For existing controls drawn over a background button:

```sh
python3 prepare_layered_fixture.py --server /path/to/4D\ Server.app
python3 test_layered_fixture.py --run
python3 test_layered_fixture.py --run --compiled
```

This checks foreground activation, complete and partial obstruction, a background action using a free region, and coincident buttons that cover/reveal each other through their existing handlers. The fixture describes their existing layers through `controls.<name>.layer`. The ordinary discovery suite separately covers checkbox, radio and popup behavior. Wait for both the handler result and final action receipt before submitting another action.

Add `--voiceover` to the compiled invocation to read and activate each exposed stacked button as its handler hides or restores the other. A grid without a provider also verifies that background activation cannot click through opaque controls.

For a large form with 600 ordinary buttons and a 65,546-character field:

```sh
python3 prepare_large_form.py --server /path/to/4D\ Server.app
python3 test_large_form.py --run
python3 test_large_form.py --run --compiled --voiceover
```

The VoiceOver mode reads the beginning and end of the complete form before the normal editing/validation suite. It rejects unresponsive speech and refuses to take over an existing VoiceOver session.

For a search field that submits after one second without a keystroke:

```sh
python3 prepare_large_form.py --server /path/to/4D\ Server.app --debounced
python3 test_debounced_input.py --run
python3 test_debounced_input.py --run --compiled
```

This variant uses an empty field, the application's own timer and a deliberately costly scope callback. It checks that an AX value replacement reaches the search intact. The regression submitted only the first character because the first editor step retained the worker's idle delay. Subsequent steps already used fast polling. Prepare the ordinary large form again before running its long-note suite.

Read each script's `--help` before choosing a case. Fixture preparers create disposable projects under ignored `build/`; run one 4D desktop fixture at a time. Synthetic AreaList tests accept `--area-list-plugin /path/to/ALP.bundle`. Use `--license-file /path/to/protected/alp.license` for an existing license file with mode 0600, or keep it in ignored `fixture/Resources/alp.license`. Add `--key-type integer` or `--key-type longint` to exercise existing numeric key arrays; `test_alp_grid_fixture.py --run --text bmp` tests supported text, while the default supplementary case remains a failing requirement. The vendor's license and redistribution terms remain separate.

For the independent AreaList supplementary Unicode crash, see the [bridge-free reproduction](tests/AREA-LIST-UNICODE.md). The adapter rejects these requests before mutation; ordinary native 4D text editing has separate Unicode coverage.

For AreaList checkboxes, add `--controls` when preparing the AreaList fixture, then run `test_alp_controls_fixture.py --run` in interpreted and `--compiled` modes. Add `--voiceover` for spoken navigation and activation. The fixture keeps normal vendor initialization and entry/exit callbacks in the child forms; the root uses the same grid configuration as other AreaList forms.

For calculated AreaList columns, add `--calculated` when preparing, then run `test_alp_grid_fixture.py --run --text bmp` in interpreted and `--compiled` modes. The vendor callback and the accessibility value formula share one display function. The test reads a distant calculated cell, exercises ordinary editing and sorting, then replaces a column's array binding while retaining the row keys and scope. Retained cells must retire and the new cells must read the replacement array. Vendor errors fail the test.

For direct moves between edited AreaList cells, add `--cell-transitions` to `test_alp_grid_fixture.py`. This shorter case verifies complete text commits, rejection by the existing exit handler, correction and a scope change during exit. The ordinary text suite also tests cell transitions after Undo/Redo. The checkbox suite checks transitions from a text editor into a checkbox, including rejected text. These tests assert committed values, not just text visible in the native editor.

For styled native text, prepare the ordinary discovery fixture with `--area --styled` and the required `--server`. Run `test_styled_text.py --tool4d /path/to/tool4d.app` for command-level reading and side-effect checks; a licensed `--server` is also supported. Run `test_styled_fixture.py --run` and then `--run --compiled --voiceover` for native selection, multiline Unicode input, style-preserving edits, original validation, Undo, stale elements and spoken reading. Prepare again with `--dynamic` to repeat both runs on a JSON-generated form. The test selects actual controls, because their captions can have the same accessible name. Default-menu Redo availability is compared with the observed native 4D 20.8 baseline; it is not a Redo execution claim. Desktop tests require an unlocked graphical session. The [family checklist](skills/4d-accessibility/references/FULL-FORMS.md) tracks the remaining work.

Live AX polling and fixture startup stop immediately if the graphical session locks. For unattended runs, keep login-session sleep and user-activity assertions alive for the whole run. `caffeinate -u` defaults to a five-second user-activity timeout when `-t` is omitted. Use a login LaunchAgent with `RunAtLoad` and `KeepAlive`. Its persistent `caffeinate -di` process holds sleep assertions while a child loop runs `caffeinate -u -t 600 /bin/sleep 240`. The loop renews user activity every four minutes; the outer sleep assertions stay active across renewals and terminal/session-host exits. Verify that its process owns `PreventUserIdleDisplaySleep`, `PreventUserIdleSystemSleep` and `UserIsActive` in `pmset -g assertions`. Keep normal authentication enabled. An explicit lock or logout still requires an unlock before testing resumes.

## Source ownership

`src/` contains the macOS provider and action/session model. `host/Methods` contains component methods and AreaList adapters; `host/OptionalMethods` contains the high-level host API. Edit canonical helpers, then reinstall them into test hosts with `install_host_methods.py`. The installer protects application-owned methods and modified generated files.

The full integration reference and examples live under `skills/4d-accessibility/references` so the agent skill can be installed as a self-contained folder. Update that source once. Build checks validate local links and the skill's required files.

When changing a control, test observable behavior against its ordinary native UI: ownership, focus, state, editor/handler callbacks and stale elements. Keep the [status](skills/4d-accessibility/references/STATUS.md) precise about failures and untested modes.

## Application instrumentation

An application-specific installer can import `install_host_methods.main` and pass a trusted `transform(body, method_name)` callback. This lets a host apply its existing instrumentation while sharing upstream overwrite, hash and compiler-declaration checks. The ordinary CLI installs source unchanged. Transformations finish before any destination is written; an exception leaves the installation untouched. Keep application-specific wrappers in the host repository.

Live fixture startup and key injection also check for held Shift, Control, Option or Command keys. Release those keys, including on a screen-sharing client, before running tests. The check reports interference without changing key state. VoiceOver can still send its own modifier combinations during a test.

To test database reopening in one 4D process, prepare the discovery fixture with `--area --reopen`, then run `test_discovery_fixture.py --run --launch` and repeat with `--compiled`. The fixture performs `OPEN DATABASE` once, verifies two startup executions, and uses external AX to complete the ordinary controls workflow after plugin reinitialization.
