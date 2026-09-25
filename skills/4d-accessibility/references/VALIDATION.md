# Validation scope

## Visible selection confirmation, September 24

The native array-grid fixture selects an already visible row while its application scope callback takes 70 ticks whenever an action is pending. The original helper changes the actual selection correctly, then reports `Application did not confirm the requested selection`. It spends another form callback on a scroll that does not change the viewport. The corrected helper completes after verifying the visible selection, avoiding that redundant cycle. The timeout and all identity, permission and application-handler checks remain unchanged.

The controlled before/after test passes nine checks in interpreted 4D 20.8 and nine in compiled ARM execution on macOS 26.6.2. Run `prepare_grid_fixture.py --server /path/to/4D_Server.app --slow-visible-selection`, then `test_grid_fixture.py --run` and `test_grid_fixture.py --run --compiled`. [Reports, helper hashes and reproduction](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/visible-selection.json). This is a bounded callback-delay regression, not a promise of unlimited latency tolerance.

## Delayed grid value speech, September 24

Version 0.19.4 passes 120 checks across eight native VoiceOver cases on macOS 26.6.2/Apple Silicon. A synthetic host compiles the production provider and session, publishes a complete 60-row/24-column grid, and withholds pages until VoiceOver has actually read Loading. It then releases the pages while the reading cursor stays still. [Complete reports and source/build hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/grid-value-speech.json).

The cases cover a single cell, forward navigation, backtracking, leaving for native window controls, another AX client querying a different cell, identical values reloading after cache invalidation, and delayed checkbox/popup roles. External AX checks the actual value and control state. Stationary caption observations check speech; the next navigation step checks that the cursor stayed at the same cell. Reading does not select rows, and read-only controls do not gain mutation actions.

The original provider fails the single-cell case with the same final driver and fixture. Its AX value arrives, but VoiceOver keeps saying Loading or its navigation hint. Only `src/GridNative.mm` differs between those two native builds. The correction identifies each newly readable cell in a separate table layout notification. A batched notification spoke only the number of updated items. It follows Apple's [layout notification](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/layoutchanged) and [changed-element list](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notificationuserinfokey/uielements) contracts; the individual-cell behavior is established by the live tests. No keyboard focus or explicit announcement is used to infer the reading cursor.

The same native source passes 273 Session, 169 logical-grid and 182 AppKit checks. A separate external native-grid suite passes 32 checks, including VoiceOver navigation/reveal to the final cell of 50,000 rows and 24 columns, sorting with stable identities, value refresh and retired elements. Run `python3 test_grid_value_speech.py --run` and `python3 test_native_grids.py --run --voiceover` from the source checkout. These native fixtures do not establish 4D host execution, Voice Control/Switch Control or behavior on other macOS versions.

The compiled 4D 20.8 native-widget regression passes 38 checks with the matching packages. It operates independent repeated-child grids, activates a checkbox, chooses through a native popup menu, then navigates to row 599. The loaded distant checkbox is spoken without another navigation command. The provider that identified the replaceable content child failed this exact 4D check; identifying its stable cell fixes it. Returning to the popup, cancelling it and leaving for an ordinary editor still pass. `test_grid_controls_fixture.py --run --compiled --voiceover` reproduces that case after preparing the documented collection/repeated/widget fixture.

The action driver now waits for the native checkbox's advertised enabled state and AXPress action after fixture configuration. The previous fixed delay tried to press a still-disabled control. The same failure occurred with the preceding 0.19.3 packages and passed there after correcting this test wait. Interpreted and compiled action suites each pass 127 checks. No application action retry was added.

## Polling and large forms, September 24

Version 0.19.3 passes 884 live checks across 18 runs on native ARM 4D 20.8 and macOS 26.6.2. The plugin and compiled component match in every case. [Checks and source/package hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/polling.json).

| Scenario | Execution and checks |
| --- | --- |
| Ordinary and generated controls | Interpreted/compiled, 69 each, 276 total |
| Collection grid inside an automatic child | Interpreted/compiled, 62 each |
| Native array grid with LongInt keys | Interpreted/compiled, 59 each |
| Local entity-selection grid | Interpreted/compiled, 60 each |
| Readiness, metadata changes and fatal callback cleanup | Interpreted, 9 |
| AreaList checkbox editors | Interpreted/compiled, 30 each; compiled VoiceOver, 34 |
| AreaList BMP text editors | Interpreted/compiled, 45 each |
| 600 ordinary buttons and a 65,546-character field | Interpreted, 23; compiled with VoiceOver, 30 |

