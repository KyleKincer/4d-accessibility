# Validation scope

The source was developed with isolated synthetic 4D 20.8 fixtures and external macOS accessibility clients. Prior development runs covered ordinary/child controls, native array/collection/entity grids, cell widgets, explicit providers, generated forms, focus ownership, large virtual grids, native/web interoperability and optional-package loading. Those historical machine reports are not shipped as evidence for this standalone repository.

Current CI builds the universal native plugin, runs deterministic Session/Grid/installer checks and compiles the component with tool4d. Desktop tests require a local unlocked session and the test client's normal macOS Accessibility approval. CI does not claim live VoiceOver, licensed compiled host execution or remote-client delivery.

Before extraction, licensed AreaList action suites passed 43 checks each in interpreted and native ARM compiled hosts. A subsequent compiled VoiceOver test initially expected navigation alone to select a row. The corrected test separates reveal from explicit VO-Space selection, matching the established native-grid contract, and passes. Native headers have separate mode-specific results below. The unresolved cases and other gaps are recorded in [status](STATUS.md) and prevent a full-accessibility claim.

Run the scripts described in `CONTRIBUTING.md` at the root of a matching source checkout. An independently installed skill does not contain those scripts; locate the checkout before running them. Keep exact source revision, package hashes, compiler/runtime versions, execution mode and test outcome with every new validation report. Reproduce each claimed workflow in the integrating application.

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
