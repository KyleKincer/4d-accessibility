# Implementation status

This is a development preview. The goal is complete access to the UI through standard macOS accessibility, with minimal application code. The goal is not yet met.

## Implemented and exercised

Synthetic live 4D 20.8 fixtures on Apple Silicon/macOS 26 cover ordinary text, buttons, checkboxes/radios, typed dropdowns, hierarchical popup menus, editable combos, semantic groups, described images, progress, numeric/date/time rulers and steppers, automatic repeated/nested page subforms, generated forms and custom providers. Editable progress uses a shared-controller mapping.

Full logical flat grids support native arrays, collections, entity selections and AreaList Pro. AreaList stable keys may use existing Text, Integer or LongInt arrays, so integer line IDs need no extra column. Tests cover distant rows, stable identity, sorting, selection, native editors, validation, Undo/Redo, stale requests, repeated child grids and native checkbox/popup cells. Coverage and execution modes differ by family. See [validation](VALIDATION.md).

## Work required before full accessibility

- Tabs, dials, editable pictures, hierarchical lists and standard-action-generated menus need implementation or further validation.
- Classic current/named-selection grids, native hierarchy, custom/styled/protected editors and further AreaList layouts remain open.
- Cold asynchronous values can still be spoken as Loading after data arrives. Licensed compiled AreaList navigation/reveal and explicit VO-Space selection now pass separately.
- Native grid headers pass array, collection and entity tests in interpreted and compiled modes. An earlier intermittent compiled entity activation reported delivery without a handler event. A fresh full run passes; its cause remains unresolved and is retained in the validation record.
- AreaList supplementary Unicode editing, IME/grapheme behavior, wrapped text geometry, errors/status speech and complete reading order need further work.
- Starting a root directly on a persisted entity or 4D shared object is unsupported; the current API writes form state and does not yet return a safe named rejection for this case.
- Generated forms and explicit providers require private data objects. Shared-data ownership is incomplete for those paths.
- Voice Control/Switch Control, overlapping providers, multiple displays, older macOS reveal, root forms larger than their window, Intel runtime and remote entity performance need validation.
- Broader compiled desktop coverage, client/server delivery and complete real application workflows remain open.
- The native package ID is provisional. Public production distribution also requires release signing and notarization.

The native binary's deployment target is a compiler setting, not a tested macOS support promise. Windows has no accessibility implementation. A label on an opaque interactive control, a compiler pass or a clean diagnostics report is not proof of an accessible screen.

## Completion

For each claimed scenario, require the [acceptance matrix](REQUIREMENTS.md), complete live tree/navigation/action tests, unchanged business and editor behavior, both claimed execution modes and reproducible release packages. Keep failures visible until corrected. The older explicit row-summary examples remain compatibility references; their viewport limits are not the design for new integrations.