The large-form VoiceOver test confirms the native window starting point, enters the form group, reads its first and last buttons, ordinary note and Close control, and preserves form data. It then runs the same distant text selection, partial/whole Unicode replacement, validation, Undo/Redo and original-timer checks as the interpreted suite. It rejects unresponsive speech. This checks both ends of the form, not a spoken traversal of every button.

The child fixture now reads focus state from its root observer and explicitly focuses a real child field before testing actions. The metadata and large-form launchers activate their owned window. The large-form test establishes entry focus before its first button action, avoiding requests during startup focus changes. These are test corrections; the original focus and business-result assertions remain. The compiled entity run uses a fresh prepared fixture because interpreted 4D rewrites its generated catalog when opening the synthetic data file. Test source/package guards remain enabled.

Reproduce with the preparers and tests in `CONTRIBUTING.md`. Prepare AreaList text and checkbox cases separately; `--controls` adds columns that the text-only suite does not expect. These results do not establish supplementary Unicode in AreaList, remote entities, Intel desktop runtime or every control family.

## Control names and empty captions, September 24

Version 0.19.2 passes 69 checks in each of four runs: ordinary and generated JSON forms, each interpreted and compiled on native ARM 4D 20.8. The 276 checks include normal object handlers, text validation and standard Cancel behavior. Untitled buttons, checkboxes, radio buttons and popups use their existing help tips. Visible button captions retain precedence. A tip exceeding 512 UTF-16 units is shortened at a character boundary. An empty static caption contributes no nameless stop, then appears when the application's normal button handler sets its text. An explicit label can retain an intentionally empty static node.

Before the changes, the untitled-button test failed to find its help-tip name, and the empty-caption test found an extra node. [Reports and source/package hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/control-names.json) preserve those reproductions and the final runs. This matrix does not establish VoiceOver speech for the new naming cases or safe activation of off-window keyboard commands.

## Button activation across record changes, September 24

Version 0.19.1 passes 58 generated-child checks and 62 ordinary-control checks in each of interpreted and compiled ARM desktop execution, 240 total. The new regression first failed when an ordinary button changed root record scope: its handler ran, but the bridge rejected its confirmation because the old route had retired. The button now acknowledges posting its verified click. The receipt does not claim a business result. The same tests retain stale-descendant rejection, existing object handlers, native checkbox/radio state, text validation and standard Cancel behavior. [Failure, final reports and source hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/button-activation.json).

The source was developed with isolated synthetic 4D 20.8 fixtures and external macOS accessibility clients. Prior development runs covered ordinary/child controls, native array/collection/entity grids, cell widgets, explicit providers, generated forms, focus ownership, large virtual grids, native/web interoperability and optional-package loading. Those historical machine reports are not shipped as evidence for this standalone repository.

Current CI builds the universal native plugin, runs deterministic Session/Grid/installer checks and compiles the component with tool4d. Desktop tests require a local unlocked session and the test client's normal macOS Accessibility approval. CI does not claim live VoiceOver, licensed compiled host execution or remote-client delivery.

Before extraction, licensed AreaList action suites passed 43 checks each in interpreted and native ARM compiled hosts. A subsequent compiled VoiceOver test initially expected navigation alone to select a row. The corrected test separates reveal from explicit VO-Space selection, matching the established native-grid contract, and passes. Native headers have separate mode-specific results below. The unresolved cases and other gaps are recorded in [status](STATUS.md) and prevent a full-accessibility claim.

Run the scripts described in `CONTRIBUTING.md` at the root of a matching source checkout. An independently installed skill does not contain those scripts; locate the checkout before running them. Keep exact source revision, package hashes, compiler/runtime versions, execution mode and test outcome with every new validation report. Reproduce each claimed workflow in the integrating application.

## AreaList checkbox cells, September 24

The 0.19 fixture passes 30 external AX checks in interpreted mode and 30 in native ARM compiled 4D 20.8. Its compiled VoiceOver run passes 34 checks. Two repeated forms each contain 600 source rows, Boolean checkboxes, Integer two-state and LongInt three-state checkboxes. Normal, small and mini display modes use their original AreaList configuration. Tests cover offscreen values, focus without toggling, uncommitted editor state, ordinary Escape and commit, callback counts, area/column/cell permissions, validation rejection, sorted row identity and retired controls. VoiceOver reads and activates a checkbox, then returns to the ordinary form editor. No application accessibility callbacks were added to the child forms.

