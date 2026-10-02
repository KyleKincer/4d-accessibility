# Configure AreaList Pro grids

Add an `areaList` entry to the same `options.grids` object that `AXB_Configure` returns, with the root [lifecycle area](AREA-INTEGRATION.md) in place. Fields and buttons remain automatically discovered. [GRIDS](GRIDS.md) owns the contracts shared with native grids: the [loading guard](GRIDS.md#gate-loading-and-record-changes), [temporary keys for unsaved rows](GRIDS.md#give-unsaved-rows-temporary-keys), [column `automationKey`](GRIDS.md#describe-custom-native-grid-columns) and the [selection callback](GRIDS.md#reuse-the-existing-selection-controller). For a whole form, see the [record-editor example](examples/RECORD-EDITOR.md).

Work through the sections in order. Preflight decides whether the area can use this adapter at all.

## Preflight the live area

Install AreaList Pro and the host helpers with `--area-list`. The current fixtures use AreaList Pro 11.4.2. Before changing configuration, read the live layout with the vendor getters:

| Requirement | Live check |
| --- | --- |
| Not transposed | `ALP_Area_Transposed=0` |
| Row selection | `ALP_Area_SelType=0` |
| Single-row layout, not multi-row | `ALP_Area_RowsInGrid=1` |
| Normal vendor array sorting | `ALP_Area_DontSortArrays=0` |
| No hierarchy | `ALP_Area_AutoHierarchy=0`, and `AL_GetObjects2` for `ALP_Object_Hierarchy` reports no hierarchy levels |
| Flat array-backed data | Every bound array matches the area's row count |
| Stable row keys | One existing Text, Integer or LongInt array, bound to exactly one column, holding unique identities. Text keys are nonempty and at most 256 UTF-16 units. |

A custom sort callback is compatible only if it preserves these conditions and sorts the bound arrays together. An incompatible layout appears as a disabled table. Layout failures share a generic label, so read these properties to identify the failed requirement. Preserve the application's semantics: an incompatible layout requires adapter work, not a silent change to vendor flags.

Use the existing identity array. Integer IDs are normalized to Text only in the accessibility descriptor; the bound array stays numeric. Empty Text keys and duplicate identities disable the grid. Real arrays are not accepted as keys; they and other unsupported bindings require adapter work. Prefer extending the canonical adapter over adding a parallel Text identity array.

If an existing supported identity array is not bound to a column, append it as a hidden column only after checking every sort, insert and delete path keeps it aligned with the other arrays. Preserve existing physical column numbers. Unsaved rows need stable application-owned [temporary keys](GRIDS.md#give-unsaved-rows-temporary-keys). Validate selection, sorting and editing through the actual application paths.

Preflight is complete when every requirement above has been read from the live area and holds, or the failing requirement is recorded as adapter work.

## Configure the grid

Point `keys` at the area's existing compatible key array:

```4d
$options:=New object("label"; "Record details"; "scope"; Formula(String(Form.recordID)); \
 "onError"; Formula(ReportAccessibilityFailure($1)))
$lines:=New object("kind"; "areaList"; "label"; "Record rows"; \
 "keys"; ->aLineID; "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.recordID)))
$options.grids:=New object("Items"; $lines)
```

`Items` is the form object's name. The provider finds the key array in the area's actual column bindings; it must occur exactly once. An optional `keyColumn` asserts a particular physical column number if your application needs that additional check. For native `array` grids, `keyColumn` is instead the key column's form-object name. Order the existing loader by the [loading guard](GRIDS.md#gate-loading-and-record-changes) and change `scope` with the record.

The provider reads current vendor bindings and formatting, exposes every non-hidden row and displayed column, and resolves retained cells by their keys after sorting. Key failures name themselves in the table label, for example `key array is not bound to the area` or `key array has more than one column binding`.

## Describe custom columns

Ordinary scalar text, numeric, date, time and Boolean columns need no description configuration. Supported Boolean/integer checkbox displays also retain their existing editing behavior; see [checkbox cells](#checkbox-cells). Every displayed picture, calculated or custom column requires a text description or an explicit decorative declaration; otherwise the grid is disabled with a label such as `column 5 needs a text description`, or `calculated column 5 needs a text description`. Add metadata only where the existing UI does not describe its meaning.

Column keys are actual runtime vendor column numbers as Text, independent of display order. Read the disabled table's label through AX to identify the physical column. Legacy setup can omit an empty column and shift later bindings, so confirm each column's live binding with the vendor's binding getters before writing its metadata. Never mark an assumed spacer decorative; it may now contain data. A key that is not a whole number written plainly, such as `"05"`, returns `invalidGrids` from `start`.

For example, an image indicator and a decorative spacer:

```4d
// Set this before returning the options from AXB_Configure.
$lines.columns:=New object(\
 "5"; New object("label"; "Visibility"; \
  "value"; Formula(Choose(AXB_PictureEquals(apictVisibility{$1.row}; <>hiddenPict); "Hidden item"; "Visible item"))); \
 "6"; New object("decorative"; True))
```

Here `apictVisibility` is the picture array bound to that column, and `<>hiddenPict` is the application's existing hidden-item icon. Use your application's actual array/icon names, or resolve `$1.key` in its existing model.

For a calculated column, reuse the function called by its existing vendor callback:

```4d
$lines.columns["1"]:=New object("label"; "Location"; \
 "value"; Formula(DescribeLocation(aLineID{$1.row}; aLineKind{$1.row})))
```

`DescribeLocation` stands for the application's existing read-only display function. Its required data must already be loaded. AreaList Pro 11.4.2 rejects source-name queries for calculated columns and cannot read an uncached calculated cell by logical row. The bridge compares the actual column pointers and uses this formula to read any requested row without scrolling the vendor control. A missing formula disables the grid before either invalid vendor query. Keep calculated columns read-only; an editable custom display still requires an editor adapter.

Column metadata rules:

- A `label` overrides the header.
- A `value` formula provides readable text for a picture or another custom display. It receives `{key, row, column}` in `$1` and runs inside the owning form when a cell page is requested. Read the existing UI model, without querying, saving, or changing selection.
- A row-based formula must read an array that AreaList sorts together with the grid, or resolve `$1.key` in the model. An unbound parallel array can describe the wrong row after sorting.
- Custom descriptions are read-only.
- A decorative column is omitted from the tree while retaining its width for neighboring cells.
- Hidden and password-formatted cells never call the value formula or publish their contents. Attributed text is published without its formatting markup.
- `automationKey` replaces the `column.N` locator segment; see [stable column locators](GRIDS.md#describe-custom-native-grid-columns).

## Edit and select

Text entry uses the existing vendor editor and its entry/exit callbacks. Normal Undo, Redo and validation remain responsible for the edit. Moving into another cell first exits the active editor through the vendor. Rejected input keeps that editor open; a scope change in its exit handler rejects the queued continuation. The bridge then rechecks the requested cell before opening it. No extra application callback is needed.

AreaList confirms selection through its own readback path. Add `onSelection` only if the application's ordinary selection path needs an existing shared refresh handler, following the [selection callback contract](GRIDS.md#reuse-the-existing-selection-controller). Do not call a general click handler that also opens records or runs business commands.

## Repeated child grids

For a grid inside an automatic subform, put this same grid configuration under `options.children.LineDetails.grids`. The root owns registration; the child needs no bridge method. Give each repeated instance its own area variable, every bound array, key-array pointer and record scope. Leave the plugin object's Variable blank for an instance-local area. Sharing only the key array separately is insufficient.

For example, independently changing records in repeated children can use:

```4d
// Root context. These are separate, existing process arrays bound in each area.
// The other bound arrays must also belong to their respective instance.
$leftLines:=New object("kind"; "areaList"; "label"; "Pending lines"; "keys"; ->aLeftLineID; \
 "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.recordID)))
$rightLines:=New object("kind"; "areaList"; "label"; "Posted lines"; "keys"; ->aRightLineID; \
 "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.recordID)))
$options.children:=New object
$options.children.Left:=New object("label"; "Pending record"; "scope"; Formula(String(Form.recordID)); "grids"; New object("Items"; $leftLines))
$options.children.Right:=New object("label"; "Posted record"; "scope"; Formula(String(Form.recordID)); "grids"; New object("Items"; $rightLines))
```

Each child's loader follows the [child-grid readiness rules](GRIDS.md#gate-loading-and-record-changes), including completions delivered to the root with `CALL FORM`. Separate AreaList areas and bound arrays remain required for independent grid contents.

## Checkbox cells

Keep the same grid configuration. Boolean columns displayed as checkboxes and Integer/LongInt columns configured as two- or three-state checkboxes are discovered automatically. The column header supplies the label; use `columns.<number>.label` when it needs clarification. Leave `value` descriptions off interactive checkboxes, since a description replaces the control with read-only text.

The adapter preserves the column's `ALP_Column_FocusableCheckbox` setting. For a non-focusable checkbox, AXPress uses AreaList's normal cell-entry command, which toggles the value and runs the existing entry/exit callbacks. AXFocused is unavailable because that vendor command would also toggle the value. For a focusable checkbox, AXFocused opens the editor without changing the value, and AXPress sends Space to that editor. Its uncommitted value appears in AX; normal Escape and focus transfer retain the vendor's cancel, commit and validation behavior. A completed press confirms the displayed checkbox state, not a database save.

Area, column and cell entry permissions remain authoritative. Hidden and password-formatted cells publish no state. A validation callback that restores the previous value produces a rejected action receipt; the adapter does not retry it. Sorting follows stable row keys, and a loading or scope transition retires old controls.

Install matching plugin, component and host helpers. Startup requires `cellFocus 1` so an older plugin cannot advertise a focus operation on a control that activates immediately. The synthetic fixture exercises normal, small and mini checkbox display modes. Formatted Boolean editors, vendor radio/popup choices and custom-picture checkbox rendering need separate validation or implementation.

## Limits

AreaList flat row selection and ordinary text editing work in isolated fixtures. Supplementary Unicode is rejected before opening or changing an editor. AreaList Pro 11.4.2 corrupts memory while reading, copying or committing long supplementary text even without this bridge; the 11.4.3b5 preview also fails. The guard protects bridge requests, not the vendor's direct-input path. See the [reproduction](https://github.com/KyleKincer/4d-accessibility/blob/main/tests/AREA-LIST-UNICODE.md).

Protected-cell editing, vendor popup/radio interaction, hierarchical and multiline layouts, and complete assistive-technology validation remain open. These are implementation gaps, not the final accessibility contract.
