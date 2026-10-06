# Configure data grids

Install matching packages and add the root [lifecycle area](AREA-INTEGRATION.md). Return these grid options from the application-owned `AXB_Configure` method. Ordinary controls remain automatically discovered. The same options also work with the [manual lifecycle](INTEGRATION.md#2-connect-one-form).

| Grid | Read |
| --- | --- |
| Native array list box | [Array list box](#add-a-native-array-list-box-without-replacing-discovery) |
| Grouped array listbox, read-only development | [Grouped reading](#read-a-grouped-array-listbox) |
| Collection or entity-selection list box | [Collection/entity list box](#use-a-collection-or-entity-selection-list-box) |
| Classic current or named selection | [Classic selection](#use-a-classic-current-or-named-selection) |
| AreaList Pro | [AreaList grids](AREALIST-GRIDS.md) |
| Record editor combining fields, an editable grid and subforms | [Record-editor example](examples/RECORD-EDITOR.md) |

Every kind shares the [loading guard](#gate-loading-and-record-changes), [temporary keys for unsaved rows](#give-unsaved-rows-temporary-keys) and [stable column locators](#describe-custom-native-grid-columns). Flat selectable grids also use the [selection callback contract](#reuse-the-existing-selection-controller). This file is the authority for those contracts.

## Add a native array list box without replacing discovery

In `AXB_Configure`, add the list box's object name and its stable row-key column to the returned options:

```4d
$options:=New object("label"; "Record details"; "scope"; Formula(String(Form.recordID)); \
 "onError"; Formula(ReportAccessibilityFailure($1)))
$options.grids:=New object("Items"; New object(\
 "kind"; "array"; "keyColumn"; "LineID"; "label"; "Record rows"))
```

`Items` is the list box's form-object name. `LineID` is a column bound to the existing Text, Integer or LongInt identity array, with one unique key per source row. Text keys must be nonempty and at most 256 UTF-16 units. Negative integer keys and zero are valid. The column can be hidden. Use a line-record ID, not the displayed row position or a product number that can repeat. The scope changes when the form changes records. All ordinary controls and automatic child forms remain part of the tree because these options omit `describe` and `apply`. Add the [loading guard](#gate-loading-and-record-changes) when rows load after On Load, and [temporary keys](#give-unsaved-rows-temporary-keys) when unsaved rows share a placeholder ID.

The list box's own variable must be its Boolean selection array, with the same row count as the key array. Keep unique numeric IDs in their original array. The bridge converts them to Text only for accessibility identity; callbacks receive the original numeric key. An already unique identity array needs no parallel array. Real-array keys are unsupported.

Keep the existing row-control array too. Automatic grids accept both LongInt flags and legacy Boolean hidden-row arrays, where True hides a row. Hidden rows are omitted from the logical table and cannot be edited through a retained element. The array must match the source row count and follow the list box's existing sorting and filtering. No additional grid option or array conversion is needed. [4D's row-control bindings](https://developer.4d.com/docs/commands/listbox-get-arrays).

The provider discovers the displayed columns, reads their existing scalar formats, and exposes every non-hidden row. Cell values load as accessibility tools request them. It retains keyed cell identities after sorting, scrolls through the native control, and uses the existing editor for supported enterable cells. It does not assign backing arrays during text entry. A completed text action means the text reached the editor; normal validation and commit still happen when editing ends. Keystroke filters can reject the action.

If selection needs the application's existing dependent-UI refresh, add `"onSelection"; Formula(YourExistingSelectionHandler)`. See the [selection callback contract](#reuse-the-existing-selection-controller).

The validated fixture covers flat array list boxes with scalar text, number, date, time or Boolean values and VoiceOver navigation through all logical rows. [Column descriptions](#describe-custom-native-grid-columns) make picture and object-array displays readable. Native checkbox and Boolean popup cells use the [existing control path](#native-checkbox-and-popup-cells). Hierarchical/custom cell editing and cold-cache announcements remain required work.

## Read a grouped array listbox

Matching 0.23.0 development packages add read-only text/date array groups through the parent lifecycle area. Version 0.24.0 adds optional application-controlled disclosure. The stable 0.22.1 packages do not include this adapter. Configure the existing hierarchical listbox with `kind: "outline"`, its hidden row-key column and a label:

```4d
$options.grids:=New object("Grouped"; New object(\
 "kind"; "outline"; "keyColumn"; "RowKey"; "label"; "Grouped items"))
```

Use one unique, nonempty text or integer key per backing row. Text keys allow at most 254 UTF-16 units because logical leaves add an internal prefix. Keep the ordinary Boolean selection array and all backing arrays aligned. Group identity follows native geometry, parent/level, the exact typed caption value and the exact member-key set. It does not use the displayed caption as a unique key.

The adapter reads one-pointer text/date and nested text groups, including disclosed leaves outside the viewport. It preserves the native blank first leaf column in a one-pointer hierarchy. Group captions are immediate read-only text. Hidden backing rows, formatted text captions and protected captions disable the grouped provider until their unsupported state is removed. Other caption types and lazy branches need further acceptance.

A leaf's selection is its backing row's element in the ordinary selection array, which the provider publishes. A group row has no element of its own, so group rows are unselectable and never reported selected. Selecting a leaf through accessibility uses the keyboard, as a user would. The nearest leaf above it, or below it, is selected without an event, then Up or Down arrows move to it across any group rows between. The list box runs On Selection Change at each row and scrolls the leaf into view. One leaf is selected at a time: a request replaces the selection, and extending it needs the physical Shift key. Omit `selection` and `onSelection`; those options are rejected for this kind. Reveal, editing and header actions remain unavailable, and the provider reports `groupedActionsPending`. Without a controller it also omits disclosure. See [the read-only development gate](../../../tests/GROUPED-OUTLINES.md) for source/package checks, both-mode reading, VoiceOver and unchanged appearance.

For disclosure with matching 0.24.0 packages, add `"setExpanded"; Formula(My_SetExpanded($1))` to the grid options and keep that Formula instance stable. The callback receives exactly `objectName`, one-based `backingRow`, one-based `breakLevel`, Boolean `expanded` and opaque `actionID`. Whitelist the expected owning form and native listbox, require complete arrays and the expected hierarchy, then call nonrecursive `LISTBOX EXPAND` or `LISTBOX COLLAPSE` with `lk break row` and those coordinates. Do not select a row or move focus. The bridge guards semantic identity and calls once; it confirms state and editor preservation after the callback returns. Keep a `ready` Formula false during partial loads or replacement.

Live group rows expose `AXDisclosing`; rows, first cells and virtual disclosure triangles expose `AXPress`. Wait for the completion receipt, then verify application state. Disclosure bypasses ancestor scrolling, including offscreen and fully clipped targets. The native command retains its ordinary effects inside the listbox, including deselection of newly hidden leaves. [The disclosure guide](../../../tests/GROUPED-DISCLOSURE.md) specifies failure behavior, VoiceOver feedback and the repeated/nested acceptance gate. This adds targeted disclosure only; whole-workflow accessibility still requires the remaining interactive controls.

## Classic hierarchical lists

A `list` form object needs no `grids` entry. Discovery publishes it as an outline keyed by item reference, and selection, disclosure and reveal run through 4D's own keyboard handling and list events. Keep item references unique. See [hierarchical lists](../../../tests/HIERARCHICAL-LISTS.md) for behavior, tests and limits.

## Use a collection or entity-selection list box

Keep the lifecycle area and ordinary controls. Configure the actual list box, without copying its rows into accessibility arrays. For example, a collection list box named `Items` has data source `Form.lines`, selected items `Form.selectedLines`, and columns such as `This.description` and `This.amount`:

```4d
$options.grids:=New object("Items"; New object(\
 "kind"; "collection"; "keyProperty"; "lineID"; \
 "selection"; Formula(Form.selectedLines); "label"; "Record rows"))
```

Each object in `Form.lines` must already have a unique, stable `lineID`. Keys can be nonempty Text of at most 254 UTF-16 units or integers from -2,147,483,648 through 2,147,483,647. Text keys are case- and accent-sensitive. Do not use the current row position as a key. Sorting or filtering a collection of those same objects preserves their accessible identities. If any key now refers to a different object, every retained cell in that grid is retired. Reuse existing objects when refreshing their values.

For an entity-selection list box, change the kind and omit `keyProperty` to use its dataclass's primary key:

```4d
$options.grids:=New object("Items"; New object(\
 "kind"; "entity"; "selection"; Formula(Form.selectedLines); \
 "label"; "Record rows"))
```

Here `Form.selectedLines` is the list box's existing selected entity selection. The bridge reads the bound entity selection, discovers the primary-key attribute and loads displayed cell values on demand. Sorting and filtering preserve identities within the same dataclass and datastore. Switching dataclasses retires old cells even when their primary keys match. An optional `keyProperty` selects another stored unique identity attribute. Keep the form's `scope` and the [loading guard](#gate-loading-and-record-changes) when a record change reuses the grid.

The `selection` Formula must return the list box's actual Selected Items expression. If that property is empty, configure it first. For collections, it contains references to the original selected objects. Do not return copied rows or a separately maintained list of keys. 4D 20.8 cannot discover that expression through a public getter. A selectable grid therefore needs this one mapping. A grid whose selection mode is None can omit it. Use `onSelection` only when the application's existing selection controller needs to run, following the [selection callback contract](#reuse-the-existing-selection-controller).

The adapter discovers direct property columns such as `This.description`. Entity columns must be stored text, number, date or Boolean attributes for automatic value reading and editing. Other displayed expressions and custom values can use the [column descriptions](#describe-custom-native-grid-columns). Hidden columns stay hidden, and password-formatted values are not read. Enterable text/number/date cells use the existing native editor and application validation. The bridge never assigns object properties or calls `save()`. 4D performs its normal entity save when editing ends; errors from that save go to the application's existing error handling. Null cells remain read-only. Boolean cells use their native checkbox or popup editor. Editing custom/styled cells and hierarchies still need implementation. Row metadata uses [the metadata configuration](#reuse-row-metadata).

A collection cell containing an object or another unsupported value exposes `Cell description required` and is disabled until it has a text description. The bridge never serializes that object into the accessibility tree. `gridValueDescriptionRequired` appears after a cell is read and resets after a reorder, so an audit must read all pages. Large or remote entity selections remain untested for polling cost; each refresh reads all row keys.

## Use a classic current or named selection

Choose a matching kit that includes this adapter from [availability](STATUS.md#availability). Keep the application's existing pin until that version's acceptance gate passes. Install plugin, component and helpers together.

For an existing current-selection or named-selection list box, add one entry in `AXB_Configure`:

```4d
$options.grids:=New object("Items"; New object(\
 "kind"; "selection"; "label"; "Records"))
```

`Items` is its existing form-object name. Keep its master table or named selection, highlight set, columns, events and methods. The adapter reads the actual source and uses the dataclass's primary key for stable row identity. An optional `keyProperty` names another stored attribute with unique, nonempty Text values of at most 254 UTF-16 units, or whole numbers from -2,147,483,648 through 2,147,483,647. Null, empty, fractional or duplicate keys disable the table. Add `scope` and the [loading guard](#gate-loading-and-record-changes) when the list box shows another parent record's rows or loads them after On Load. Add `onSelection` only when the existing selection controller must refresh dependent UI. Omit `selection`; this kind reads the list box's highlight set. A source without a highlight set offers no selection action. No copied display arrays or form event hook is needed.

The bridge reads ordered physical record numbers and copies the existing highlight set. A private read-only process resolves those numbers into a shared entity selection. Displayed values come from stored fields in the master table, with the original column formats. Accessibility reads preserve the form's current selection, loaded record, unsaved values and `OK`. Actions use the original native list box and editors, so explicit navigation or editing can change record state through the application's normal behavior.

The table needs a datastore mapping and a unique supported identity. Automatic columns cover stored text, number, date and Boolean master-table fields. For calculated expressions, related-table fields, styled cells or other displays, use [column descriptions](#describe-custom-native-grid-columns). The description receives the row's `4D.Entity` as `This` and `$1.item`. Read each value from that entity: `[Table]Field` reads the form's current record rather than the requested row. Pass entity attributes to the existing formatter, for example `Formula(FormatStatus(This.status))`. For a related field, follow its ORDA relation, for example `Formula(String(This.customer.name))`. Keep record loading, selection changes, `SELECTION TO ARRAY`, `SELECTION RANGE TO ARRAY` and `Selection to JSON` out of this callback; the last three unload a modified record. A description provides reading only. An enterable custom column still needs an editor adapter before that screen is fully accessible.

In the fixture, screenshot review confirms that the list box paints saved values while the form's process holds a modified, unsaved record. Automated checks verify the persisted accessibility value and preserve the separate unsaved buffer. Uncommitted transaction records, remote/client-server data, classic grids in child subforms, custom display expressions and additional cell types require their own acceptance tests.

Rows publish after a private read completes. Until then, including briefly after sorting or changing the rows, the table is disabled with `Classic selection is loading` and cell actions are rejected. Retained row identities survive ordinary sorting. A read failure appears in the table label as `Classic selection read failed: <error>: <method>: <line>`; it does not call `onError` or the application's error handler. The next refresh retries. Both loading and read failure produce `gridUnavailable` in coverage diagnostics; read the table label before changing the configuration. The configured label prefixes these messages, for example `Records: Classic selection is loading`.

Each completed read starts another short-lived process and copies the highlight set. Selection feedback arrives after a later read and must fit the existing two-second confirmation deadline. The fixture covers 600 local records; measure larger selections before claiming acceptable performance.

## Gate loading and record changes

Every grid kind uses this guard when rows load after On Load, the loader calls `IDLE`, or the grid shows another parent record's rows. Add `"ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.recordID))` to that grid's options, and order the existing loader:

1. Initialize `linesReady` to false at the start of On Load, before any code that can run the line loader.
2. In the existing loader, set it false before replacing or refreshing arrays, and capture the record ID when loading begins.
3. When the data is complete, store that captured ID in `linesLoadedID`, then set `linesReady` true. If loading finishes asynchronously, carry the captured ID with that load and use it at completion; do not substitute the currently displayed ID.

Change `scope` when the record changes too. Scope alone does not prove which record the arrays contain: changing it alone would publish old rows under the new record identity between switching records and starting the loader. The loaded-ID comparison closes that interval. While readiness is false, the table is disabled and previous cell references stop working. Use a Formula for changing readiness; a literal Boolean stays fixed.

These properties assume existing mutable plain form data. For an entity, class-instance or shared root, keep readiness and loaded-record identity in the application's existing editor state, as in the [record-editor example](examples/RECORD-EDITOR.md#entity-class-and-shared-root-data). Do not add UI attributes to an entity or bypass a shared object's `Use...End use` rules.

In a child grid, each `ready` Formula reads that child's data. A completion delivered to the root with `CALL FORM` has the root's `Form`; update the actual child data captured when the load began, rather than assuming `Form.linesReady` refers to that child. Before marking it ready, verify the current container still owns that data and represents that record. Repeated automatic children sharing a plain business object need distinct per-instance readiness/loaded-ID properties if their loaders differ.

## Give unsaved rows temporary keys

If several new rows have ID `0` until saved, those IDs cannot identify them yet. Assign a UI UUID once when each row is inserted, keep it through editing and saving, and move or delete it with that row in every array operation. Bind this key array to a hidden column so native sorting moves it too. Retire its keys when reloading the display arrays. These keys need no database field and must not replace business IDs. The same rule applies to AreaList: append its hidden key column after the existing columns to preserve their numbers. Never generate new keys during accessibility reads or use a repeated product number instead.

## Describe custom native grid columns

In kits with [stable locators](IDENTIFIERS.md), column metadata can include `automationKey`. It replaces the native column object-name segment, or the AreaList `column.N` segment. Use 1–256 UTF-16 units and a unique key within that grid. An invalid value rejects startup with `invalidGrids`; duplicate keys reject publication. Row keys are also visible in `AXIdentifier`, so use opaque, non-sensitive identities.

The working source accepts column metadata for array, collection, entity-selection and classic-selection grids. AreaList columns use [their own description rules](AREALIST-GRIDS.md#describe-custom-columns). Keep the same grid configuration and add entries only where automatic scalar reading does not describe the visible UI. Keys are existing column object names, not header captions or column positions. Find the column itself in the Form editor; its header has a separate object name. An unknown column name disables the grid and reports `gridUnavailable`.

Some columns require a description before the grid becomes available:

| Grid | Needs `value`, or `decorative: True` for content without meaning or actions |
| --- | --- |
| Array | Picture or Object array columns; multi-style columns. |
| Collection/entity | Expressions other than direct `This.<property>`; multi-style columns. |
| Entity | Attributes other than stored text, number, date or Boolean. |
| Classic selection | Calculated expressions, related-table fields, unsupported master-table fields and multi-style columns. |

Until those descriptions are supplied, the table is disabled and diagnostics report `gridUnavailable`. A direct collection property containing an object is instead reported per requested cell. Other metadata can improve a header or the meaning of a value. For example:

```4d
If ($options.grids.Items.columns=Null)
 $options.grids.Items.columns:=New object
End if
$options.grids.Items.columns.StatusPicture:=New object(\
 "label"; "Status"; "value"; Formula(DescribeLineStatus))
$options.grids.Items.columns.Spacer:=New object("decorative"; True)
```

Here `DescribeLineStatus` is the application's existing formatter, which reads `This` as the collection item or entity. It returns meaningful text such as `Ready to ship`. If the formatter takes an argument instead, use `Formula(DescribeLineStatus($1.item))`. Use the same formatter as the visual UI, passing entity attributes for a classic grid; do not duplicate its business rules in an accessibility adapter. Array grids instead pass the current source row to the existing array formatter, for example `Formula(DescribeArrayLineStatus($1.row))`. Assign this metadata before returning the options.

An array formatter must index arrays that 4D reorders with the list box, including arrays bound to hidden columns. A parallel unbound array keeps its old order after a header sort and describes the wrong line. Bind it to a hidden column, or resolve `$1.key` in the existing application model.

For a grid in an automatic page subform, put the configuration under `options.children.<container>.grids.<listbox>`, including its `columns`. `Form` then refers to that child instance. Invalid child metadata is reported through the root's error callback when the child is first discovered. No child event hook is needed.

The `value` Formula receives one object:

| Field | 4D type and meaning |
| --- | --- |
| `key` | The original Text or Number key from the bound array, row property or classic identity attribute. Numeric keys are whole numbers within the supported range, not necessarily an `Is integer` value. |
| `row` | Number, whole and one-based, in the current key array, collection or entity selection. It changes after sorting/filtering and can be passed to an Integer parameter. |
| `column` | Text. The native column's object name; one formatter can serve several columns. |
| `item` | The original collection object or `4D.Entity`, by reference. Classic grids supply the resolved entity for that record. Undefined for arrays, so `$1.item=Null`. It stays in the host. Do not modify, save or reload it. |

The callback runs on demand in the owning form or child and must return Text without changing UI, selection or data. `This` is the current collection object or entity; array callbacks have no receiver. It can describe a computed expression, picture, object value or styled display. The bridge does not evaluate the column's source string to manufacture a value. Supplying `value` makes that column read-only through accessibility; it does not change the ordinary 4D control. Custom editor support remains separate work. A `label` alone changes the header while retaining supported native editing. An enterable column with a description still needs custom editor support before the screen is fully accessible; coverage reports `gridCellEditingPending` with its column name. An enterable decorative column produces the same diagnostic. Do not use `decorative` to hide an interactive column.

The callback does not run as the cell's form event. `Form event code`, `Self` and `Object current` do not identify that cell. Keep formatting in memory: a page can request up to 128 cells, and values are requested again after changes. Existing methods keep their existing compiler declarations. If adding a new no-argument formatter like the example, declare its Text result in the application's compiler method with `C_TEXT(DescribeLineStatus; $0)`.

Hidden columns are omitted and never invoke the callback. Visibility is read again on every refresh. Password-formatted columns, using the `%password` font, publish no text and never invoke the callback. `decorative: True` omits a column while preserving its physical width, so only use it for content without meaning or actions. Do not supply both `decorative` and `value`.

An invalid configuration returns `invalidGrids` from `start`. This includes a non-Formula `value`, an empty/overlong `label`, and `decorative: True` combined with `value`. A callback returning something other than Text publishes `Cell description required`, disables that cell and adds `gridValueDescriptionRequired` on the next poll. It never serializes the returned object. An empty Text is accepted as an empty cell. Audit every page after a reorder, which clears earlier value diagnostics.

An error raised inside a formatter stops that window's bridge, calls `onError` when configured and records `Form.axbFailure` on plain local data. Normal form behavior remains available. Fix the formatter, then restart in the root context with the complete options from the same configuration method. For an area-owned root, `AXB_Form("start"; newOptions)` retains area teardown ownership.

Configure metadata before `start`; changing it afterwards is not a supported update path. To change a renderer, restart in the root context with the complete new options. An area-owned root retains automatic teardown ownership. A change to the underlying column expression or array binding retires retained cells automatically. Ordinary sorting preserves row identity and calls the formatter with the new row position.

## Reuse row metadata

A native array grid reads its existing LongInt row-control array automatically. It must have one entry per source row. Hidden rows are omitted; other row states follow the rules below. A `meta` option is valid only for collection and entity grids; other kinds return `invalidGrids`. Classic grids do not read per-row disabled or unselectable flags. Their global control and column permissions, native editor validation and selection mode still apply. A classic grid with application-specific row restrictions needs adapter work before its full behavior is accessible. Collection/entity grids can also use the existing Meta Info Expression. A direct `This.<property>` expression, such as `This.meta`, needs no additional configuration. For a method or other expression, pass one Formula that calls the same application code:

```4d
// The list box's existing Meta Info Expression is RowMeta.
$options.grids.Items.meta:=Formula(RowMeta)
```

Keep this in the same grid options as `selection` and `columns`. For a child grid, put it under `options.children.<container>.grids.<listbox>`. Configure it before starting discovery. The Formula runs with the original collection object/entity as `This` and the owning form as `Form`. It receives one optional argument with `key`, one-based source `row`, and original `item`, using the same types as the column-description table above. Reuse the existing renderer's `disabled` and `unselectable` decisions; do not maintain a second set of permissions.

If the existing method takes an item parameter, use `Formula(RowMeta($1.item))`. An existing item method can use `Formula(This.rowMetadata())`. The request has no `column` property. Existing methods keep their compiler declarations; a new object-returning method needs `C_OBJECT(MethodName; $0)` plus declarations for its parameters. The callback runs outside a native cell event: `Self`, `Object current` and `Form event code` do not identify its row.

Return the existing metadata object or Null. A Null object, an absent flag, or a Null flag means no additional restriction. Other defined `disabled` and `unselectable` values must be Boolean. Cell-level versions of those flags are ignored, matching 4D. Formatting properties do not change accessibility permission. A color that communicates business meaning still needs a text value or description.

Disabled rows remain readable and selectable, matching native 4D, while their cells cannot be edited. `unselectable` independently prevents adding a row to the selection. A selection change can retain a previously selected row that later became restricted, or remove it. Unselectable rows cannot be highlighted; their text editor remains available when 4D's Single-Click Edit option is enabled. With selection mode None, 4D ignores the unselectable flag. Normal editors, validation and confirmation still decide whether an operation completes. Without Single-Click Edit, an unselectable row is also not editable. New restrictions apply to retained cells at the next refresh. A lifted restriction applies when that cell's value page reloads, without changing record identity.

An arbitrary native Meta Info Expression without a `meta` Formula leaves the grid unavailable and names the missing mapping. Invalid return types also produce `gridUnavailable`; a thrown callback stops that window's bridge, calls `onError` and records `Form.axbFailure` on plain local data. Keep metadata formatting fast and free of business mutations. It runs for every row on each refresh and action-confirmation pass, unlike lazy cell descriptions. Entity selections therefore load every entity. A stored `This.<property>` avoids the Formula calls but still reads every row. Remote entity performance remains unvalidated. The custom mapping records the native expression when the visible grid is first discovered, including while it is loading. After replacing that expression, restart in the root context with complete options containing the matching Formula. A Formula configured with no native Meta Info Expression reports `gridUnavailable`. Switching between direct `This.<property>` sources is automatic and retires retained cells.

The matching native build requires the `rowStates 1` capability. Array, collection, entity, stored-property, child-form and lifecycle/error cases have [isolated live validation](VALIDATION.md).

## Reuse the existing selection controller

Programmatic row selection does not run the list box's ordinary object method. If that method refreshes dependent UI, put that work in one shared application method and call it from both the existing selection event and `onSelection`. The callback receives no arguments and runs later in the owning form. Event-dependent values such as `Form event code`, `Self` and `Object current` do not identify a user selection event there. Read the actual selection binding. Do not open another window from this refresh callback; completion requires the original form window to remain frontmost.

Keyboard focus may still belong to a search field or another grid. Pass the grid's object name to a controller that needs it, for example `Formula(RefreshCategory("Categories"))`. Carry that name through the called methods instead of rediscovering it with `Object with focus`. Test selection after editing another field as well as immediately after opening the form.

For automatic native grids, the bridge changes the native selection, waits for the binding, and calls `onSelection` once. It checks the binding again, reveals the last selected row, and confirms completion. A handler that changes the selection produces a rejected result without replay. Confirmation has a two-second deadline, so a slow handler can already have run when the bridge reports rejection. A rejected request does not imply rollback. AreaList uses its own selection readback path. The older explicit [summary recipe](examples/LISTBOX-FORM.md) has a separate confirmation contract.

## Native checkbox and popup cells

The native grid adapter discovers Boolean checkboxes, numeric three-state checkboxes and Boolean popup columns. Keep the existing `grids` configuration and column methods. No additional callback is required. Build the packages and install the helpers from the same commit; automatic startup checks the native `gridControls 1` capability.

The column must be enterable to offer editing. Bind it to a Boolean array, a direct `This.<property>` Boolean in a collection, a stored Boolean entity attribute or a stored Boolean master-table field in a classic grid. Numeric bindings displayed as three-state checkboxes use the same path. Do not add a `columns.<name>.value` description to an operable checkbox or popup. It replaces the widget with read-only text and reports `gridCellEditingPending` for an enterable column. `decorative` omits the column. A Boolean checkbox's native caption supplies its spoken name and takes precedence over a label override. Change a misleading caption in the form definition. `columns.<name>.label` renames the header and is the fallback when that caption is empty. Numeric checkboxes use the column label: 4D 20.8's public getters return the numeric format instead of their caption. If a numeric checkbox has a meaningful visible caption, include it in `columns.<name>.label`, for example `New object("label"; "Reviewed")`.

A checkbox exposes unchecked, checked or mixed state. A Boolean popup exposes its selected label and uses its column label as its name. Give both popup choices meaningful labels in the form's True/False text properties. These widgets do not accept text assignment.

| Request | Existing native behavior | Completion means |
| --- | --- | --- |
| Press a checkbox | Reveal, then one click on its indicator. Normal entry, selection and data-change handlers run. | The state changed and remained changed after the handlers returned. |
| Press a Boolean popup | Reveal, then one click opens 4D's actual menu. | The menu is open. The receipt arrives while it is still showing; it does not confirm a choice. Choose a native item or press Escape, then read the cell value. |
| Focus either widget | `EDIT ITEM` invokes On Before Data Entry. In the live 4D 20.8 fixture, focus followed by blur selects the row without a data-change event. | The cell has keyboard focus. The bridge does not toggle its value during focus; an application entry handler may change it. |

VoiceOver configured to move keyboard focus can invoke entry handling as it visits cells. To refuse entry, return `$0:=-1` from the existing On Before Data Entry handler. Moving focus alone does not reject a native click.

The dispatcher checks the cell, value, permissions, window and hit region before sending input. An unchanged checkbox is rejected after the action deadline, whether validation refused entry or the click had no effect. A scope change retires the cell reference and rejects its receipt, but does not cancel a native click already in progress. A rejected receipt does not guarantee rollback. Read the current cell state before deciding whether another action is appropriate.

Negative numeric checkbox states follow 4D: `-1` is blank, and `-2`, `-3` and `-4` are disabled unchecked, checked and mixed states. Disabled cells stay readable. Other negative values report `gridValueDescriptionRequired`; correct the stored state rather than adding a text description to an interactive checkbox. Values above `2` are mixed. Null cells are blank and read-only. Existing row restrictions and Single-Click Edit settings govern whether the native editor is available. A semicolon in a checkbox caption does not make it a popup; discovery also reads the column's native display type.

This adapter covers native flat list boxes. [AreaList checkboxes](AREALIST-GRIDS.md#checkbox-cells) use the vendor's own entry path. [Validation scope](VALIDATION.md) distinguishes historical coverage from checks still owed in a new host.

## Add an AreaList grid to the same form

Moved to [AreaList grids](AREALIST-GRIDS.md): live preflight, configuration, custom columns, editing, repeated child grids and limits.

### AreaList checkbox cells

See [AreaList checkbox cells](AREALIST-GRIDS.md#checkbox-cells).

## Configure a record editor with editable grids

See the [record-editor example](examples/RECORD-EDITOR.md).

### Entity, class and shared root data

See [entity, class and shared root data](examples/RECORD-EDITOR.md#entity-class-and-shared-root-data).