`validation/arealist-checkboxes.json` contains the checks, source/package hashes and VoiceOver captions. Prepare with `prepare_alp_grid_fixture.py --controls --server <4D Server.app>` and run `test_alp_controls_fixture.py --run`, then `--compiled` and `--compiled --voiceover`. Keep the existing vendor plugin/license arguments described in `CONTRIBUTING.md`.

The shared paging change also passes all six existing Text/Integer/LongInt text-editor suites, 45 checks each in interpreted and compiled mode, 270 total. Deterministic checks pass 273 Session and 169 logical-grid assertions; native AppKit passes 182. Installer and development-package checks pass. The universal plugin and ARM/Intel component build successfully; these runtime results cover native ARM only.

The fixture initially inherited legacy AreaList compatibility mode, which resets visibility and hides the final column. Its checkbox configuration now explicitly uses modern visibility settings. A disabled AXPress can still return transport success on macOS; permission tests assert absent actions, unchanged values and unchanged callback counts after application event cycles. A transport return code is not a mutation receipt. Vendor popup/radio editors, custom-picture rendering and modal editors remain outside this result.

## Standalone generated-child validation, September 24

The standalone universal plugin and tool4d-built component passed 57 external AX checks in an interpreted host and 57 in a native ARM compiled host on 4D 20.8/macOS 26.6.2. These runs used JSON-generated repeated and nested children, shared plain business data, replacement invalidation, ordinary editing/handlers and a second root window. Children had no explicit providers or registration. The source checkout contains the sanitized check results and exact source/package hashes in `validation/generated-children.json`.

This establishes that the parent-owned generated-child recipe works for the tested synthetic form. It does not establish every generated builder, assistive technology, vendor grid or application workflow. Reproduce with `prepare_auto_subforms.py --generated-children --server <4D Server.app>` followed by `test_auto_subforms.py --run --launch`, then `--compiled` for the licensed compiled mode.

## Standalone AreaList numeric-key validation, September 24

Existing Integer and LongInt key arrays each passed 43 external AX checks in interpreted mode and 43 in native ARM compiled mode. The LongInt compiled fixture also passed 16 VoiceOver checks, including navigation to the final logical row, explicit selection and return to an ordinary field. The source checkout records sanitized results and adapter/package hashes in `validation/arealist-numeric-keys.json`.

The cases use two repeated AreaList instances with 600 source rows each. They exercise hidden rows and columns, protected values, offscreen reads/reveal, selection, BMP text editing, native validation and Undo, sorting, readiness and stale references. The source key arrays retain their numeric types. Supplementary Unicode entry remains a failing requirement and is explicitly rejected before mutation.

One interpreted test initially failed while reading a diagnostic file during its timer-driven rewrite. The reader now retries incomplete JSON; the corrected run passed all 43 checks. This correction does not change the bridge or weaken the assertions.

## Standalone native-header validation, September 24

Header suites pass 31 external checks each for arrays, collections and entity selections in interpreted and compiled modes. They cover ordinary/reverse sorting, custom and rejected header handlers, offscreen reveal, hidden and loading states, retained-element rejection, and empty grids. `validation/native-headers.json` records the results and exact package hashes. One earlier compiled entity run acknowledged input delivery without a header event or sort. A separate two-activation probe and a freshly prepared complete run pass. Its cause remains unresolved; no action retry or scheduler workaround was added.

