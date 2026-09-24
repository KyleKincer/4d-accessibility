# Native list-box reading and selection

For collection/entity row metadata, use automatic `options.grids` and [reuse the existing metadata expression](../INTEGRATION.md#reuse-row-metadata). The summary adapter described here still rejects those expressions.

This is the older explicit summary adapter. For new integrations, use [automatic discovery with a complete logical grid](../INTEGRATION.md#add-a-native-array-list-box-without-replacing-discovery), including the [collection/entity option](../INTEGRATION.md#use-a-collection-or-entity-selection-list-box). It exposes every logical row and keeps ordinary fields in the same tree.

The recipe below remains available for existing integrations. The host installer includes its helpers by default. `AXB_Listbox` validates stable keys and describes visible rows; `AXB_ListboxSelect` resolves a requested selection against the current binding. This recipe's viewport summary does not satisfy the full-UI accessibility target.

This recipe supports flat **array**, **object-collection**, and **entity-selection** list boxes on 4D 20.8. It does not support current/named record selections, hierarchical arrays, formatted columns, or collection/entity meta expressions. Those layouts produce a disabled table and no rows. Other controls in the form continue working.

## A collection form

Create a form named `ItemPicker` with a list box named `Items`. Set these properties:

| Object | Property | Value |
| --- | --- | --- |
| Form | Events | On Load, On Activate, On Unload |
| Form | Method | `ListAX_Form` |
| Items | Data source type | Collection or entity selection, bound to `Form.items` |
| Items | Variable or expression | `Form.items` |
| Items | Selected items | `Form.selectedItems` |
| Items | Selection mode | Multiple |
| Items | Meta info expression | Empty |
| Items | Events / method | On Selection Change / `ListAX_SelectionEvent` |
| ItemsKey column | Expression | `This.id` |
| ItemsName column | Expression | `This.name` |
| Both columns | Enterable | False |
| Both columns | Format | Empty |
| SelectionStatus input | Variable or expression / Enterable | `Form.selectionSummary` / False |

Pass a data object to the existing `DIALOG` call. It must contain `items`, a collection of objects such as `New object("id"; "item-42"; "name"; "Acoustic guitar")`, and `selectedItems`, initialized with `New collection`. Each item needs a unique nonempty **Text** ID. Use opaque, non-sensitive keys: an AX client can read them in row identifiers even when the key column is hidden. Only the allowlisted name column contributes spoken text. Key matching distinguishes case and accents.

Add these methods. `ListAX_Form` follows the same lifecycle as the simple-form example:

```4d
// ListAX_Form
var $reply; $options : Object
var $operation : Text
Case of
 : (Form event code=On Load)
  Form.selectionSummary:="No items selected"
  Form.listAX:=New object("kind"; "collection"; "objectName"; "Items"; "id"; "items"; "label"; "Items"; "keyColumn"; "ItemsKey"; "keyProperty"; "id"; "selection"; Formula(Form.selectedItems); "labelColumns"; New collection(New object("objectName"; "ItemsName"; "property"; "name")))
  If (Form.entity=True)
   Form.listAX.kind:="entity"
  End if
  Form.listAX.onSelection:=Formula(ListAX_SelectionChanged)
  $options:=New object("label"; "Item picker"; "describe"; Formula(ListAX_Describe); "apply"; Formula(ListAX_Apply($1)))
  $operation:="start"
  If (Form.isSubform=True)
   $operation:="register"
  End if
  $reply:=AXB_Form($operation; $options)
  If (Not($reply.ok=True))
   Form.axbError:=$reply.error
  End if
 : (Form event code=On Activate)
  ListAX_SelectionChanged
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
```

```4d
// ListAX_Describe
#DECLARE -> $description : Object
var $grid : Object
$description:=AXB_Controls(New collection(New object("objectName"; "SelectionStatus"; "id"; "selectionStatus"; "role"; "text"; "label"; "Selection"; "value"; Form.selectionSummary; "enabled"; True)))
If (Not($description.ok=True))
 return
End if
$grid:=AXB_Listbox(Form.listAX)
If (Not($grid.ok=True))
 $description:=$grid
 return
End if
$description.nodes:=$description.nodes.concat($grid.nodes)
$description.scope:="item-picker"
```

```4d
// ListAX_Apply
#DECLARE($action : Object) -> $result : Object
$result:=AXB_ListboxSelect(Form.listAX; $action)
```

Put dependent-control work in one shared method. This sample updates the visible selection summary:

```4d
// ListAX_SelectionChanged
Form.selectionSummary:=String(Form.selectedItems.length)+" items selected"
```

The list box's normal human event calls that same method:

```4d
// ListAX_SelectionEvent
If (Form event code=On Selection Change)
 ListAX_SelectionChanged
End if
```

Add these declarations to an existing compiler method, or create `Compiler_ListAX` if the project has none. The last declaration is for the array option below; omit it until adding that method.

```4d
// Compiler_ListAX
C_OBJECT(ListAX_Describe; $0)
C_OBJECT(ListAX_Apply; $0; $1)
C_OBJECT(ListAX_ArrayOptions; $0)
```

The `selection` formula must read the **same selected-items expression configured on the list box**. 4D 20.8 cannot query that expression at runtime. The adapter obtains the displayed collection through `OBJECT Get value("Items")`; it does not use a second cached collection. Column expressions must be direct `This.property` accesses matching the configured `keyProperty` and label `property` values. Formula changes disable the adapter.

The describe example combines `AXB_Controls` with `$grid.nodes`; it does not publish the adapter's internal source-position map. Preserve any existing `scope` and `subforms` when adding it to another form. If the list belongs to a record, set `scope` to that record's ID whenever the owning record changes. While data is loading, leave the grid nodes out of the description.

Selection changes the real list box. The adapter returns an internal pending result for arrays, collections and entities. `AXB_Form` waits for the actual selection in the same form instance, calls `onSelection` once, and checks the selection again on a later poll. Return the helper's result unchanged. Only an unchanged, confirmed selection produces a `completed` receipt. A handler that clears the selection or changes the record scope rejects completion without replay. Confirmation expires after two seconds, including time spent in the callback.

A `rejected` confirmation can follow a native selection change. The bridge skips the callback if the scope changes, the form becomes hidden or inactive, the grid becomes unsupported, or another selection replaces the requested one before readback. It also rejects changes made by a callback that already ran. It does not undo an earlier selection. Recompute dependent controls from the current binding in the application's existing record-load, activation, and human-selection handlers. Do not use a receipt as the authoritative selection, or retry a rejected request without reading the current UI. Keep irreversible business work out of `onSelection`.

The sample refreshes its summary on activation and human selection. When application code replaces or changes the items, call `ListAX_SelectionChanged` once the new selection binding is current. A parent that hides and reveals a picker subform must refresh that child's summary in its existing reveal handler too; revealing a container need not activate its window.

The tested 4D 20.8 selection commands generate neither `On Clicked` nor `On Selection Change`. Human row selection uses the existing event method; AX selection uses `onSelection` after the bindings are current. The callback can therefore run the same dependent-control logic without a timer or a guessed delay. Keep later business actions in their existing handlers. Verify current-item/current-position bindings separately if that logic uses them instead of selected items.

The bridge records unexpected callback failures in `Form.axbError` / `Form.axbFailure` and detaches. Add the root `onError` callback described in [the integration guide](../INTEGRATION.md#when-nothing-appears-in-accessibility-inspector) to connect your application's logger or cleanup. A failed start is reported directly, as shown above.

## An array form

Use the same lifecycle, describe, and apply methods. Replace `Form.listAX` with an array configuration:

```4d
// ListAX_ArrayOptions
#DECLARE -> $options : Object
$options:=New object("kind"; "array"; "objectName"; "Items"; "id"; "items"; "label"; "Items"; "keyColumn"; "ItemsKey"; "labelColumns"; New collection(New object("objectName"; "ItemsName")))
```

Set the form's list-box source type to Arrays. Bind `ItemsKey` to a Text key array and `ItemsName` to a Text label array. Bind `Items` itself to its Boolean selection array. In `ListAX_Form`, replace the collection-options assignment with `Form.listAX:=ListAX_ArrayOptions`; keep the following `onSelection` assignment. Change `ListAX_SelectionChanged` to count `True` values in that Boolean array, for example `Count in array(aItemsSelected; True)`, instead of reading `Form.selectedItems.length`. The human event method stays the same. Read business state directly from its binding, so an accessibility limit never changes the displayed count.

The adapter obtains pointers from the actual list and column objects. Do not supply a separate key array or a stale copy of the selection. 4D's native sort keeps the bound arrays aligned. The adapter re-reads them before every action. It also reads the list's row-control array: hidden rows disappear; disabled and nonselectable rows cannot accept selection. Per-row hidden/disabled state is supported only for arrays here. Collection/entity meta expressions remain unsupported.

## An entity-selection form

Use the collection recipe with `Form.items` bound to the entity selection the application already loaded. Initialize `Form.selectedItems` to an empty selection from the same dataclass. Set `entity: True` on the data object passed to the form; `ListAX_Form` then selects `kind: "entity"`. Keep the `selection` formula bound to the control's selected-items expression. An entity-only form can set `kind: "entity"` directly instead of using the flag. The key must be a stored Text attribute, or a stored numeric attribute whose values are all integers in the signed 32-bit range. Labels must be stored Text attributes. Substitute the application's actual attribute names in the columns and options together. The adapter rejects computed attributes and aliases before reading any entities. Integer keys become Text row IDs with an `n:` prefix, such as `items.n:42`; label columns still control what is spoken. Formatted labels need an application display model.

The adapter reads the actual entity selection from the control and checks selected entities by membership. It does not call `USE ENTITY SELECTION`, navigate a classic current selection, or save entities. Ordered entity selections can contain duplicates; duplicate keys disable the grid just as they do for arrays. A Null label contributes no text; a row with no permitted label is omitted. Null keys and dropped entity references disable the grid. Reload the selection through the application's normal handler to remove dropped references. Entity selection confirmation uses the same next-cycle callback as collections.

Entity reads can touch the datastore. This adapter accepts at most 1,000 entities, reads only configured storage attributes, and performs no query. The application's describe callback should not query either. Load/filter/page the selection through the application's existing handlers. Measure the resulting polling cost against the real server before deploying; local fixture timing does not establish remote performance.

Current/named record selections remain disabled. A live probe found that native current-selection list-box commands unloaded an unsaved classic record buffer. They need a separate application-aware action path and readback; converting a named selection into the current selection on every poll is unsafe.

## A list box inside a subform

Use the same `ItemPicker` form and methods. Bind its parent subform container to an object containing `items`, `selectedItems`, and `isSubform: True`. Each container needs its own data object. The flag makes `ListAX_Form` call `register`; only the outer window calls `start` and supplies `onError`. Add the container's object name to the parent's description, for example `$description.subforms:=New collection("Picker")`. For a nested container, every intermediate form must register and name its immediate children. See [the subform lifecycle](../FORM-SUPPORT.md#subforms-and-repeated-instances).

The bridge routes both selection and its later confirmation back into the same child `Form` object. Replacing the child or changing any ancestor's scope cancels that confirmation. The fixture below runs two instances of this exact recipe in one root window, with separate selections and summaries. They use collections in the default run and entity selections in the `--entity` run.

## Scrolling and limits

The adapter checks identities across up to 10,000 array/collection rows, or 1,000 entities. Exceeding the binding limit or 100 visible labelled rows disables that grid and publishes no rows; it does not truncate the data. Filter the data or shrink the viewport to recover. The whole form still has the bridge's 4,096-node limit. Use automatic logical grids for large data. Preserve every meaningful control; do not reduce accessibility coverage to satisfy the snapshot budget. Only visible portions of allowlisted columns contribute labels. Headers, footers, scrollbars, horizontal scrolling, and locked columns constrain the row viewport.

Native scrolling changes the published rows on the next poll. A retained row that has left the viewport cannot select itself. Sorting preserves a row's stable ID while changing the source position used by its next action. An accessible Search, Next page, or Scroll control must call the application's existing handler; the adapter does not invent navigation or load more records.

Keys plus the local table ID and separator must fit in 78 UTF-16 units. A label longer than 512 UTF-16 units or duplicate keys anywhere in the binding, including offscreen rows, disables that grid. Correct the keys or shorten the displayed labels to recover. The adapter refuses formatted or multistyle labels because their raw backing values may differ from the displayed information.

Editing, header actions, hierarchy expansion, and drag/drop need separate application handlers. Use an explicit edit form with shared validation when that is the application's supported editing path. Do not claim that assigning an array cell reproduces a native edit.

## Reproduce the check

From the repository root, run:

```sh
python3 prepare_listbox_fixture.py --server "/path/to/4D Server.app"
open -n --arch arm64 /Applications/4D/4D.app --args --project "$PWD/build/listbox-fixture/Project/ListboxFixture.4DProject" --dataless --opening-mode interpreted --webadmin-auto-start false
python3 test_listbox_fixture.py --run --mode interpreted --expect-architecture arm64
```

The fixture has synthetic data only. Inspect and acknowledge 4D's application-mode license notice if it appears before running the test; the test does not dismiss dialogs. For a licensed compiled-desktop run, change both mode arguments to `compiled`.

To exercise entities instead of the root collection, prepare with `--entity`. Launch that prepared project with `--data "$PWD/build/listbox-fixture/synthetic.4dd"` in place of `--dataless`, then run the same external test command. The preparer creates 600 synthetic records in that disposable data file; it never connects to the application database.

These commands select native ARM execution. On an Intel Mac use `--arch x86_64` and `--expect-architecture x86_64`. The interpreted-host run uses a compiled component against two 600-row grids. It covers native sorting, confirmed selection callbacks, viewport changes past row 255, hidden/disabled array rows, multiple/single/empty selection, exact key/scope matching, changed column formulas, formatted-value rejection, duplicate keys, and unload. ARM and Intel compilation pass with type inference disabled. The entity run also checks the unsaved classic buffer, row limit, invalid type/dataclass, Null selected items, stored integer keys, computed-attribute rejection, and Null labels. Compiled desktop execution and application-specific business effects remain separate validation. See [the validation record](../VALIDATION.md) for the current check count.

Relevant 4D contracts: [displayed data-source value](https://developer.4d.com/docs/commands/object-get-value), [cell coordinates and clipping](https://developer.4d.com/docs/commands/listbox-get-cell-coordinates), [column formulas](https://developer.4d.com/docs/commands/listbox-get-column-formula), and [selection commands](https://developer.4d.com/docs/commands/listbox-select-row).
