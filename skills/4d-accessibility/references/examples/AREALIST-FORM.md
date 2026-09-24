# Example: invoice lines in AreaList Pro

This is the earlier explicit row-summary API. For a new integration, use the [complete AreaList grid configuration](../GRIDS.md#add-an-arealist-grid-to-the-same-form), which composes with automatic ordinary controls and exposes logical rows and columns. This example remains for existing integrations; its viewport summaries do not satisfy the full accessibility target.

`ReportAccessibilityFailure` below stands for the existing application diagnostic reporter accepting a failure object. Substitute its name and reuse its declaration. Use `onError` in root start options for later failures, as shown in [the ordinary-form recipe](AUTOMATIC-FORM.md). The example's application state uses plain local form data; with entity, class-instance or shared roots, keep that state in the application's existing UI controller.

An invoice screen uses the same start, describe, apply, and stop pattern as the [simple form](SIMPLE-FORM.md). The extra work is to describe the grid's bindings and choose a stable key for each line. The adapter selects rows through AreaList and reads the selection back. Verify that the application's existing Return command consumes those same line records, including after a sort.

This example uses a flat, array-backed, 24-column grid. Its first capability is reading permitted row labels and selecting lines. Cell editing and hierarchical layouts require their own validated adapters.

## Add the grid helpers to the host

Run the same installer with the grid option:

```sh
python3 install_host_methods.py --project-dir /path/to/MyApplication/Project --area-list
```

This installs `AXB_ALPNode`, `AXB_ALPRows`, `AXB_ALPRowsSelect`, and `AXB_ALPSelect` along with the ordinary helpers and their declarations. Keep the `--compiler-method` option used for your first install. AreaList must be installed in the host. These adapters stay in the host because a compiled component cannot dereference an interpreted host's array pointers.

## Describe the actual bindings

In this example the AreaList object name is `Lines`, its area reference is `vLines`, and its arrays are bound as follows:

| Column | Source | Use |
| --- | --- | --- |
| 5 | `aItemID` | Visible item label |
| 8 | `aDescription` | Visible description label |
| 23 | `aLineKey` | Unique line-record key, maintained in display order |

The key array is a **Text array** separate from the product array. Two invoice lines may contain the same product and must remain distinguishable after sorting. Keys must be nonempty, unique, and aligned with every displayed row. Identity comparison respects case and accents: `Case`, `case`, `café`, and `cafe` are four different keys. The array size must equal AreaList's row count. Column 23 must be bound to that array, and its formatted value must equal the key exactly. The local row ID `"lines."+key` must fit within 78 UTF-16 units.

After the application has configured the area, initialize:

```4d
Form.gridAX:=New object(\
 "id"; "lines"; "label"; "Invoice lines"; \
 "columnCount"; 24; "keyColumn"; 23; "keySource"; "aLineKey"; \
 "labelColumns"; New collection(\
  New object("column"; 5; "source"; "aItemID"); \
  New object("column"; 8; "source"; "aDescription")))
```

Every `source` and `keySource` must match the array name returned by `ALP_Column_Source` exactly. The adapter verifies that match on every read and before selection. It publishes only the listed label columns when AreaList marks the column and cell visible. Other bound columns, such as costs or internal notes, are not added automatically. Combined row labels must fit within 512 UTF-16 units; a longer label disables this adapter with an explanatory table label.

## Connect the form

This example keeps its own `gridAX`, `gridReady` and `loadedInvoiceID` state on plain local `Form` data. With entity, class-instance or shared roots, keep that state in the application's existing UI controller. Root bridge ownership already supports those bindings.

This example supplies `describe`, which replaces automatic control discovery. Its grid-only description leaves the form's other controls out of the bridge tree. Include required buttons and fields with `AXB_Controls` and route their actions in `InvoiceAX_Apply`, as shown below. For new integrations, the full grid adapter already composes with automatic discovery through `options.grids`.

Keep your existing initialization, loading indicator, timer, and grid callbacks. Initialize `Form.gridReady:=False` and `Form.loadedInvoiceID:=""` before loading. Before **every** array rebuild, set `gridReady` to false. After the area and arrays finish loading successfully, set `loadedInvoiceID:=String(Form.invoiceID)`, then `gridReady:=True`. Start once after the first successful load:

```4d
var $bridge : Object
$bridge:=AXB_Form("start"; New object(\
 "label"; "Invoice inquiry"; \
 "describe"; Formula(InvoiceAX_Describe); \
 "apply"; Formula(InvoiceAX_Apply($1))))
If (Not($bridge.ok=True) & ($bridge.error#"dependencyUnavailable"))
 ReportAccessibilityFailure($bridge)
End if
```

Use the same stop hook as the simple form, including error cleanup. Create `InvoiceAX_Describe`:

```4d
#DECLARE -> $description : Object
$description:=New object(\
 "scope"; String(Form.invoiceID); \
 "enabled"; False; "nodes"; New collection)
If ((Form.gridReady=True) & (Form.loadedInvoiceID=String(Form.invoiceID)))
 $description.enabled:=True
 $description.nodes:=AXB_ALPRows(vLines; "Lines"; ->aLineKey; Form.gridAX)
End if
```

These form properties, `vLines`, and the array names are this example's application-owned values. Map them to the real form. The readiness gate skips all AreaList calls while arrays are incomplete or belong to another invoice. If replacing the area object itself, stop before replacement and restart after initialization. For a completed refresh or sort, the next description updates the revision automatically.

Create `InvoiceAX_Apply`:

```4d
#DECLARE($action : Object) -> $result : Object
$result:=New object("status"; "rejected"; "message"; "Invoice action unavailable")
If ((Form.gridReady=True) & (Form.loadedInvoiceID=String(Form.invoiceID)))
 If (($action.node="lines") & ($action.operation="selectRows"))
  $result:=AXB_ALPRowsSelect(vLines; "Lines"; ->aLineKey; Form.gridAX; $action)
 End if
End if
```

Add the two methods' object parameter/result declarations as in the simple example. If selecting rows requires an application refresh or selection notification, put that shared application step after successful selection and verify its outcome. Calling AreaList's selection API does not synthesize a mouse click or every application callback.

## Put the grid inside an input subform

Follow [the complete repeated-subform recipe](AREALIST-SUBFORM.md). It includes the child form, describe/apply/stop methods, process-array compiler declarations, parent readiness and record-scope ownership, replacement, and the combined window budget. Each instance needs its own area reference and arrays; a private `Form` object alone does not separate a reused plugin variable or process array.

## Leave business commands in the application

Select the intended line, verify AreaList's resulting selection, then invoke the normal Return menu item or button. The row adapter does not create a business record. For a custom button that needs bridge exposure, add it to the description with `AXB_Controls` and route `press` through the existing shared handler and its permission checks. Preserve an accessible native menu instead of adding a duplicate virtual command.

To combine ordinary controls with the grid, build both collections inside the same readiness gate:

```4d
var $controls : Object
$controls:=AXB_Controls(New collection(\
 New object("objectName"; "Return"; "id"; "return"; "role"; "button"; "label"; "Create return"; "value"; ""; "enabled"; Bool(Form.canReturn))))
If (Not($controls.ok=True))
 return $controls
End if
$description.nodes:=$controls.nodes.concat(AXB_ALPRows(vLines; "Lines"; ->aLineKey; Form.gridAX))
```

This assumes your form actually has a custom `Return` button. Its `press` branch and human object method must call the same existing business handler. The adapter validates up to 200 bound keys but publishes only viewport rows, up to 100, plus the table. Sum those visible nodes across all grids and ordinary controls within the window's 4,096-node budget.

This is the whole additional grid contract. The reusable form helper handles the session, revisions, scope changes, and receipts. The grid helpers handle binding checks, row identity, geometry, selection limits, and readback.

## Validate the grid before enabling it

Use duplicate products with distinct line keys. Select a line, sort, refresh, and switch invoices. A retained control for an old invoice must not affect a new one, even if a local row key repeats. Check masked columns, hidden rows, scrolling, and resize. Test the normal business workflow afterward and verify the resulting records.

Current row-adapter limits are 200 bound rows, 100 viewport rows, 100 requested selections, a flat compatibility-mode layout, row selection mode, and unique nonempty keys matching the bound key column. The whole bridge also has a 4,096-node snapshot limit. Unsupported layouts return a disabled table, not guessed row actions. See [form families](../FORM-SUPPORT.md) for editable grids and other table types.

Use [automatic grid composition](../GRIDS.md#add-an-arealist-grid-to-the-same-form) for complete rows, editing and reveal. Only viewport rows are published and selectable through this older explicit adapter. The reported AX row count is the published subset. Ordinary UI scrolling updates that subset, but this explicit summary adapter exposes no scrolling action or keyboard-focus transfer into AreaList. Selecting a row through VoiceOver works within the published viewport; long-grid VoiceOver-only navigation remains unvalidated.

After a successful selection, the vendor reveal call can bring a partially clipped viewport row fully into view. It does not authorize selecting an unpublished row.

Runtime column numbering can differ from legacy setup arguments. The current invoice source test observes 23 columns and the key at physical 22, because an empty binding was omitted. Treat the older 24-column / key-column-23 numbers in this historical recipe as unverified assumptions. New integrations should resolve the existing key array through the [automatic grid provider](../GRIDS.md#add-an-arealist-grid-to-the-same-form). The installer now includes both the four legacy row helpers and the four full-grid/editor helpers when `--area-list` is supplied.
