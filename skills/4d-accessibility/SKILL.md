---
name: 4d-accessibility
description: Integrate or extend the 4D Accessibility bridge in 4D projects, including ordinary forms, tabs, native or AreaList Pro grids, list subforms, repeated page subforms, generated forms and automation identifiers. Use when adding accessibility or diagnosing bridge coverage and integration failures.
---

# Integrate 4D accessibility

Prefer an installer-added lifecycle area and automatic discovery. Keep business methods and timers. Return labels and provider configuration from application-owned `AXB_Configure`; map a shared controller only where the adapter needs application intent it cannot infer.

## 1. Establish the integration boundary

Locate the matching bridge source checkout or release package and the host's `Project/Sources`. If this skill was installed separately, follow [acquisition and version checks](references/SETUP.md). This skill directory holds documentation only; take the installer and binaries from the matching kit.

Read [current status](references/STATUS.md), [area installation](references/AREA-INTEGRATION.md) and [matching packages](references/INTEGRATION.md#1-install-once). Inspect the target form definition, form method, object methods, loader, shared opener and replacement/close paths. Identify the host's supported 4D/macOS versions and execution modes.

Use `inventory_forms.py --project-dir /path/to/Project --output /host-local/ignored/form-inventory.json` from the checkout or complete release kit. Keep this static inventory in an ignored host-local directory; it does not establish runtime coverage. Search shared openers, `OBJECT SET SUBFORM`, asynchronous loaders, `CALL FORM`, `CALL WORKER`, `EXECUTE METHOD IN SUBFORM`, nonblocking `DIALOG`, `FORM GOTO PAGE`, AreaList entry/sort callbacks and `DontSortArrays` setters. Inspect runtime pages and generated controls too.

Trace where `Form` data is persisted, including `JSON Stringify`, entity `fromObject` and copies into `Storage`. Record its type and apply [root ownership and failure reporting](references/INTEGRATION.md#preserve-the-form-data-and-report-failures).

Complete with a map of actual controls, lifecycle owners, state persistence and transient UI. Every requested control must have a supported path or an explicit implementation task.

## 2. Install matching parts

Choose a kit from the [availability table](references/STATUS.md#availability). The area path needs 0.20.0 or later. With signed 0.19.7, follow the [manual lifecycle](references/MANUAL-LIFECYCLE.md) instead of the area steps below.

Use `install_host_methods.py --help` from the checkout or complete kit, then install into the directory containing `Sources`. The plugin belongs in `Plugins`, the compiled component in `Components`, and generated methods in `Project/Sources/Methods`. All three parts must come from the same version. Restart 4D after replacing the plugin or component. A Dependency Manager component alone does not install the plugin or host methods.

Add `--area-list` only for AreaList hosts. Keep the same `--compiler-method` target on refresh. Generated methods and their marked compiler block are installer-owned; application configuration methods remain application-owned. If an existing generated method was edited, inspect the change and reconcile it with canonical source before refreshing.

Matching 0.22.0 kits also own `Resources/AXB.FormMetadata.json` next to `Project`. Area installation can generate it even when the selected form has no list. Commit and ship that resource. Refresh it after form changes and reopen affected forms, following the [metadata contract](references/LIST-SUBFORMS.md#install-a-parent-form).

Verify the installed parts from any host method:

- [`AXB_Host("info"; New object)`](references/SETUP.md) must report matching kit versions and a compiled component.
- In `.nativeStatus`, require `areaLifecycle 1`, plus `buttonInput 1` for automatic controls and `tabs 1` for tabs. Version 0.21.0 or later also requires `stableIdentifiers 1`; its helpers return `stableIdentifiersUnavailable` when the plugin lacks this capability. List subforms require `listSubforms 1` in a matching 0.22.0 development kit. See [stable locators](references/IDENTIFIERS.md) when recording or updating automation. In `.componentInfo`, require `capturedStop: 1` and `compiled: True`.

Complete when the installed package checks and host compiler pass. The next step adds the area and verifies registration.

## 3. Choose the smallest form integration

For named forms, rerun the installer with the step 2 options plus repeatable `--form <name>` or `--all-forms`, and `--dry-run`. Resolve conflicts, rerun without `--dry-run`, and review the form diff. Bulk installation skips list/print forms and referenced list-row forms. Named inheritance shares one base area unless that base also serves a list row; detail branches then own their area locally. Bulk migration removes exact installer-owned areas from row forms and shared row bases. Existing objects, layout, methods and events must remain equivalent. The page-zero area owns startup/shutdown. Ordinary forms need no business-method hooks. Add optional `AXB_Configure` for missing labels, `scope`, grids or existing providers, including its application compiler declarations.

When migrating a manual registration, preserve it until area configuration covers the same providers and failure handling. Follow the [migration ordering and ownership rules](references/AREA-INTEGRATION.md#migrate-and-verify), then remove validated one-shot start/stop calls. Keep intentional restart, explicit child registration, invalidation and focus observation where their lifecycle reason remains. The [manual interface](references/MANUAL-LIFECYCLE.md) remains for deliberately application-owned registrations.

Read only the references for the branches present in the host:

| Branch | Read and apply |
| --- | --- |
| Repeated/nested page subforms | [Child ownership and replacement](references/INTEGRATION.md#child-forms). Let the root area own the tree; put child metadata under its container. Reusable child areas do not start a second root. Invalidate before replacing the child or its data binding. Start without a focus observer. If an editor reports the wrong focused control or `ambiguousFocus`, follow the [observer decision and branch checks](references/INTEGRATION.md#repeated-controls-with-ambiguous-focus). Complete the affected descendant branch, rather than adding only a parent call. Compound generated early-focus retention needs a matching 0.21.1 kit. |
| Native array/collection/entity/classic-selection grids | [Native grids](references/GRIDS.md#add-a-native-array-list-box-without-replacing-discovery), including stable keys, selection, column descriptions and native cell controls. For a current/named selection, read [classic selection configuration](references/GRIDS.md#use-a-classic-current-or-named-selection) and verify its kit availability. Use exact native bindings and preserve validation and selection handlers. |
| Classic list subforms | Development only, requiring a matching 0.22.0 kit with `listSubforms 1`. Check [acceptance](references/STATUS.md#classic-list-subforms-in-0220), then [list-subform integration](references/LIST-SUBFORMS.md). Keep the area in the parent. Follow the linked metadata ownership and update contract. Stored scalar fields and primary keys need no new form hooks. Complete the layout's native-editor, selection, saved-value and VoiceOver checks before claiming coverage. |
| AreaList Pro, including repeated child grids | [AreaList grids](references/AREALIST-GRIDS.md). Complete its [live preflight](references/AREALIST-GRIDS.md#preflight-the-live-area) for layout, sorting and stable keys, and give [repeated children](references/AREALIST-GRIDS.md#repeated-child-grids) independent instance data, before adding hooks. Preserve existing vendor semantics. Use the full grid adapter for new work; legacy row summaries do not provide complete navigation. |
| JSON-generated forms | [Generated lifecycle](references/examples/DYNAMIC-FORM.md). Use `AXB_AreaForm(json; "LogicalKey")` at the shared builder and open its returned `.form`. The key selects central configuration without writing to business data; preserve the original method, events and data. Use the advanced `AXB_Dynamic` wrapper only when explicit per-instance provider registration needs its private-data contract. For automatic children, invalidate at replacement. For registered children, close wrapped descendants deepest-first and close the old instance before rebinding. |
| Alerts and confirmations | [Message dialogs](references/MESSAGES.md). Built-in `ALERT`/`CONFIRM`/`Request` are published by the native plugin. Inspect the actual opener, integrate existing application forms, preserve choice/return contracts, and validate the real workflow. |
| Editable progress | Map `controls.<name>.adjust` to the existing [shared adjustment controller](references/INTEGRATION.md#map-editable-progress-bars-to-a-controller). Read-only progress needs no controller. |
| Tab controls | Check [kit availability](references/STATUS.md#availability), then [the tab adapter and its validation status](references/TABS.md). Keep existing bindings, labels, handlers and standard actions. Ordinary tabs require no extra form hooks. Inspect the actual strip, icon or compact-menu presentation at supported window sizes. |
| Custom semantics | Use narrow `controls` metadata such as `label`, `description`, `decorative`, `protected`, `group` and `adjust`, or grid `columns`, `meta` and `onSelection`. See [configuration](references/INTEGRATION.md). A custom `apply` alone replaces all automatic action routing. Use [explicit providers](references/FORM-SUPPORT.md) only for an intentionally owned description/action contract. |
| Hierarchical grids or other unsupported controls | Compare [status](references/STATUS.md) and diagnostics with the live tree. For an entire-UI request, follow [extending the bridge](references/EXTENDING.md); a text description does not implement an interactive control. |
| Web areas | System-engine fixture accepted; embedded engine pending. Follow [native web-area integration, engine checks and reading-order limits](references/WEB-AREAS.md). Preserve the current engine, HTML and callbacks. Verify browser-owned descendants and actual submission, then return to 4D editing. |
| Other plugin areas | Inspect their existing AX children, navigation and actions first. Preserve a complete native provider. An opaque interactive area requires a tested adapter or upstream fix. |

For grids, apply the [loading guard](references/GRIDS.md#gate-loading-and-record-changes) and the binding-specific [identity rules](references/GRIDS.md). Entity, class and shared roots keep that state in [existing editor state](references/examples/RECORD-EDITOR.md#entity-class-and-shared-root-data). Never add UI attributes to persisted entities or bypass shared-object locks. For a form combining fields, an editable grid and subforms, follow the [record-editor example](references/examples/RECORD-EDITOR.md).

Open the integrated form. In its root form's process, through existing debugging infrastructure or a temporary development-only call, run `AXB_Area("diagnostics"; ""; "")`. It must show an active registration. Require `configured: True` when the application supplies a configuration callback. An empty area list is not success. If packages are intentionally optional, also verify normal behavior without them. Treat `dependencyUnavailable` as optional absence; surface other startup failures through existing application diagnostics.

Complete when registration succeeds, every owned hook has a lifecycle reason and every custom callback maps to existing application behavior. Keep ordinary editors, validation, Undo/Redo, menus and business commands as the authority for mutations. A text description is sufficient for a visual-only value; it does not replace an interactive custom editor.

## 4. Validate the whole requested UI

Follow the [host AX inspection and scenario checks](references/VERIFY.md), [coverage diagnostics](references/INTEGRATION.md#check-the-forms-coverage) and [acceptance requirements](references/REQUIREMENTS.md). From the root, inspect `AXB_Form("diagnostics"; New object)` after the first snapshot. Exercise each page, loading and error state, child replacement, record switch, sort, filter and supported window size.

For recorded automation, follow [stable identifiers and window scoping](references/IDENTIFIERS.md). Use an external AX client and VoiceOver against the real running form. Verify meaningful content, logical navigation, enabled/read-only behavior, offscreen reveal, editing, validation, cancellation and stale-reference rejection. Compare action results and persisted business state with the ordinary UI. Run interpreted and compiled tests for the modes being claimed; compilation alone proves neither.

An AX action return confirms transport, not application completion. Read the bridge root's `AXHelp` receipt and verify the resulting UI state. A rejected or missing receipt does not prove rollback. Inspect the result before considering any retry of a mutating action.

Complete only when every requested interactive element has a working provider and the requested workflow succeeds with assistive technology. If desktop access or a required license is unavailable, finish the source diff and available checks, then report the exact blocked tests, expected results and reproduction commands. Remove any temporary diagnostics call before delivery. Keep live validation pending rather than calling the integration complete.

Deliver the smallest host diff, the installed version, the tested forms/modes and the remaining gaps. Use the [integration reference](references/INTEGRATION.md) as the API authority rather than copying another application's configuration.
