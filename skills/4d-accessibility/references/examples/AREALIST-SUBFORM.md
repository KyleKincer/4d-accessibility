# Example: two AreaList input subforms

This is the earlier explicit row-summary API. New integrations configure each grid under `options.children.<container>.grids` in the [automatic AreaList recipe](../GRIDS.md#add-an-arealist-grid-to-the-same-form). That path needs no child bridge methods. The example below remains for existing summary integrations.

`ReportAccessibilityFailure` below stands for the existing application diagnostic reporter accepting a failure object. Substitute its name and reuse its declaration. Use `onError` in root start options for later failures, as shown in [the ordinary-form recipe](AUTOMATIC-FORM.md). The example's application state uses plain local form data; with entity, class-instance or shared roots, keep that state in the application's existing UI controller.

Use this recipe when a parent displays two independently loaded grids. Each child owns its bridge registration and AreaList area reference. The parent owns loading the two sets of arrays and tells each child when its data is ready. [Install the AreaList host helpers first](AREALIST-FORM.md#add-the-grid-helpers-to-the-host).

This example uses two slots, `Left` and `Right`, in one 4D process. It supports reading visible row labels and selecting rows. The key identifies the line record, not its product. Existing application cell editing requires its own validation and remains separate from AX selection.

## Configure the forms and data

Create an input form named `LinePicker`. Add an AreaList plugin object named `Grid`. Leave its Variable or Expression blank and set its type to Integer, so 4D creates a separate plugin variable for each instance. Enable On Load and On Unload on the form, and call `LinePicker_Form` from its form method.

Add two input-subform objects named `Left` and `Right` to the parent. Both use `LinePicker`. Bind their Variable or Expression properties to `Form.left` and `Form.right`. Before displaying the parent, allocate two private data objects:

```4d
$data.left:=New object("side"; "Left"; "recordID"; "invoice-left"; "loadedRecordID"; ""; "gridReady"; False)
$data.right:=New object("side"; "Right"; "recordID"; "invoice-right"; "loadedRecordID"; ""; "gridReady"; False)
```

Here `$data` is the object passed to the parent's `DIALOG`. The parent lists `New collection("Left"; "Right")` in its description and calls `AXB_Form("start"; options)` after its own initialization. Each child only calls `register`.

Use six **process Text arrays**, declared below. The `Left` loader fills `aLeftLineKey`, `aLeftItem`, and `aLeftDescription`; the `Right` loader fills the corresponding `aRight` arrays. Keep each slot's arrays the same length and in the same order. Do not use local arrays or local pointers that outlive their method. Do not share one set of process arrays between independently sorted or reloaded children. Two root windows in the same process need additional storage slots or a different application-owned storage design.

Before the initial `DIALOG`, finish loading each slot, set its `loadedRecordID` to its `recordID`, and then set `gridReady` to true. When reloading an already open child, the **parent loader** follows this order, shown for the left slot:

```4d
Form.left.gridReady:=False
Form.left.recordID:=String($newRecordID)
// Rebuild all three left arrays in the new record's display order.
AL_SetAreaLongProperty(Form.left.area; ALP_Area_UpdateData; 0)
Form.left.loadedRecordID:=Form.left.recordID
Form.left.gridReady:=True
```

If loading fails, leave `gridReady` false. The child reads those properties through its private `Form`; its record scope changes with `recordID`. A retained AX row for the old record cannot select a same-named line in the new one. On initial display, the arrays are ready before the child exists. The child binds its area before its final `register` call, so the bridge cannot read it early. During a live reload, keep readiness false until binding and loading finish. Stop an old registration before replacing its area.

## Add the child methods

The following methods are extracted verbatim and compiled by the disposable repeated-subform fixture. Its observation wrappers call the documented describe/apply methods, record receipts and vendor errors, and enable ordinary cell entry for the editing regression. Replacement calls the documented stop method. Map the arrays and slot choice to your application, while preserving their lifetime and ownership.

```4d
// LinePicker_Form
var $areaVariable; $keys : Pointer
var $prefix : Text
var $error : Integer
var $reply : Object
Case of
 : (Form event code=On Load)
  $prefix:="aLeft"
  $keys:=->aLeftLineKey
  If (Form.side="Right")
   $prefix:="aRight"
   $keys:=->aRightLineKey
  Else
   If (Form.side#"Left")
    ReportAccessibilityFailure(New object("error"; "unknownGridSlot"))
    return
   End if
  End if
  $areaVariable:=OBJECT Get pointer(Object named; "Grid")
  Form.area:=$areaVariable->
  Form.lineKeys:=$keys
  $error:=AL_SetArraysNam(Form.area; 1; 1; $prefix+"Item")
  $error:=AL_SetArraysNam(Form.area; 2; 1; $prefix+"Description")
  $error:=AL_SetArraysNam(Form.area; 3; 1; $prefix+"LineKey")
  AL_SetHeaders(Form.area; 1; 1; "Item")
  AL_SetHeaders(Form.area; 2; 1; "Description")
  AL_SetWidths(Form.area; 1; 1; 130)
  AL_SetWidths(Form.area; 2; 1; 170)
  AL_SetAreaLongProperty(Form.area; ALP_Area_CompHideCols; 1)
  AL_SetAreaLongProperty(Form.area; ALP_Area_SelType; 0)
  AL_SetAreaLongProperty(Form.area; ALP_Area_SelMultiple; 1)
  AL_SetAreaLongProperty(Form.area; ALP_Area_ReadOnly; 15)
  Form.gridAX:=New object("id"; "lines"; "label"; Form.side+" lines"; "columnCount"; 3; "keyColumn"; 3; "keySource"; $prefix+"LineKey"; "labelColumns"; New collection(New object("column"; 1; "source"; $prefix+"Item"); New object("column"; 2; "source"; $prefix+"Description")))
  $reply:=AXB_Form("register"; New object("label"; Form.side+" lines"; "describe"; Formula(LinePicker_Describe); "apply"; Formula(LinePicker_Apply($1))))
  If (Not($reply.ok=True))
   ReportAccessibilityFailure($reply)
  End if
 : (Form event code=On Unload)
  LinePicker_Stop
End case
```

This example configures the ordinary area for reading and selection. Keep your application's actual entry, validation, formatting and selection callbacks when adapting an existing editable area. Do not turn off ordinary editing simply to add AX selection.

```4d
// LinePicker_Describe
#DECLARE -> $description : Object
var $keys : Pointer
$description:=New object("scope"; Form.recordID; "enabled"; False; "nodes"; New collection)
If ((Form.gridReady=True) & (Compare strings(Form.loadedRecordID; Form.recordID; sk char codes)=0))
 $keys:=Form.lineKeys
 $description.enabled:=True
 $description.nodes:=AXB_ALPRows(Form.area; "Grid"; $keys; Form.gridAX)
End if
```

```4d
// LinePicker_Apply
#DECLARE($action : Object) -> $result : Object
var $keys : Pointer
$result:=New object("status"; "rejected"; "message"; "Grid is loading or unavailable")
If ((Form.gridReady=True) & (Compare strings(Form.loadedRecordID; Form.recordID; sk char codes)=0))
 $keys:=Form.lineKeys
 $result:=AXB_ALPRowsSelect(Form.area; "Grid"; $keys; Form.gridAX; $action)
End if
```

```4d
// LinePicker_Stop
var $reply : Object
$reply:=AXB_Form("stop"; New object)
```

The vendor declares optional argument slots for `AL_SetArraysNam`, `AL_SetHeaders`, and `AL_SetWidths`. 4D 20.8 reports seven 533.4 warnings for those documented calls in this example; the fixture compiler accepts only those calls and rejects unexpected diagnostics.

Add the declarations to the application's compiler method. Its arrays are per process, not interprocess variables:

```4d
// Compiler_LinePicker
C_OBJECT(LinePicker_Describe; $0)
C_OBJECT(LinePicker_Apply; $0; $1)
ARRAY TEXT(aLeftLineKey; 0)
ARRAY TEXT(aLeftItem; 0)
ARRAY TEXT(aLeftDescription; 0)
ARRAY TEXT(aRightLineKey; 0)
ARRAY TEXT(aRightItem; 0)
ARRAY TEXT(aRightDescription; 0)
```

## Replace a child and budget the window

Before replacing the left child, call `EXECUTE METHOD IN SUBFORM("Left"; "LinePicker_Stop")`, then run any shared application cleanup inside that old child. Allocate fresh left data with the slot, record ID and readiness properties above, bind it with `OBJECT SET VALUE("Left"; Form.left)`, and use `OBJECT SET SUBFORM` to install the replacement. Its On Load creates a new registration. Do not rely on programmatic replacement delivering On Unload.

`AXB_ALPRows` validates all bound keys, up to 200, but publishes only rows intersecting that area's viewport, up to 100. The total snapshot still has a 4,096-node limit: add one table plus the visible rows for **each** child, then the parent's other controls. Account for all ordinary nodes across the form; a snapshot over the limit stops the root bridge and reports the error through its `onError` callback. Do not truncate or reorder bound arrays to meet the budget.

The adapter converts AreaList's window-relative row coordinates to child-local coordinates. The form helper then translates and clips them through the parent. Do not add the container offset in your application callbacks.

[The fixture evidence](../VALIDATION.md) distinguishes these synthetic tests from real application validation. Test your actual reload, sort, business selection callback, error and close paths before enabling the integration.

Only rows in the current viewport are accessible. VoiceOver's row count describes that published subset, not the total bound array. This older explicit adapter exposes no scrolling action or keyboard-focus transfer into the vendor grid. Use [automatic grid composition](../GRIDS.md#add-an-arealist-grid-to-the-same-form) for complete rows, editing and reveal. An agent can use ordinary mouse/keyboard scrolling, then inspect the refreshed AX rows; this is not a complete VoiceOver-only navigation path for long grids. Preserve that limitation when evaluating a real application rollout.
