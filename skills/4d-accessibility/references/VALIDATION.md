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
