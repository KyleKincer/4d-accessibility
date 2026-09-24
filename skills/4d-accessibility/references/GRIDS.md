# Configure data grids

Install the matching packages and use the root [start/stop and error-reporting hooks](INTEGRATION.md#2-connect-one-form) first. Add only the configuration for your binding family. Ordinary controls remain automatically discovered.

## Add a native array list box without replacing discovery

Keep the same start/stop integration. Add the list box's object name and its stable row-key column to the start options:

```4d
$options:=New object("label"; "Invoice"; "scope"; Formula(String(Form.invoiceID)); \
 "onError"; Formula(ReportAccessibilityFailure($1)))
$options.grids:=New object("Items"; New object(\
 "kind"; "array"; "keyColumn"; "LineID"; "label"; "Invoice lines"))
$bridge:=AXB_Form("start"; $options)
```

`Items` is the list box's form-object name. `LineID` is a column bound to the existing Text, Integer or LongInt identity array, with one unique key per source row. Text keys must be nonempty and at most 256 UTF-16 units. Negative integer keys and zero are valid. The column can be hidden. Use a line-record ID, not the displayed row position or a product number that can repeat. The scope changes when the form changes records. All ordinary controls and automatic child forms remain part of the tree because these options omit `describe` and `apply`.

The list box's own variable must be its Boolean selection array, with the same row count as the key array. Keep numeric IDs in their original array. The bridge converts them to Text only for accessibility identity; callbacks receive the original numeric key. No parallel identity array is needed. Real-array keys are unsupported.

If rows load after On Load or the loader calls `IDLE`, add `"ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.invoiceID))` to the grid options. Initialize `linesReady` to false at the start of On Load, before any code that can run the line loader. In the existing loader, set it false before touching arrays and capture the record ID when loading begins. When the arrays are complete, store that captured ID in `linesLoadedID`, then set `linesReady` true. The ID comparison also closes the interval between switching records and starting the loader. Changing `scope` alone would publish old rows under the new record identity during that interval. While false, the table is disabled and previous cell references stop working. Use a Formula for changing readiness; a literal Boolean stays fixed.

The provider discovers the displayed columns, reads their existing scalar formats, and exposes every non-hidden row. Cell values load as accessibility tools request them. It retains keyed cell identities after sorting, scrolls through the native control, and uses the existing editor for supported enterable cells. It does not assign backing arrays during text entry. A completed text action means the text reached the editor; normal validation and commit still happen when editing ends. Keystroke filters can reject the action.

If selection needs the application's existing dependent-UI refresh, add `"onSelection"; Formula(YourExistingSelectionHandler)`. See the [selection callback contract](#reuse-the-existing-selection-controller).

The validated fixture covers flat array list boxes with scalar text, number, date, time or Boolean values and VoiceOver navigation through all logical rows. [Column descriptions](#describe-custom-native-grid-columns) make picture and object-array displays readable. Native checkbox and Boolean popup cells use the existing control path described below. Hierarchical/custom cell editing and cold-cache announcements remain required work.

## Use a collection or entity-selection list box

Use the same start/stop calls and ordinary controls. Configure the actual list box, without copying its rows into accessibility arrays. For example, a collection list box named `Items` has data source `Form.lines`, selected items `Form.selectedLines`, and columns such as `This.description` and `This.amount`:

```4d
$options.grids:=New object("Items"; New object(\
 "kind"; "collection"; "keyProperty"; "lineID"; \
 "selection"; Formula(Form.selectedLines); "label"; "Invoice lines"))
```

Each object in `Form.lines` must already have a unique, stable `lineID`. Keys can be nonempty Text of at most 254 UTF-16 units or integers from -2,147,483,648 through 2,147,483,647. Text keys are case- and accent-sensitive. Do not use the current row position as a key. Sorting or filtering a collection of those same objects preserves their accessible identities. If any key now refers to a different object, every retained cell in that grid is retired. Reuse existing objects when refreshing their values.

For an entity-selection list box, change the kind and omit `keyProperty` to use its dataclass's primary key:

```4d
$options.grids:=New object("Items"; New object(\
 "kind"; "entity"; "selection"; Formula(Form.selectedLines); \
 "label"; "Invoice lines"))
```

Here `Form.selectedLines` is the list box's existing selected entity selection. The bridge reads the bound entity selection, discovers the primary-key attribute and loads displayed cell values on demand. Sorting and filtering preserve identities within the same dataclass and datastore. Switching dataclasses retires old cells even when their primary keys match. An optional `keyProperty` selects another stored unique identity attribute. Keep the form's `scope` and loading `ready` guard from the array example when a record change reuses the grid.

The `selection` Formula must return the list box's actual Selected Items expression. If that property is empty, configure it first. For collections, it contains references to the original selected objects. Do not return copied rows or a separately maintained list of keys. 4D 20.8 cannot discover that expression through a public getter. A selectable grid therefore needs this one mapping. A grid whose selection mode is None can omit it. Use `onSelection` only when the application's existing selection controller needs to run, following the [selection callback contract](#reuse-the-existing-selection-controller).

The adapter discovers direct property columns such as `This.description`. Entity columns must be stored text, number, date or Boolean attributes for automatic value reading and editing. Other displayed expressions and custom values can use the descriptions below. Hidden columns stay hidden, and password-formatted values are not read. Enterable text/number/date cells use the existing native editor and application validation. The bridge never assigns object properties or calls `save()`. 4D performs its normal entity save when editing ends; errors from that save go to the application's existing error handling. Null cells remain read-only. Boolean cells use their native checkbox or popup editor. Editing custom/styled cells and hierarchies still need implementation. Row metadata uses the configuration below.

A collection cell containing an object or another unsupported value exposes `Cell description required` and is disabled until it has a text description. The bridge never serializes that object into the accessibility tree. `gridValueDescriptionRequired` appears after a cell is read and resets after a reorder, so an audit must read all pages. Large or remote entity selections remain untested for polling cost; each refresh reads all row keys.

## Describe custom native grid columns

The working source accepts column metadata for array, collection and entity-selection grids. Keep the same grid configuration and add entries only where automatic scalar reading does not describe the visible UI. Keys are existing column object names, not header captions or column positions. Find the column itself in the Form editor; its header has a separate object name. An unknown column name disables the grid and reports `gridUnavailable`.

Some columns require a description before the grid becomes available:

| Grid | Needs `value`, or `decorative: True` for content without meaning or actions |
| --- | --- |
| Array | Picture or Object array columns; multi-style columns. |
| Collection/entity | Expressions other than direct `This.<property>`; multi-style columns. |
| Entity | Attributes other than stored text, number, date or Boolean. |

Until those descriptions are supplied, the table is disabled and diagnostics report `gridUnavailable`. A direct collection property containing an object is instead reported per requested cell. Other metadata can improve a header or the meaning of a value. For example:

```4d
If ($options.grids.Items.columns=Null)
 $options.grids.Items.columns:=New object
End if
$options.grids.Items.columns.StatusPicture:=New object(\
 "label"; "Status"; "value"; Formula(DescribeLineStatus))
$options.grids.Items.columns.Spacer:=New object("decorative"; True)
```

Here `DescribeLineStatus` is the application's existing formatter, which reads `This` as the collection item or entity. It returns meaningful text such as `Ready to ship`. If the formatter takes an argument instead, use `Formula(DescribeLineStatus($1.item))`. Use the same formatter as the visual UI; do not duplicate its business rules in an accessibility adapter. Array grids instead pass the current source row to the existing array formatter, for example `Formula(DescribeArrayLineStatus($1.row))`. Assign the metadata before `AXB_Form("start"; $options)`.

An array formatter must index arrays that 4D reorders with the list box, including arrays bound to hidden columns. A parallel unbound array keeps its old order after a header sort and describes the wrong line. Bind it to a hidden column, or resolve `$1.key` in the existing application model.

For a grid in an automatic page subform, put the configuration under `options.children.<container>.grids.<listbox>`, including its `columns`. `Form` then refers to that child instance. Invalid child metadata is reported through the root's error callback when the child is first discovered. No child event hook is needed.

The `value` Formula receives one object:

| Field | 4D type and meaning |
| --- | --- |
| `key` | The original Text or Number key from the bound array or row property. Numeric keys are whole numbers within the supported range, not necessarily an `Is integer` value. |
| `row` | Number, whole and one-based, in the current key array, collection or entity selection. It changes after sorting/filtering and can be passed to an Integer parameter. |
| `column` | Text. The native column's object name; one formatter can serve several columns. |
| `item` | The original collection object or `4D.Entity`, by reference. Undefined for arrays, so `$1.item=Null`. It stays in the host. Do not modify, save or reload it. |

The callback runs on demand in the owning form or child and must return Text without changing UI, selection or data. `This` is the current collection object or entity; array callbacks have no receiver. It can describe a computed expression, picture, object value or styled display. The bridge does not evaluate the column's source string to manufacture a value. Supplying `value` makes that column read-only through accessibility; it does not change the ordinary 4D control. Custom editor support remains separate work. A `label` alone changes the header while retaining supported native editing. An enterable column with a description still needs custom editor support before the screen is fully accessible; coverage reports `gridCellEditingPending` with its column name. An enterable decorative column produces the same diagnostic. Do not use `decorative` to hide an interactive column.

The callback does not run as the cell's form event. `Form event code`, `Self` and `Object current` do not identify that cell. Keep formatting in memory: a page can request up to 128 cells, and values are requested again after changes. Existing methods keep their existing compiler declarations. If adding a new no-argument formatter like the example, declare its Text result in the application's compiler method with `C_TEXT(DescribeLineStatus; $0)`.

Hidden columns are omitted and never invoke the callback. Visibility is read again on every refresh. Password-formatted columns, using the `%password` font, publish no text and never invoke the callback. `decorative: True` omits a column while preserving its physical width, so only use it for content without meaning or actions. Do not supply both `decorative` and `value`.

An invalid configuration returns `invalidGrids` from `start`. This includes a non-Formula `value`, an empty/overlong `label`, and `decorative: True` combined with `value`. A callback returning something other than Text publishes `Cell description required`, disables that cell and adds `gridValueDescriptionRequired` on the next poll. It never serializes the returned object. An empty Text is accepted as an empty cell. Audit every page after a reorder, which clears earlier value diagnostics.

An error raised inside a formatter stops that window's bridge, calls `onError` when configured and records `Form.axbFailure` on plain local data. Normal form behavior remains available. Fix the formatter and start the bridge again.

Configure metadata before `start`; changing it afterwards is not a supported update path. To change a renderer, stop and restart with the new options. A change to the underlying column expression or array binding retires retained cells automatically. Ordinary sorting preserves row identity and calls the formatter with the new row position.

## Reuse row metadata

A native array grid reads its existing LongInt row-control array automatically. It must have one entry per source row. Hidden rows are omitted; other row states follow the rules below. A `meta` option is invalid for array and AreaList grids. Collection/entity grids can also use the existing Meta Info Expression. A direct `This.<property>` expression, such as `This.meta`, needs no additional configuration. For a method or other expression, pass one Formula that calls the same application code:

```4d
// The list box's existing Meta Info Expression is InvoiceLineMeta.
$options.grids.Items.meta:=Formula(InvoiceLineMeta)
```

Keep this in the same grid options as `selection` and `columns`. For a child grid, put it under `options.children.<container>.grids.<listbox>`. Configure it before starting discovery. The Formula runs with the original collection object/entity as `This` and the owning form as `Form`. It receives one optional argument with `key`, one-based source `row`, and original `item`, using the same types as the column-description table above. Reuse the existing renderer's `disabled` and `unselectable` decisions; do not maintain a second set of permissions.

If the existing method takes an item parameter, use `Formula(InvoiceLineMeta($1.item))`. An existing item method can use `Formula(This.rowMetadata())`. The request has no `column` property. Existing methods keep their compiler declarations; a new object-returning method needs `C_OBJECT(MethodName; $0)` plus declarations for its parameters. The callback runs outside a native cell event: `Self`, `Object current` and `Form event code` do not identify its row.

Return the existing metadata object or Null. A Null object, an absent flag, or a Null flag means no additional restriction. Other defined `disabled` and `unselectable` values must be Boolean. Cell-level versions of those flags are ignored, matching 4D. Formatting properties do not change accessibility permission. A color that communicates business meaning still needs a text value or description.

Disabled rows remain readable and selectable, matching native 4D, while their cells cannot be edited. `unselectable` independently prevents adding a row to the selection. A selection change can retain a previously selected row that later became restricted, or remove it. Unselectable rows cannot be highlighted; their text editor remains available when 4D's Single-Click Edit option is enabled. With selection mode None, 4D ignores the unselectable flag. Normal editors, validation and confirmation still decide whether an operation completes. Without Single-Click Edit, an unselectable row is also not editable. New restrictions apply to retained cells at the next refresh. A lifted restriction applies when that cell's value page reloads, without changing record identity.

An arbitrary native Meta Info Expression without a `meta` Formula leaves the grid unavailable and names the missing mapping. Invalid return types also produce `gridUnavailable`; a thrown callback stops that window's bridge, calls `onError` and records `Form.axbFailure` on plain local data. Keep metadata formatting fast and free of business mutations. It runs for every row on each refresh and action-confirmation pass, unlike lazy cell descriptions. Entity selections therefore load every entity. A stored `This.<property>` avoids the Formula calls but still reads every row. Remote entity performance remains unvalidated. The custom mapping records the native expression when the visible grid is first discovered, including while it is loading. After replacing that expression, stop and restart discovery with the matching Formula. A Formula configured with no native Meta Info Expression reports `gridUnavailable`. Switching between direct `This.<property>` sources is automatic and retires retained cells.

The matching native build requires the `rowStates 1` capability. Array, collection, entity, stored-property, child-form and lifecycle/error cases have [isolated live validation](VALIDATION.md).

## Reuse the existing selection controller

Programmatic row selection does not run the list box's ordinary object method. If that method refreshes dependent UI, put that work in one shared application method and call it from both the existing selection event and `onSelection`. The callback receives no arguments and runs later in the owning form. Event-dependent values such as `Form event code`, `Self` and `Object current` do not identify a user selection event there. Read the actual selection binding. Do not open another window from this refresh callback; completion requires the original form window to remain frontmost.

For automatic native grids, the bridge changes the native selection, waits for the binding, and calls `onSelection` once. It checks the binding again, reveals the last selected row, and confirms completion. A handler that changes the selection produces a rejected result without replay. Confirmation has a two-second deadline, so a slow handler can already have run when the bridge reports rejection. A rejected request does not imply rollback. AreaList uses its own selection readback path. The older explicit summary recipe below has a separate confirmation contract.

## Native checkbox and popup cells

The native grid adapter discovers Boolean checkboxes, numeric three-state checkboxes and Boolean popup columns. Keep the existing `grids` configuration and column methods. No additional callback is required. Build the packages and install the helpers from the same commit; automatic startup checks the native `gridControls 1` capability.

The column must be enterable to offer editing. Bind it to a Boolean array, a direct `This.<property>` Boolean in a collection, or a stored Boolean entity attribute. Numeric bindings displayed as three-state checkboxes use the same path. Do not add a `columns.<name>.value` description to an operable checkbox or popup. It replaces the widget with read-only text and reports `gridCellEditingPending` for an enterable column. `decorative` omits the column. A Boolean checkbox's native caption supplies its spoken name and takes precedence over a label override. Change a misleading caption in the form definition. `columns.<name>.label` renames the header and is the fallback when that caption is empty. Numeric checkboxes use the column label: 4D 20.8's public getters return the numeric format instead of their caption. If a numeric checkbox has a meaningful visible caption, include it in `columns.<name>.label`, for example `New object("label"; "Reviewed")`.

A checkbox exposes unchecked, checked or mixed state. A Boolean popup exposes its selected label and uses its column label as its name. Give both popup choices meaningful labels in the form's True/False text properties. These widgets do not accept text assignment.

| Request | Existing native behavior | Completion means |
| --- | --- | --- |
| Press a checkbox | Reveal, then one click on its indicator. Normal entry, selection and data-change handlers run. | The state changed and remained changed after the handlers returned. |
| Press a Boolean popup | Reveal, then one click opens 4D's actual menu. | The menu is open. The receipt arrives while it is still showing; it does not confirm a choice. Choose a native item or press Escape, then read the cell value. |
| Focus either widget | `EDIT ITEM` invokes On Before Data Entry. In the live 4D 20.8 fixture, focus followed by blur selects the row without a data-change event. | The cell has keyboard focus. The bridge does not toggle its value during focus; an application entry handler may change it. |

VoiceOver configured to move keyboard focus can invoke entry handling as it visits cells. To refuse entry, return `$0:=-1` from the existing On Before Data Entry handler. Moving focus alone does not reject a native click.

The dispatcher checks the cell, value, permissions, window and hit region before sending input. An unchanged checkbox is rejected after the action deadline, whether validation refused entry or the click had no effect. A scope change retires the cell reference and rejects its receipt, but does not cancel a native click already in progress. A rejected receipt does not guarantee rollback. Read the current cell state before deciding whether another action is appropriate.

Negative numeric checkbox states follow 4D: `-1` is blank, and `-2`, `-3` and `-4` are disabled unchecked, checked and mixed states. Disabled cells stay readable. Other negative values report `gridValueDescriptionRequired`; correct the stored state rather than adding a text description to an interactive checkbox. Values above `2` are mixed. Null cells are blank and read-only. Existing row restrictions and Single-Click Edit settings govern whether the native editor is available. A semicolon in a checkbox caption does not make it a popup; discovery also reads the column's native display type.

This adapter covers native flat list boxes. [AreaList checkboxes](#arealist-checkbox-cells) use the vendor's own entry path. [Validation scope](VALIDATION.md) distinguishes historical coverage from checks still owed in a new host.

## Add an AreaList grid to the same form

Install AreaList Pro and the host helpers with `--area-list`. The current fixtures use AreaList Pro 11.4.2. Before changing configuration, inspect the live layout. The current adapter requires flat array-backed data, row selection, normal vendor array sorting, no transposition or multi-row layout, and unique Text, Integer or LongInt keys in one bound column. Read `ALP_Area_Transposed=0`, `ALP_Area_SelType=0`, `ALP_Area_RowsInGrid=1`, `ALP_Area_DontSortArrays=0` and `ALP_Area_AutoHierarchy=0` with the vendor getters. `AL_GetObjects2` for `ALP_Object_Hierarchy` must report no hierarchy levels. A custom sort callback is compatible only if it preserves these conditions and sorts the bound arrays together. Preserve the application's semantics; an incompatible layout requires adapter work, not a silent change to vendor flags.

If an existing supported identity array is not bound to a column, append it as a hidden column only after checking every sort, insert and delete path keeps it aligned with the other arrays. Preserve existing physical column numbers. Real-array keys and other unsupported bindings require adapter work. Prefer extending the canonical adapter over adding a parallel Text identity array. Unsaved rows need stable application-owned temporary identities. Validate selection, sorting and editing through the actual application paths.

Use the existing Text, Integer or LongInt identity array. Integer IDs are normalized to Text only in the accessibility descriptor; the bound array stays numeric. Real arrays are not accepted as keys. Empty Text keys and duplicate identities disable the grid.

Identify the area's existing compatible key array:

```4d
$options:=New object("label"; "Invoice"; "scope"; Formula(String(Form.invoiceID)); \
 "onError"; Formula(ReportAccessibilityFailure($1)))
$lines:=New object("kind"; "areaList"; "label"; "Invoice lines"; \
 "keys"; ->aLineID; "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.invoiceID)))
$options.grids:=New object("Items"; $lines)
$bridge:=AXB_Form("start"; $options)
```

`Items` is the form object's name. The provider finds the key array in the area's actual column bindings; it must occur exactly once. An optional `keyColumn` asserts a particular physical column if your application needs that additional check. Initialize `Form.linesReady` to false at the start of On Load, before any line loading. In the existing loader, clear readiness and capture the invoice ID before replacing or refreshing arrays. When that load completes, store its captured ID in `Form.linesLoadedID` before setting readiness true. The formula checks that loaded ID against the displayed invoice, including any delay before loading begins. Change the scope when the record changes; scope alone does not prove which record the arrays contain. The provider reads current vendor bindings and formatting, exposes every non-hidden row and displayed column, and resolves retained cells by their keys after sorting. The other fields and buttons remain automatically discovered.

Scalar text, numeric, date, time and Boolean columns need no description configuration. Boolean values are currently read-only through accessibility, even if the vendor UI permits toggling. Every displayed picture or custom column requires a text description or an explicit decorative declaration; otherwise the grid is disabled with a “needs a text description” label. Add metadata only where the existing UI does not describe its meaning. For example, an image indicator and a decorative spacer:

```4d
// Set this before AXB_Form("start"; $options).
$lines.columns:=New object(\
 "5"; New object("label"; "Visibility"; \
  "value"; Formula(Choose(AXB_PictureEquals(apictVisibility{$1.row}; <>hiddenPict); "Hidden item"; "Visible item"))); \
 "6"; New object("decorative"; True))
```

Here `apictVisibility` is the picture array bound to that column, and `<>hiddenPict` is the application's existing hidden-item icon. Use your application's actual array/icon names, or resolve `$1.key` in its existing model.

Column keys are actual runtime vendor column numbers as Text, independent of display order. An unconfigured custom column disables the table with a label such as `column 5 needs a text description`; read that label through AX to identify the physical column. Confirm its live binding before supplying metadata: legacy setup can omit an empty column and shift later bindings. Never mark an assumed spacer decorative; it may now contain data. Verify this with the vendor's live binding getters before writing column metadata. A `label` overrides the header. A `value` formula provides readable text for a picture or another custom display; it receives `{key, row, column}` in `$1` and runs inside the owning form when a cell page is requested. Read the existing UI model, without querying, saving, or changing selection. A row-based formula must read an array that AreaList sorts together with the grid, or resolve `$1.key` in the model. An unbound parallel array can describe the wrong row after sorting. Custom descriptions are read-only. A decorative column is omitted from the tree while retaining its width for neighboring cells. Hidden and password-formatted cells never call the value formula or publish their contents. Attributed text is published without its formatting markup.

Text entry uses the existing vendor editor and its entry/exit callbacks. Normal Undo, Redo and validation remain responsible for the edit. Add `onSelection` only if the application's ordinary selection path needs an existing shared refresh handler; do not call a general click handler that also opens records or runs business commands.

For a grid inside an automatic subform, put this same grid configuration under `options.children.LineDetails.grids`. The root owns registration; the child needs no bridge method. Give each repeated instance its own area variable, every bound array, key-array pointer and record scope. Leave the plugin object’s Variable blank for an instance-local area. Sharing only the key array separately is insufficient.

For example, independently changing records in repeated children can use:

```4d
// Root context. These are separate, existing process arrays bound in each area.
// The other bound arrays must also belong to their respective instance.
$leftLines:=New object("kind"; "areaList"; "label"; "Pending lines"; "keys"; ->aLeftLineID; \
 "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.invoiceID)))
$rightLines:=New object("kind"; "areaList"; "label"; "Posted lines"; "keys"; ->aRightLineID; \
 "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.invoiceID)))
$options.children:=New object
$options.children.Left:=New object("label"; "Pending invoice"; "scope"; Formula(String(Form.invoiceID)); "grids"; New object("Items"; $leftLines))
$options.children.Right:=New object("label"; "Posted invoice"; "scope"; Formula(String(Form.invoiceID)); "grids"; New object("Items"; $rightLines))
```

Each grid's `ready` Formula reads that child's data. A completion delivered to the root with `CALL FORM` has the root's `Form`; update the actual child data captured when the load began, rather than assuming `Form.linesReady` refers to that child. Carry the captured record ID with the load. Before marking it ready, verify the current container still owns that data and represents that record. Repeated automatic children sharing a plain business object need distinct per-instance readiness/loaded-ID properties if their loaders differ. Separate AreaList areas and bound arrays remain required for independent grid contents.

The current flat-grid adapter requires row selection mode, a non-transposed single-row layout, no hierarchy, and permission for AreaList to sort its bound arrays. All bound arrays must match the row count. The key array must contain unique Text, Integer or LongInt identities. Text keys must be nonempty and at most 256 UTF-16 units. An incompatible layout appears as a disabled table. Layout failures share a generic label; read the vendor properties listed above to identify the failed requirement. For `areaList`, optional `keyColumn` is a physical number; for native `array`, it is the form-object name of the key column.

AreaList flat row selection and ordinary text editing work in isolated fixtures. Supplementary Unicode is rejected before opening or changing an editor. AreaList Pro 11.4.2 corrupts memory while reading, copying or committing long supplementary text even without this bridge; the 11.4.3b5 preview also fails. The guard protects bridge requests, not the vendor's direct-input path. See the [reproduction](https://github.com/KyleKincer/4d-accessibility/blob/main/tests/AREA-LIST-UNICODE.md).

Protected-cell editing, vendor popup/radio interaction, hierarchical and multiline layouts, and complete assistive-technology validation remain open. These are implementation gaps, not the final accessibility contract.

### AreaList checkbox cells

Keep the same grid configuration. Boolean columns displayed as checkboxes and Integer/LongInt columns configured as two- or three-state checkboxes are discovered automatically. The column header supplies the label; use `columns.<number>.label` when it needs clarification. Leave `value` descriptions off interactive checkboxes, since a description replaces the control with read-only text.

The adapter preserves the column's `ALP_Column_FocusableCheckbox` setting. For a non-focusable checkbox, AXPress uses AreaList's normal cell-entry command, which toggles the value and runs the existing entry/exit callbacks. AXFocused is unavailable because that vendor command would also toggle the value. For a focusable checkbox, AXFocused opens the editor without changing the value, and AXPress sends Space to that editor. Its uncommitted value appears in AX; normal Escape and focus transfer retain the vendor's cancel, commit and validation behavior. A completed press confirms the displayed checkbox state, not a database save.

Area, column and cell entry permissions remain authoritative. Hidden and password-formatted cells publish no state. A validation callback that restores the previous value produces a rejected action receipt; the adapter does not retry it. Sorting follows stable row keys, and a loading or scope transition retires old controls.

Install matching plugin, component and host helpers. Startup requires `cellFocus 1` so an older plugin cannot advertise a focus operation on a control that activates immediately. The synthetic fixture exercises normal, small and mini checkbox display modes. Formatted Boolean editors, vendor radio/popup choices and custom-picture checkbox rendering need separate validation or implementation.

## Put the invoice-like form together

For a native list box, use the array, collection or entity grid options above in place of the AreaList `$lines` configuration. Keep the same scope, readiness and loader ordering.

This example uses existing mutable plain form data. Keep readiness and loaded-record identity in the application's existing UI state when the root is an entity, class instance or shared object; map the formulas to that state without adding entity attributes. Use this ordering in the existing form method and line loader. Initialization must precede the first load, including when that loader runs inside On Load.

```4d
// Form method: start of On Load, before existing initialization can load lines.
Form.linesReady:=False

// Existing line loader: before changing arrays or starting asynchronous work.
// Match this declaration to the actual record ID type. This example uses Integer.
var $loadingInvoiceID : Integer
Form.linesReady:=False
$loadingInvoiceID:=Form.invoiceID
// Existing code loads this invoice's arrays.
// When that work finishes, record the ID the data actually belongs to:
Form.linesLoadedID:=$loadingInvoiceID
Form.linesReady:=True

// Form method: end of On Load, after its existing initialization.
var $options; $lines; $bridge : Object
$options:=New object("label"; "Invoice"; "scope"; Formula(String(Form.invoiceID)); \
 "onError"; Formula(ReportAccessibilityFailure($1)))
$lines:=New object("kind"; "areaList"; "label"; "Invoice lines"; \
 "keys"; ->aLineID; "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.invoiceID)))
$options.grids:=New object("Items"; $lines)
$bridge:=AXB_Form("start"; $options)
If (Not($bridge.ok=True) & ($bridge.error#"dependencyUnavailable"))
 ReportAccessibilityFailure($bridge)
End if

// Form method: On Unload and existing fatal form-error cleanup.
$bridge:=AXB_Form("stop"; New object)
```

If loading finishes asynchronously, retain its captured invoice ID with that load and use it at completion. Do not substitute the currently displayed ID. Add the picture/custom-column descriptions shown above to `$lines.columns`. If selection needs a dependent-UI refresh, set `$lines.onSelection` to the existing shared selection handler before starting.

Fields, buttons and page subforms remain automatically discovered. Save, return and print keep their existing buttons, menus and business handlers. There is no accessibility-specific copy of those operations.
