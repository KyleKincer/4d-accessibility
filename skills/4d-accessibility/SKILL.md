---
name: 4d-accessibility
description: Integrate or extend the 4D Accessibility bridge in 4D projects, including ordinary forms, native or AreaList Pro grids, repeated subforms and generated forms. Use when adding accessibility or diagnosing bridge coverage and integration failures.
---

# Integrate 4D accessibility

Use the host's existing form lifecycle and business handlers. Prefer automatic discovery plus configuration; add a shared controller mapping only where the adapter needs application intent that it cannot infer.

## 1. Establish the integration boundary

Locate the matching bridge source checkout or release package and the host's `Project/Sources`. If this skill was installed separately, follow [acquisition and version checks](references/SETUP.md). Its directory contains documentation, not the installer or binaries.

Read [current status](references/STATUS.md) and [installation and ordinary forms](references/INTEGRATION.md#1-install-once). Inspect the target form definition, form method, object methods, loader, shared opener and replacement/close paths. Identify the host's supported 4D/macOS versions and execution modes.

Use `inventory_forms.py --project-dir /path/to/Project --output /host-local/ignored/form-inventory.json` from the checkout or complete release kit. Keep this static inventory in an ignored host-local directory; it does not establish runtime coverage. Search shared openers, `OBJECT SET SUBFORM`, asynchronous loaders, `CALL FORM`, `CALL WORKER`, `EXECUTE METHOD IN SUBFORM`, nonblocking `DIALOG`, `FORM GOTO PAGE`, AreaList entry/sort callbacks and `DontSortArrays` setters. Inspect runtime pages and generated controls too.

Trace where `Form` data is persisted, including `JSON Stringify`, entity `fromObject` and copies into `Storage`. Record its type and apply [root ownership and failure reporting](references/INTEGRATION.md#preserve-the-form-data-and-report-failures).

Complete with a map of actual controls, lifecycle owners, state persistence and transient UI. Every requested control must have a supported path or an explicit implementation task.

## 2. Install matching parts

Use `install_host_methods.py --help` from the checkout or complete kit, then install into the directory containing `Sources`. The plugin belongs in `Plugins`, the compiled component in `Components`, and generated methods in `Project/Sources/Methods`. All three parts must come from the same version. A Dependency Manager component alone does not install the plugin or host methods.

Add `--area-list` only for AreaList hosts. Keep the same `--compiler-method` target on refresh. Generated methods and their marked compiler block are installer-owned; application configuration methods remain application-owned. If an existing generated method was edited, inspect the change and reconcile it with canonical source before refreshing.

Check [`AXB_Host("info")` in setup](references/SETUP.md): component/plugin versions must match the kit, `compiled` must be True, and form startup must accept the installed capabilities. Complete when those checks and the host compiler pass and the selected existing ordinary form starts successfully. If packages are intentionally optional, also verify normal form behavior without them. Treat `dependencyUnavailable` as optional absence; surface other startup failures through the application's existing diagnostics.

## 3. Choose the smallest form integration

For ordinary named forms, add `AXB_Form("start"; options)` after successful On Load initialization and `AXB_Form("stop"; New object)` to On Unload and existing fatal cleanup. Preserve the timer. Read [the automatic example](references/examples/AUTOMATIC-FORM.md) for labels and child configuration.

Read only the references for the branches present in the host:

| Branch | Read and apply |
| --- | --- |
| Repeated/nested page subforms | [Child ownership and replacement](references/INTEGRATION.md#child-forms). Start only the root; put child metadata under its container. Invalidate before replacing the child or its data binding. If exercising repeated shared bindings produces `ambiguousFocus`, inspect catch-all or event-agnostic form code before adding the [form-level focus observer](references/INTEGRATION.md#repeated-controls-with-ambiguous-focus). |
| Native array/collection/entity grids | [Native grids](references/GRIDS.md#add-a-native-array-list-box-without-replacing-discovery), including stable keys, selection, column descriptions and native cell controls. Use exact native bindings and preserve validation and selection handlers. |
| AreaList Pro, including repeated child grids | [AreaList configuration and assembled invoice-style example](references/GRIDS.md#add-an-arealist-grid-to-the-same-form). Follow the preflight for layout, sorting, stable keys and independent instance data before adding hooks. Preserve existing vendor semantics. Use the full grid adapter for new work; legacy row summaries do not provide complete navigation. |
| JSON-generated forms | [Generated lifecycle](references/examples/DYNAMIC-FORM.md). Integrate at the shared builder, pass the wrapper's returned JSON, preserve original method/events and use fresh private data. For automatic children, invalidate at replacement. For registered children, close wrapped descendants deepest-first and close the old instance before rebinding. |
| Alerts and confirmations | [Message dialogs](references/MESSAGES.md). Inspect the actual opener, integrate existing application forms, preserve choice/return contracts, and validate the real workflow. Direct built-in calls require migration or a vendor fix. |
| Editable progress | Map `controls.<name>.adjust` to the existing [shared adjustment controller](references/INTEGRATION.md#map-editable-progress-bars-to-a-controller). Read-only progress needs no controller. |
| Custom semantics | Use narrow `controls` metadata such as `label`, `description`, `decorative`, `protected`, `group` and `adjust`, or grid `columns`, `meta` and `onSelection`. See [configuration](references/INTEGRATION.md). A custom `apply` alone replaces all automatic action routing. Use [explicit providers](references/FORM-SUPPORT.md) only for an intentionally owned description/action contract. |
| Tabs, list subforms, classic-selection/hierarchical grids or other unsupported controls | Compare [status](references/STATUS.md) and diagnostics with the live tree. For an entire-UI request, follow [extending the bridge](references/EXTENDING.md); a text description does not implement an interactive control. |
| Web areas and other plugins | Inspect their existing AX children, navigation and actions first. Preserve a complete native provider. An opaque interactive area requires a tested adapter or upstream fix. |

For grids, initialize readiness false at the start of On Load, before any loader; publish the captured loaded record ID before setting readiness true. Follow the binding-specific [identity and loading rules](references/GRIDS.md).

Complete when every owned hook has a lifecycle reason and every custom callback maps to existing application behavior. Keep ordinary editors, validation, Undo/Redo, menus and business commands as the authority for mutations. A text description is sufficient for a visual-only value; it does not replace an interactive custom editor.

## 4. Validate the whole requested UI

Follow the [host AX inspection and scenario checks](references/VERIFY.md), [coverage diagnostics](references/INTEGRATION.md#check-the-forms-coverage) and [acceptance requirements](references/REQUIREMENTS.md). From the root, inspect `AXB_Form("diagnostics"; New object)` after the first snapshot. Exercise each page, loading and error state, child replacement, record switch, sort, filter and supported window size.

Use an external AX client and VoiceOver against the real running form. Verify meaningful content, logical navigation, enabled/read-only behavior, offscreen reveal, editing, validation, cancellation and stale-reference rejection. Compare action results and persisted business state with the ordinary UI. Run interpreted and compiled tests for the modes being claimed; compilation alone proves neither.

An AX action return confirms transport, not application completion. Read the bridge root's `AXHelp` receipt and verify the resulting UI state. A rejected or missing receipt does not prove rollback. Inspect the result before considering any retry of a mutating action.

Complete only when every requested interactive element has a working provider and the requested workflow succeeds with assistive technology. If desktop access or a required license is unavailable, finish the source diff and available checks, then report the exact blocked tests, expected results and reproduction commands. A temporary development-only diagnostics export may be used through existing debugging infrastructure; remove it after inspection. Keep live validation pending rather than calling the integration complete.

Deliver the smallest host diff, the installed version, the tested forms/modes and the remaining gaps. Use the [integration reference](references/INTEGRATION.md) as the API authority rather than copying another application's configuration.
