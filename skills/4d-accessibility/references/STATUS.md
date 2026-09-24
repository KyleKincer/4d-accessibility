# Implementation status

This is a development preview. The goal is complete access to the UI through standard macOS accessibility, with minimal application code. The goal is not yet met.

## Current development check

The 0.19 AreaList checkbox adapter passes 30 checks in interpreted 4D and 30 in native ARM compiled 4D. A compiled VoiceOver run passes 34 checks, including checkbox reading/activation and return to an ordinary field. Existing grid configuration and vendor callbacks are preserved. Normal, small and mini Boolean/integer checkbox displays, focus, commit/cancel, permissions, validation rejection and stable sorted identities are covered. [Exact scope](VALIDATION.md#arealist-checkbox-cells-september-24).

The 0.18 editor-cache correction passes the six interpreted/compiled AreaList suites and a compiled Guard Malloc case. AreaList Pro 11.4.2 corrupts memory when reading, copying or committing long supplementary Unicode text in a bridge-free one-cell project. The 11.4.3b5 preview fails at the same conversion in the complete fixture. The adapter continues to reject supplementary input before mutation. The experimental clipboard workaround was removed because it did not resolve that defect. See the [reproduction](https://github.com/KyleKincer/4d-accessibility/blob/main/tests/AREA-LIST-UNICODE.md).

Generated wrappers opened with different plain/shared/entity/class data now preserve original lifecycle events without adding attributes to incompatible data. All eight interpreted/compiled wrong-data cases pass, 56 checks. Preparing a wrapper on non-plain data remains unsupported.

## Implemented and exercised

Synthetic live 4D 20.8 fixtures on Apple Silicon/macOS 26 cover ordinary text, buttons, checkboxes/radios, typed dropdowns, hierarchical popup menus, editable combos, semantic groups, described images, progress, numeric/date/time rulers and steppers, automatic repeated/nested page subforms, generated forms and custom providers. Editable progress uses a shared-controller mapping.

Flat grids expose all logical rows and columns for native arrays, collections, entity selections and AreaList Pro. AreaList text editing supports BMP text only; supplementary text and further cell types remain open. Native array and AreaList stable keys may use existing Text, Integer or LongInt arrays, so integer line IDs need no extra column. Tests cover distant rows, stable identity, sorting, selection, native editors, validation, Undo/Redo, stale requests, repeated child grids, native checkbox/popup cells and AreaList checkboxes. Coverage and execution modes differ by family. Licensed compiled AreaList navigation/reveal and explicit VO-Space selection pass separately. See [validation](VALIDATION.md).

Root forms keep ownership outside persisted entities, class instances and 4D shared objects; their live interpreted/compiled ownership matrix passes.

## Work required before full accessibility

- Tabs, dials, editable pictures, hierarchical lists and standard-action-generated menus need implementation or further validation.
- Classic current/named-selection grids, native hierarchy, custom/styled/protected editors and further AreaList layouts remain open.
- Cold asynchronous values can still be spoken as Loading after data arrives.
- Native grid headers pass array, collection and entity tests in interpreted and compiled modes. An earlier intermittent compiled entity activation reported delivery without a handler event. A fresh full run passes; its cause remains unresolved and is retained in the validation record.
- IME/grapheme behavior, wrapped text geometry, errors/status speech and complete reading order need further work.
- Generated wrappers and explicit child registration still require private plain data.
- Voice Control/Switch Control, overlapping providers, multiple displays, older macOS reveal, root forms larger than their window, Intel runtime and remote entity performance need validation.
- Broader compiled desktop coverage, client/server delivery and complete real application workflows remain open.
- The native package ID is provisional. Public production distribution also requires release signing and notarization.

The native binary's deployment target is a compiler setting, not a tested macOS support promise. Windows has no accessibility implementation. A label on an opaque interactive control, a compiler pass or a clean diagnostics report is not proof of an accessible screen.

## Completion

For each claimed scenario, require the [acceptance matrix](REQUIREMENTS.md), complete live tree/navigation/action tests, unchanged business and editor behavior, both claimed execution modes and reproducible release packages. Keep failures visible until corrected. The older explicit row-summary examples remain compatibility references; their viewport limits are not the design for new integrations.