An earlier disabled-header test used `OBJECT SET ENABLED` on a native list box. Its transient disabled flag reverted with the bridge stopped too; [4D documents this command for other control types](https://developer.4d.com/docs/commands/object-set-enabled). The corrected test uses the supported readiness contract. It also reacquires the loading table because suspending a logical grid retires its old AX element. Cached failure state had incorrectly suggested a stopped form timer; the actual file continued advancing. No scheduler workaround was added.

## Root data ownership, September 24

Eight native ARM desktop cases pass across interpreted and compiled execution: a persisted entity, 4D shared object, plain local object and user-class instance. Each starts on its original binding, reads the field, invokes the existing business handler, restarts, rejects a retained field and recovers from an intentional callback error. The error callback runs after detachment with the application's handler restored; the original timer continues and the form closes normally. Entity/class/shared data receives no bridge properties. Entity, class and plain cases also edit supplementary Unicode through the native editor and commit through an ordinary button.

The shared-object case has a read-only field and a business handler using `Use...End use`. It does not claim that 4D permits arbitrary direct editing of shared properties. Generated preparation and explicit registration return named rejection errors for these data types before adding state; those paths still require private plain data. `validation/root-data.json` records each check and the exact native, component and generated source hashes.

A deterministic Session test covers initial focus arriving on the unchanged requested target before dispatch. The former implementation rejected that transition. Other focus changes, value/selection changes and expired requests still reject. Live fixtures also wait for the initial focus publication and each completed mutation before issuing another action; neither mutation retries nor a timer replacement are used.

The ownership checkpoint also passes 273 Session checks, 161 logical-grid checks, 182 native AppKit checks, 94 portable-helper checks and the 57-check generated-child suite in each execution mode. The child test now retains one lookup while waiting for replacement, avoiding a test-side race between two AX lookups. Native mouse tests initially ran without an active/key window while a credential application's lock window held the foreground. Closing that window restored the existing test activation path; no activation-policy change was retained. Development-package and clean-host installer checks pass.

## Native array key types, September 24

Text, Integer and LongInt key arrays each pass 92 external AX checks in interpreted and native ARM compiled 4D. The numeric cases include the signed minimum, zero and maximum, and preserve numeric keys in application callbacks. Tests cover all 599 visible rows, descriptions, protected values, row permissions, selection callbacks, Unicode editing and validation, Undo/Redo, sorting, readiness and stale identities. `validation/native-array-keys.json` records the six runs and source/package hashes. These changes require no additional form hooks or parallel arrays.

The original adapter rejected the numeric fixture. The test launcher now explicitly activates the licensed host and waits for published initial focus. A compiled Text run encountered a table retiring between lookup and indexed read during renderer replacement; its bounded read-only wait now reacquires on `kAXErrorInvalidUIElement`. Actions are never retried.

## Editor action cache, September 24

The 0.18 implementation passes 45 live checks for each Text, Integer and LongInt AreaList key variant in interpreted and native ARM compiled 4D, 270 checks total. A compiled LongInt run also passes all 45 checks under Guard Malloc, and its compiled VoiceOver run passes 16 navigation/selection checks. That instrumented run uses longer external test waits because memory instrumentation slows per-character entry; the application timeouts are unchanged. `validation/editor-cache.json` records exact native/component and generated-source hashes.

A focused editor now remains actionable when a delayed backing-cell cache updates while the actual editor text and selection stay unchanged. Changed permissions, changed editor text and changed unfocused-cell values still reject. The deterministic grid regression failed before the fix; all 167 grid checks now pass, alongside 273 Session and 182 native AppKit checks. No new host calls or clipboard operations are required.

The live suite also verifies that supplementary replacement rejects while preserving the active editor's value and selected text. A test-only lookup race during expected table retirement now uses a bounded read-only reacquisition; activations are never retried. AreaList supplementary editing itself remains blocked: a one-cell project without this bridge crashes in the vendor's Unicode conversion during getter, Copy and commit operations. See the [reproduction](https://github.com/KyleKincer/4d-accessibility/blob/main/tests/AREA-LIST-UNICODE.md). This is a limitation of the tested vendor editor, not evidence that ordinary native 4D text controls lack Unicode support.

## Generated wrong-data fallback, September 24

A source review found an unguarded compatibility-property write when a generated wrapper opened with different data from the object passed to preparation. The shared-object reproduction raised error -10719 at `AXB_DynamicEvent` line 31. Type guards now preserve original On Load, timer and On Unload behavior without adding properties to entity, class-instance or shared data. Eight interpreted/compiled native ARM cases pass seven checks each, 56 total. The integrating application's existing generated-subform regression also passes 24 checks in each mode, including replacement, rebinding, wrong-data fallback and cleanup. Plain local data retains its compatibility error property. Preparing a generated wrapper directly on non-plain data is still unsupported.

[Exact reports and source hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/dynamic-bindings.json). Opus 5.5 rated the revised integration skill 8/10 in a source review; its follow-up findings led to this fix and further documentation corrections. That rating is not runtime validation or a claim of complete accessibility.
