# Implementation status

This is a development preview. The goal is complete access to the UI through standard macOS accessibility, with minimal application code. The goal is not yet met.

## Current development check

An already visible native grid selection now avoids a redundant scroll-and-wait cycle. In an expensive form that extra callback could exhaust the deadline even though selection had succeeded. A synthetic 4D fixture reproduces the false timeout with the original helper; the correction passes nine checks in each of interpreted and compiled ARM execution. It preserves timeouts, permission checks and existing selection handlers. [Before/after evidence](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/visible-selection.json).

The 0.19.5 native provider requests one low-priority announcement when the most recently requested loading checkbox receives its value in the active window. The previous provider failed automatic distant-cell speech in a clean compiled-4D run (38 passing checks, one failure). The corrected source passes four complete compiled runs (39 checks each). The [local candidate package](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/grid-value-speech-0.19.5.json), [downloaded ad hoc candidate](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/grid-value-speech-0.19.5-download.json) and [signed, notarized candidate](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/signed-release-0.19.5.json) each pass all 39 compiled VoiceOver checks, including popup use and automatic distant-checkbox speech. The synthetic AppKit matrix passes 135 checks across nine VoiceOver cases, including an unrelated AX inspection and leaving a delayed checkbox before it loads. This resolves that specific regression; the remaining control-family work is listed below.

The 0.19.3 polling correction passes 884 checks across 18 live runs. Grid-page reads validate their current grid and containing form without rediscovering unrelated ordinary controls. The component adapts its normal idle interval to callback cost; pending editor operations retain the fast path. No new application hook or timer is required. The matrix covers ordinary/generated controls, native array/collection/entity grids, a child grid, metadata failures, AreaList text/checkbox editing and a 600-button form. Compiled VoiceOver reads and activates AreaList checkboxes and reaches both ends of the large ordinary form. [Exact modes, checks and hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/polling.json). This does not complete every control family or application workflow.

The 0.19.2 naming defaults pass 276 live checks across ordinary and generated forms, in interpreted and compiled ARM desktop execution. Untitled buttons, checkboxes, radio buttons and popups reuse their current help tips; captions and explicit labels take precedence. Long tips respect the name limit without splitting a Unicode character. Empty static captions enter the tree when the application supplies text. [Reproductions, reports and matching package hashes](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/control-names.json). Review the resulting names: a help tip can describe an error instead of an action.

The 0.19.1 button-dispatch correction passes 240 live checks across ordinary controls and generated repeated/nested children, in interpreted and compiled ARM desktop execution. A scope-changing button previously ran its normal handler but reported a rejected receipt after its old route retired. Its receipt now acknowledges posting the verified click; business results still require separate checks. Stale descendants remain unusable. [Reproduction and matching builds](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/button-activation.json).

The 0.19 AreaList checkbox adapter passes 30 checks in interpreted 4D and 30 in native ARM compiled 4D. A compiled VoiceOver run passes 34 checks, including checkbox reading/activation and return to an ordinary field. Existing grid configuration and vendor callbacks are preserved. Normal, small and mini Boolean/integer checkbox displays, focus, commit/cancel, permissions, validation rejection and stable sorted identities are covered. [Exact scope](VALIDATION.md#arealist-checkbox-cells-september-24).

The 0.18 editor-cache correction passes the six interpreted/compiled AreaList suites and a compiled Guard Malloc case. AreaList Pro 11.4.2 corrupts memory when reading, copying or committing long supplementary Unicode text in a bridge-free one-cell project. The 11.4.3b5 preview fails at the same conversion in the complete fixture. The adapter continues to reject supplementary input before mutation. The experimental clipboard workaround was removed because it did not resolve that defect. See the [reproduction](https://github.com/KyleKincer/4d-accessibility/blob/main/tests/AREA-LIST-UNICODE.md).

Generated wrappers opened with different plain/shared/entity/class data now preserve original lifecycle events without adding attributes to incompatible data. All eight interpreted/compiled wrong-data cases pass, 56 checks. Preparing a wrapper on non-plain data remains unsupported.

## Implemented and exercised

Synthetic live 4D 20.8 fixtures on Apple Silicon/macOS 26 cover ordinary text, buttons, checkboxes/radios, typed dropdowns, hierarchical popup menus, editable combos, semantic groups, described images, progress, numeric/date/time rulers and steppers, automatic repeated/nested page subforms, generated forms and custom providers. Editable progress uses a shared-controller mapping.

Flat grids expose all logical rows and columns for native arrays, collections, entity selections and AreaList Pro. AreaList text editing supports BMP text only; supplementary text is an accepted vendor limitation, and further cell types remain open. Native array and AreaList stable keys may use existing Text, Integer or LongInt arrays, so integer line IDs need no extra column. Tests cover distant rows, stable identity, sorting, selection, native editors, validation, Undo/Redo, stale requests, repeated child grids, native checkbox/popup cells and AreaList checkboxes. Coverage and execution modes differ by family. Licensed compiled AreaList navigation/reveal and explicit VO-Space selection pass separately. See [validation](VALIDATION.md).

Root forms keep ownership outside persisted entities, class instances and 4D shared objects; their live interpreted/compiled ownership matrix passes.

## Work required before full accessibility

- Tabs, dials, editable pictures, hierarchical lists and standard-action-generated menus need implementation or further validation.
- Classic current/named-selection grids, native hierarchy, custom/styled/protected editors and further AreaList layouts remain open.
- Native grid headers pass array, collection and entity tests in interpreted and compiled modes. An earlier intermittent compiled entity activation reported delivery without a handler event. A fresh full run passes; its cause remains unresolved and is retained in the validation record.
- IME/grapheme behavior, wrapped text geometry, errors/status speech and complete reading order need further work.
- Generated wrappers and explicit child registration still require private plain data.
- Voice Control/Switch Control, overlapping providers, multiple displays, older macOS reveal, root forms larger than their window, Intel runtime and remote entity performance need validation.
- Broader compiled desktop coverage, client/server delivery and complete real application workflows remain open.
- The plug-in manifest ID must not conflict with another plug-in in a target host. The current ID matches the optional host lookup. Developer ID signing and notarization pass for the 0.19.5 signed candidate; full-UI coverage remains unfinished.

The native binary's deployment target is a compiler setting, not a tested macOS support promise. Windows has no accessibility implementation. A label on an opaque interactive control, a compiler pass or a clean diagnostics report is not proof of an accessible screen.

## Accepted vendor limitation

The AreaList supplementary-Unicode conversion defect does not block a stable release. Keep the documented restriction and reject supplementary text in bridge editing requests before mutation. Ordinary 4D text editors are unaffected. Direct input into the vendor editor remains subject to the vendor defect. Remove the restriction only after a vendor fix passes the [reproduction and editing matrix](https://github.com/KyleKincer/4d-accessibility/blob/main/tests/AREA-LIST-UNICODE.md).

## Completion

For each claimed scenario, require the [acceptance matrix](REQUIREMENTS.md), complete live tree/navigation/action tests, unchanged business and editor behavior, both claimed execution modes and reproducible release packages. Keep failures visible until corrected. The older explicit row-summary examples remain compatibility references; their viewport limits are not the design for new integrations.
