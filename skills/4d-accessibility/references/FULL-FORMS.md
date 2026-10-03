# Full-form compatibility

The target is an accessible macOS interface for every interactive 4D form in the supported runtime versions. Every meaningful control must support reading, navigation and its ordinary operations, including controls in subforms and outside the visible viewport. A label on an otherwise opaque area does not meet that target. The [acceptance requirements](REQUIREMENTS.md) define completion; [current status](STATUS.md) records what has passed.

## Integration stays the same

Keep one installer-added area per root form and one optional application-owned configuration callback. Implement generic control support in the shared helpers and native plugin. Reuse the application's existing labels, bindings, validation and handlers. An application supplies only information that cannot be discovered safely, such as row identity, a calculated value's existing Formula, or a custom control's controller.

For embedded controls, use their existing native accessibility tree when it provides complete semantics. Otherwise add a shared adapter for that control family, using the same configuration callback. Inspecting a control must preserve application data, selection, focus and business execution. Actions must exercise its normal UI or existing controller, then verify the result.

## Compatibility work by family

The following is an implementation checklist, not a coverage percentage. A source inventory cannot establish which forms are active or whether an accessible workflow succeeds.

| Family | Current position | Work needed for complete support |
| --- | --- | --- |
| Ordinary text, buttons, checkboxes, radios, dropdowns and combos | Live coverage exists for the cases in status. | Complete input-method, grapheme, wrapped-text geometry and protected-editor checks. |
| Styled native text | In 0.21.0, named/generated forms pass interpreted and compiled native editing, style preservation, Unicode selection, multiline input, original validation, Undo and stale-element checks. Compiled VoiceOver reads both variants. Both compiler targets and private-copy command checks pass. | Validate long input. Read embedded expressions from their original rendered context without extra evaluation; expose actionable links and style ranges. Styled grid-cell editors remain separate work. |
| Array, collection and entity list boxes | Flat logical grids, native editors and selected cell types are exercised. | Support hierarchy, remaining cell types and remote performance. Keep row identities stable after sorting and replacement. |
| Page subforms and generated forms | Automatic discovery, area-owned lifecycle and compound nonblocking focus are exercised. [0.21.1 evidence](../../../validation/compound-form-focus-0.21.1.json). | Validate additional table-form contexts. |
| Classic list subforms | The 0.22.0 source/CI adapter exposes a named table list form through automatic parent discovery and generated metadata. Project/table parent fixtures pass the scoped 912-check gate and two zero-difference window comparisons. [Integration and limits](LIST-SUBFORMS.md). | Publish matching package provenance and finish signed/remote delivery. Shared-grid regressions pass. Visible horizontal/vertical scrollbar geometry has scoped acceptance. Automatic relations, nonzero pages, page-nested lists, multiple lists, dynamic definitions, detail openers, grouped/break layouts, embedded controls, transactions and client/server data remain separate work. |
| Tabs | Version 0.21.0 passes 628 interpreted AX/compiled VoiceOver checks and unchanged-pixel comparisons without new application hooks. See [tab coverage](TABS.md#coverage). | Existing-control regressions pass. A runtime that renders actual scroll arrows needs a separate check; the tested narrow icon control renders a popup. |
| Classic current/named-selection list boxes | Flat stored-field adapter passes 164 checks across six current/named-selection runs, including compiled VoiceOver. | Native/VoiceOver acceptance, both pixel comparisons and existing-grid regressions pass. Add per-row restrictions and validate custom columns, transaction records, child grids and client/server data separately. |
| Hierarchical lists | Not implemented. | Preserve item references, parent/child relationships, expansion, selection, editing and distant navigation. |
| Splitters, dials, button grids and picture menus | Not implemented. | Expose each native operation with the correct role, value and bounds. Preserve drag/click handlers and constrained movement. |
| Pictures and custom drawing | Described/decorative images are exercised. Editing is incomplete. | Expose meaningful regions and existing editing operations through a reusable provider, rather than treating interactive content as one image. |
| Web areas | The macOS system engine passes native HTML/4D coexistence, validation/submission, compiled VoiceOver and zero-difference pixels with no additional host hooks. The exact 0.22.1 kit interleaves native web content with neighboring 4D controls under eligible native containers. [Engine limits and integration](WEB-AREAS.md). | Validate nested, scrolled and multiple-web layouts, actual application scripts, popups and frames. Embedded Chromium has no native web tree in the bridge-free post-load VoiceOver probe; establish a supported activation route and complete its separate gate. |
| Write Pro, View Pro and third-party plugin areas | Complete embedded-editor support is unvalidated. AreaList has its own tested adapter and documented limits. | Audit existing native trees, avoid duplicate elements, and implement missing family adapters. Include nested navigation, edits, popups and cleanup. Arbitrary third-party code needs either native accessibility or a provider. |
| Built-in dialogs and standard-action menus | Built-in message dialogs fail the bridge-free reproduction on the tested runtime. Existing accessible custom dialogs can be integrated. | Obtain native vendor support or use an application's approved accessible dialog implementation. Validate standard-action-generated menus separately. |
| Window and application behavior | Some modal, repeated and layered cases are exercised. | Complete reading order, status/error announcements, focus restoration, multiple displays, large root forms, overlapping providers and assistive technologies beyond VoiceOver. |

## Styled-text inspection

4D stores style markup alongside text. Accessibility values and selection offsets must refer to visible text, while editing must use the original native editor so style, validation and Undo survive. [4D's styled-text command documentation](https://developer.4d.com/docs/commands/st-get-plain-text) distinguishes the live object from a field or variable and documents reference display modes.

Parsing a fresh private copy of a 4D expression reference can execute its method, even when the requested output mode excludes expression values. The real-command regression test counts method executions and checks source text and `OK` preservation, including encoded reference identifiers. Such references require their original rendered context; the current development helper reports that requirement and disables unsupported edits. It does not evaluate the expression to manufacture an accessibility value.

## Validation order

Finish each adapter's acceptance gate before updating any host's upstream pin. Ordinary styled-field basics have live evidence. Tabs pass live acceptance, unchanged-pixel comparisons and existing-control regressions. Classic selections, compound generated focus, named scalar list subforms and eligible native web composition pass their scoped gates. Hierarchy and further list layouts remain before the larger embedded-editor adapters.

For each family, compare the bridge with the unmodified native UI, exercise external accessibility and VoiceOver, and verify the application result in every claimed execution mode. Test stale elements after hiding, page changes, rebinding and close. Publish the exact source and package hashes with the results. A compiler pass or an accepted AX request cannot close the family.

The current implementation is macOS-only. Windows accessibility needs its own native backend and acceptance tests. Vendor defects and unsupported families remain explicit until their reproductions pass; they are not included in a claim of complete compatibility.
