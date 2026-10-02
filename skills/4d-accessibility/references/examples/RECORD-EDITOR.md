# Example: record editor with editable grids

This example combines ordinary fields and buttons with an editable grid and optional nested or repeated subforms. The additional configuration identifies rows across sorting, distinguishes the current record from previously loaded data, and reuses existing formatters and selection controllers. `RecordEditor`, `recordID` and the other application names below are placeholders for the host's existing form and bindings. The [loading guard](../GRIDS.md#gate-loading-and-record-changes) is the contract; this example shows it in place.

The grid here is [AreaList](../AREALIST-GRIDS.md). For a native list box, use the [array, collection or entity grid options](../GRIDS.md) in place of the AreaList `$lines` configuration. Keep the same scope, readiness and loader ordering.

## Order the existing loader

This example uses existing mutable plain form data. For an entity, class-instance or shared root, use [existing editor state](#entity-class-and-shared-root-data) instead. Initialization must precede the first load, including when that loader runs inside On Load.

```4d
// Form method: start of On Load, before existing initialization can load lines.
Form.linesReady:=False

// Existing line loader: before changing arrays or starting asynchronous work.
// Match this declaration to the actual record ID type. This example uses Integer.
var $loadingRecordID : Integer
Form.linesReady:=False
$loadingRecordID:=Form.recordID
// Existing code loads this record's arrays.
// When that work finishes, record the ID the data actually belongs to:
Form.linesLoadedID:=$loadingRecordID
Form.linesReady:=True

```

If loading finishes asynchronously, retain its captured record ID with that load and use it at completion.

## Return the configuration

The installer adds the lifecycle area to `RecordEditor`. Keep configuration in an application method called by `AXB_Configure`:

```4d
// Application method: RecordEditorAccessibilityOptions
#DECLARE() -> $options : Object
var $lines : Object
$options:=New object("label"; "Record details"; "scope"; Formula(String(Form.recordID)); \
 "onError"; Formula(ReportAccessibilityFailure($1)))
$lines:=New object("kind"; "areaList"; "label"; "Record rows"; \
 "keys"; ->aLineID; "ready"; Formula(Form.linesReady && (Form.linesLoadedID=Form.recordID)))
$options.grids:=New object("Items"; $lines)
```

Add [picture/custom-column descriptions](../AREALIST-GRIDS.md#describe-custom-columns) to `$lines.columns`. If selection needs a dependent-UI refresh, set `$lines.onSelection` to the existing shared selection handler before returning the options. Add `C_OBJECT(RecordEditorAccessibilityOptions; $0)` to the application's compiler method, outside the installer-owned declarations. The area handles startup, startup failure reporting and shutdown.

## Entity, class and shared root data

Use the application's existing editor state instead of assigning the plain-data properties above. For example, a record-editor process may already own a mutable `RecordEditorState` object independently of its persisted record entity. Initialize that state before the first load, and update it in the existing loader:

```4d
// Existing process-owned editor state, before its first load:
RecordEditorState.linesReady:=False
// Before refreshing the bound arrays:
var $loadingRecordID : Integer
RecordEditorState.linesReady:=False
$loadingRecordID:=Form.recordID
// Existing loader fills the arrays, preserving its normal locking/validation.
RecordEditorState.linesLoadedID:=$loadingRecordID
RecordEditorState.linesReady:=True
```

The configuration reads that state while the actual record remains `Form`:

```4d
$options.scope:=Formula(String(Form.recordID))
$lines.ready:=Formula(RecordEditorState.linesReady && \
 (RecordEditorState.linesLoadedID=Form.recordID))
```

This example assumes one record editor per process. If the application keeps several editors in one process, use its existing per-window state lookup instead. Repeated children need their existing per-instance state too. An asynchronous completion must verify that its captured state and record still belong to the current editor before marking them ready. Declare the actual process variable and method types in the application's compiler method. Do not add UI attributes to an entity or bypass a shared object's `Use...End use` rules.

## Leave commands where they are

Fields, buttons and page subforms remain automatically discovered. Save, return and print keep their existing buttons, menus and business handlers. There is no accessibility-specific copy of those operations.
