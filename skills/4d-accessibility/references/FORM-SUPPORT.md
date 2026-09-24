# Integrating different form families

Use [the integration walkthrough](INTEGRATION.md) for installation and the form lifecycle. This reference explains what changes when a form becomes more complex. The implementation and validation status are separate: a compiler pass alone does not establish runtime behavior.

Use the [current support status](STATUS.md) and [validation record](VALIDATION.md) for measured behavior and execution modes. Read the public [coverage report](INTEGRATION.md#check-the-forms-coverage) to identify unsupported objects and missing labels in the running form.

## Subforms and repeated instances

With the automatic provider, start and stop only the root. Visible page subforms are discovered recursively. Supply child labels in `options.children`, and call `AXB_Form("invalidate"; New object("subform"; containerName))` at the shared replacement boundary. Children can share a business-data object. The bridge owns their distinct identities outside that data. Repeated forms with shared control bindings may need the [form-level focus observer](INTEGRATION.md#repeated-controls-with-ambiguous-focus). See [the automatic subform example](examples/AUTOMATIC-FORM.md#repeated-and-nested-page-subforms).

### Explicit child providers

The following registration contract applies when a form supplies its own `describe`/`apply` callbacks, for example the older explicit grid-summary adapters.

The top-level form calls `AXB_Form("start"; options)` once. Enable `On Load` and `On Unload` on every participating child form. Each child calls `AXB_Form("register"; options)` during its own load and `AXB_Form("stop"; New object)` during unload. `register` stores that instance's description and action formulas; it does not create another window scheduler.

In the parent's description, list the subform **object names**, not the form definition names:

```4d
$description.subforms:=New collection("ShippingAddress"; "BillingAddress")
```

Each child uses the same describe/apply contract as a standalone form. Nested children list their own immediate subform objects. Give each container its own data-source object. For example, initialize `Form.shipping:=New object` and `Form.billing:=New object`, then set the containers' Variable or Expression properties to `Form.shipping` and `Form.billing`. Do this before displaying the parent. Each child then receives its object as `Form`, as described in [4D's subform documentation](https://developer.4d.com/docs/20/FormObjects/subformOverview).

Do not bind a child to the parent's whole `Form` or bind two children to the same object. Their registration properties would overwrite each other, and a child's stop could stop its parent. Share business values through separate properties when needed.

The host helper enters each child through a fixed `EXECUTE METHOD IN SUBFORM` call. It qualifies local control IDs by instance and parent lifetime, converts coordinates through 4D, and clips through the containing rectangles. Handlers still receive their local IDs, such as `name` or `lines`. A control named `Name` in two address forms therefore routes to two different instances.

For `OBJECT SET SUBFORM`, unregister the old child explicitly, assign a fresh instance object, then replace it:

```4d
var $reply : Object
EXECUTE METHOD IN SUBFORM("ShippingAddress"; "AXB_Form"; $reply; "stop"; New object)
Form.shipping:=New object
OBJECT SET VALUE("ShippingAddress"; Form.shipping)
OBJECT SET SUBFORM(*; "ShippingAddress"; "AlternateAddress")
```

If the child has application cleanup in On Unload, extract that cleanup into a shared child method and call it through `EXECUTE METHOD IN SUBFORM` before assigning the new data. The tested generated-form replacement does not deliver the old On Unload event. [The generated-form recipe](examples/DYNAMIC-FORM.md#generated-subforms) shows the complete sequence.

The replacement registers during its own load. Reuse of the container name does not authorize an old accessibility element to act on the replacement. If the parent changes records, return its new record ID in `description.scope`; that invalidates descendants too.

An AreaList inside a subform keeps its grid arrays and the AreaList helper methods in the host. Its describe/apply callbacks run in that subform, where the area and pointers belong. Give repeated instances separate area references and array bindings, as shown in [the AreaList subform recipe](examples/AREALIST-FORM.md#put-the-grid-inside-an-input-subform). Register the child and list its container in the parent as above; the grid binding contract is unchanged.

Page subforms and list subforms are distinct. Repeated records in a list subform require a row adapter with stable record IDs. Registering a detail form does not establish a repeated-record adapter.

## Pages and generated forms

Automatic discovery and `AXB_Controls` read current-page and inherited objects; off-page controls leave the snapshot. Tabs are not exposed yet, so page switching remains unfinished. With `AXB_Controls`, an allowlisted name that exists nowhere in the form is an adapter error, which catches misspelled names.

JSON-generated forms use the same lifecycle as named forms. [Use `AXB_Dynamic` at the opening point](examples/DYNAMIC-FORM.md) to wrap the original form method and start after its initialization. It adds the bridge load/unload events and preserves the original subscriptions. Supply a private `Form` data object for each instance. For explicit `describe` providers, keep IDs stable for the same semantic control and update the allowlist when controls are added or removed. Automatic discovery handles these changes itself.

Use `scope` to distinguish a replaced model or record. A reused object name must not silently turn an old request into an action on different data. When replacing the entire form, stop the old registration and start a new one. Nonblocking dialogs also need unload/error cleanup; the code after `DIALOG(...; *)` is not their close hook.

## Native list boxes

Standard `AXScrollToVisible` is offered on macOS 26 only. Support on earlier macOS versions remains unfinished; see [scrolling and reading order](INTEGRATION.md#scrolling-and-reading-order).

Use automatic discovery with [`options.grids`](GRIDS.md#add-a-native-array-list-box-without-replacing-discovery) for a flat native array list box. The complete provider exposes every non-hidden logical row and displayed scalar column, headers, lazy offscreen values, reveal, selection and the real cell editor. A hidden unique Text key column identifies rows after sorting. Existing validation, Undo/Redo and dialog cancellation remain in charge. This provider composes with ordinary controls and repeated subforms. Its existing LongInt Row Control Array supplies hidden, disabled and nonselectable states. [Row-state rules](GRIDS.md#reuse-row-metadata). The working source accepts [column descriptions](GRIDS.md#describe-custom-native-grid-columns) for picture, object-array and styled displays.

Collection and entity-selection list boxes now use [complete automatic grids](GRIDS.md#use-a-collection-or-entity-selection-list-box) for direct property columns. Map the existing Selected Items expression; supply a stable collection key property, or use the entity dataclass primary key. The shared pipeline provides lazy values, native selection/reveal, editing, validation, Undo/Redo and cancellation. Collection object replacement and entity dataclass replacement retire stale cells. The working source accepts [descriptions for computed/picture/custom columns](GRIDS.md#describe-custom-native-grid-columns), using the existing application formatter. Described columns remain read-only through accessibility. Row metadata can use a direct stored property automatically or one Formula mapped to the existing Meta Info Expression. Native row metadata separates selection restrictions from native editing permission; its [expanded isolated live validation passes](VALIDATION.md). [Row metadata configuration](GRIDS.md#reuse-row-metadata). Custom cell editing and additional layouts remain unfinished. Current/named classic selections must also preserve the application's record buffer and selection conventions; a binding change cannot be handled by reusing an unrelated selection.

Native Boolean checkbox/popup and numeric mixed-state cells use their existing editors and callbacks through the [automatic grid adapter](GRIDS.md#native-checkbox-and-popup-cells). Hierarchical arrays and custom cells need further interaction support. Object-array values are readable through a column description. An unsupported binding must be resolved before its screen can be considered accessible. A live 4D 20.8 audit found no usable native array/collection row tree to fall back to.

## AreaList grids and large tables

Use [automatic AreaList grid composition](GRIDS.md#add-an-arealist-grid-to-the-same-form) for flat array-backed areas. It discovers the actual vendor bindings and exposes complete logical rows/columns alongside the form's ordinary controls. Supply existing stable keys, readiness and record scope, plus text descriptions for meaningful custom/picture columns. Repeated subforms use separate area variables and arrays. Native selection/reveal and BMP text entry pass the live fixtures with existing vendor entry/exit validation and Undo/Redo. VoiceOver reaches the final logical row and returns to ordinary controls.

Supplementary-Unicode entry, protected write-only entry, hierarchy/SubALP, breaks, transposition and other complex vendor modes remain required work. The current early rejection of supplementary input prevents a reproduced vendor editor defect; it is not an accepted final limitation. [Evidence](VALIDATION.md).

Keep table operations separate from business commands. Selection can call the application's existing shared selection handler once when configured, but must not replay a mouse handler that also navigates or changes edit mode. Business commands consume the verified selection through their normal menu/controller path.

The ordinary tree allows 4,096 nodes, 1,048,576 UTF-16 units per text value and a 16 MiB envelope. Complete grid rows are indexed separately and their values load in bounded pages. The 50,000-row native fixture verifies indexed access and VoiceOver navigation. Do not truncate application arrays to meet a transport bound.

The earlier explicit summary adapters remain available for compatibility. Their limits differ: at most 200 AreaList keys, 10,000 native array/collection rows or 1,000 entities, with at most 100 visible summary rows per list. They do not provide the complete-grid contract and should not be used as its replacement.

## Other controls and existing accessibility

| Family | Integration rule |
| --- | --- |
| Ordinary input | The automatic provider uses the actual editor, formatting and normal validation. Protected inputs remain in the tree as secure text fields; their contents and selection are omitted. |
| Checkbox and radio | Automatic discovery exposes checked/unchecked and a checkbox's mixed state. Activation uses the real control and existing handler. Regular and flat three-state checkbox cycles and VoiceOver activation pass in isolated live fixtures. |
| Picture/custom button | The automatic provider uses the real button action and current availability. Supply a meaningful label for an icon whose purpose cannot be inferred. |
| Typed dropdown and hierarchical popup | Automatic discovery reads typed arrays, object choices, and choice-list values or references. The real native menu and its existing handlers perform selection. |
| Editable combo | Automatic discovery preserves array, object and scalar bindings, display formats, editing and validation. The combo exposes its real native popup, selection, confirmation and cancellation without extra host methods. Live VoiceOver opening, arrow navigation, spoken selection and Return confirmation pass. Unusual popup placement remains under validation. |
| Group boxes | The working semantic extension reads captions and nests controls under an unambiguous containing box. Optional `group` metadata resolves overlapping groups. |
| Progress and busy indicators | Automatic numeric/date/time values, actual ranges and orientation. Editable bars require an `adjust` formula that calls the shared application controller. Read-only and busy indicators need no callback. See the [controller recipe](INTEGRATION.md#map-editable-progress-bars-to-a-controller). |
| Static images and image status | Supply missing text through `controls.<object>.description`, or mark decorative images. The semantic extension publishes the current text alternative for VoiceOver and AX tools. |
| Numeric/date/time rulers and steppers | Automatic values, formatted descriptions and increment/decrement actions. Date rulers expose unbounded date incrementors to match their keyboard behavior; numeric/time sliders expose their configured ranges. Steppers invoke their existing click handler; rulers preserve normal keyboard handling. Disabled/read-only states remain readable. |
| Tabs, date-picker popups and other adjustable variants | The remaining adapters must expose available choices and preserve the original controller behavior. See [the current support status](STATUS.md). |
| Web areas | Preserve usable browser accessibility. The coverage report lists `providerPending` because automatic discovery omits the area; verify its existing native tree. Add an adapter only for a verified missing behavior. |
| Other plugin areas | Use that plugin's documented geometry/state/action API and an application allowlist. AreaList bindings cannot describe another plugin. |
| Menus | Prefer the existing native menu item and its normal enablement/action. Add a bridge command only when a real custom control requires it. |

## Multiple windows, modals, and cleanup

Each root form owns its own session; repeated object names in different windows are valid. Publish state while the form is alive, but accept actions only in the active permitted form. The helper checks the foreground window and instance identity; application authorization stays in the handler. Keep each poll bounded and synchronous. A callback that opens a modal may block the parent callback until it returns.

Call stop from unload and from the application's existing fatal form-error path before abandoning the context. Preserve the application's error handler and timer. Do not install a global handler that quits the application merely because an optional adapter failed.

Completion for each family requires an external AX run in the application's interpreted and compiled execution modes, including invalid actions, disabled/hidden state, stale references, and its specific sort/refresh/replacement behavior. Keyboard and VoiceOver validation remain distinct checks; an automated AX test does not prove either experience.

Legacy row-summary navigation and complete logical-grid navigation have different contracts. Consult [validation scope](VALIDATION.md), then rerun the relevant current fixture and the integrating application workflow.
