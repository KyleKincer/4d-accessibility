// Run only after the same view has refreshed its provider state. Returning a
// page never scrolls, selects, enters an editor or evaluates a source expression.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $descriptor; $query; $page; $rowData; $column; $definition; $cell; $action; $data; $value : Object
var $rows; $cells; $positions : Collection
var $key; $columnID; $text : Text
var $r; $c; $start; $end; $firstColumn; $lastColumn; $position; $scrollRow; $scrollColumn : Integer
$result:=New object("ok"; True; "pages"; New collection; "status"; "rejected"; "message"; "Grid changed before the request")
If (Not($state.valid=True))
 return
End if
$descriptor:=$state.descriptor
If ($operation="readGrid")
 For each ($query; $request.requests)
  If (($query.generation=$descriptor.generation) & ($query.order=$descriptor.order))
   $start:=$query.row
   $end:=$start+$query.rowCount
   $firstColumn:=$query.column
   $lastColumn:=$firstColumn+$query.columnCount
   If (($start<0) | ($end>$descriptor.rows.length) | ($query.rowCount<1) | ($query.rowCount>16) | ($firstColumn<0) | ($lastColumn>$descriptor.columns.length) | ($query.columnCount<1) | ($query.columnCount>8))
    return
   End if
   $rows:=New collection
   For ($r; $start; $end-1)
    $key:=$descriptor.rows[$r]
    $position:=$state.positions[$key]
    $cells:=New collection
    For ($c; $firstColumn; $lastColumn-1)
     $definition:=$descriptor.columns[$c]
     $columnID:=$definition.id
     $column:=$state.columns[$columnID]
     $value:=AXB_GridValue($state; $column; $position)
     $cell:=New object("column"; $columnID; "value"; $value.value; "enabled"; $value.ok & $definition.enabled & $value.enabled & (AXB_KeyIndex($descriptor.disabled; $key)<0); "editable"; $value.editable & $definition.editable & (AXB_KeyIndex($descriptor.uneditable; $key)<0))
     If ($value.role#Null)
      $cell.role:=$value.role
      If ($value.checked#Null)
       $cell.checked:=$value.checked
      End if
      If ($value.label#Null)
       $cell.label:=$value.label
      End if
     End if
     $cells.push($cell)
    End for
    $rows.push(New object("id"; $key; "cells"; $cells))
   End for
   $page:=New object("node"; $query.node; "generation"; $descriptor.generation; "order"; $descriptor.order; "row"; $start; "column"; $firstColumn; "rows"; $rows)
   $result.pages.push($page)
  End if
 End for each
 return
End if
If (($operation#"apply") | (Current form window#Frontmost window))
 return
End if
$action:=$request.action
If (($action.node#$options.id) | Not(OBJECT Get enabled(*; $options.objectName)))
 return
End if
If (New collection("gridHeaderPress"; "gridHeaderReveal").indexOf($action.operation)>=0)
 If (Value type($action.value)#Is object)
  return
 End if
 $columnID:=$action.value.column
 If (($action.value.generation#$descriptor.generation) | Not(OB Is defined($state.columns; $columnID)))
  return
 End if
 $column:=$state.columns[$columnID]
 If (Not($column.header.visible=True))
  return
 End if
 If (($action.operation="gridHeaderPress") & Not($column.header.enabled & $column.header.press))
  return
 End if
 If ((($column.header.visible#$action.value.expectedHeader.visible) | ($column.header.enabled#$action.value.expectedHeader.enabled) | ($column.header.press#$action.value.expectedHeader.press) | ($column.header.sortable#$action.value.expectedHeader.sortable) | ($column.header.sort#$action.value.expectedHeader.sort)))
  $result.message:="Header changed before activation"
  return
 End if
 OBJECT GET SCROLL POSITION(*; $options.objectName; $scrollRow; $scrollColumn)
 OBJECT SET SCROLL POSITION(*; $options.objectName; New collection(1; $scrollRow).max(); $column.number)
 $data:=New object("options"; $options; "state"; $state; "action"; $action; "generation"; $descriptor.generation; "deadline"; Milliseconds+2000)
 return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
End if
If (New collection("gridReveal"; "gridEdit"; "gridPress"; "gridSetValue"; "gridSetSelection"; "gridReplaceSelection").indexOf($action.operation)>=0)
 If (Value type($action.value)#Is object)
  return
 End if
 If ($action.value.generation#$descriptor.generation)
  return
 End if
 $key:=$action.value.row
 $columnID:=$action.value.column
 If (Not(OB Is defined($state.positions; $key)) | Not(OB Is defined($state.columns; $columnID)))
  return
 End if
 $column:=$state.columns[$columnID]
 $position:=$state.positions[$key]
 $data:=New object("options"; $options; "state"; $state; "action"; $action; "generation"; $descriptor.generation; "deadline"; Milliseconds+1500)
 If ($action.operation="gridReveal")
  OBJECT SET SCROLL POSITION(*; $options.objectName; $position; $column.number)
 Else
  If ((AXB_KeyIndex($descriptor.uneditable; $key)>=0) | Not($column.editable=True) | Not(OBJECT Get enterable(*; $column.name)) | Not(OBJECT Get enabled(*; $column.name)) | $column.protected)
   return
  End if
  $value:=AXB_GridValue($state; $column; $position)
  If (Not($value.ok & $value.enabled & $value.editable))
   return
  End if
  If ($action.value.expectedCell#Null)
   If (New collection("gridEdit"; "gridPress").indexOf($action.operation)<0)
    return
   End if
   If ((New collection("checkbox"; "popup").indexOf($value.role)<0) | ($value.role#$action.value.expectedCell.role) | (Compare strings($value.value; $action.value.expectedCell.value; sk char codes)#0) | ($value.checked#$action.value.expectedCell.checked))
    $result.message:="Cell control changed before activation"
    return
   End if
   $data.widget:=$value
  Else
   If (($action.operation="gridPress") | (New collection("checkbox"; "popup").indexOf($value.role)>=0))
    return
   End if
  End if
  If ($action.value.expectedEditor#Null)
   $cell:=New object("objectName"; $options.objectName; "row"; $key; "column"; $columnID; "generation"; $descriptor.generation)
   If (Not(AXB_TextFocus($column.name; $cell)) | Not(Is editing text))
    return
   End if
   GET HIGHLIGHT(*; $column.name; $start; $end)
   If ((Compare strings(Get edited text; $action.value.expectedValue; sk char codes)#0) | (($start-1)#$action.value.expectedEditor.selection[0]) | (($end-$start)#$action.value.expectedEditor.selection[1]))
    $result.message:="Cell editor changed before the request"
    return
   End if
  Else
   If (New collection("gridSetSelection"; "gridReplaceSelection").indexOf($action.operation)>=0)
    return
   End if
  End if
  If (($action.operation="gridSetValue") & ($action.value.expectedEditor=Null))
   $text:=$value.value
   If (Compare strings($text; $action.value.expectedValue; sk char codes)#0)
    $result.message:="Cell value changed before editing"
    return
   End if
  End if
  If ($action.value.expectedEditor=Null)
   If ($action.operation="gridPress")
    // EDIT ITEM changes row selection when the cell later loses focus.
    // Reveal first; activation uses the same native click as the visible widget.
    OBJECT SET SCROLL POSITION(*; $options.objectName; $position; $column.number)
   Else
    EDIT ITEM(*; $column.name; $position)
   End if
  End if
 End if
 return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
End if
If (($action.operation#"gridSelect") | (Value type($action.value)#Is collection))
 return
End if
If (Not($descriptor.actions.select) | Not(OBJECT Get enabled(*; $options.objectName)))
 return
End if
$positions:=New collection
For each ($key; $action.value)
 If (Not(OB Is defined($state.positions; $key)) | ((AXB_KeyIndex($descriptor.unselectable; $key)>=0) & (AXB_KeyIndex($descriptor.selected; $key)<0)))
  return
 End if
 $position:=$state.positions[$key]
 If ($positions.indexOf($position)>=0)
  return
 End if
 $positions.push($position)
End for each
If ((LISTBOX Get property(*; $options.objectName; lk selection mode)=1) & ($positions.length>1))
 return
End if
If ($options.onSelection#Null)
 If ((Value type($options.onSelection)#Is object) || Not(OB Instance of($options.onSelection; 4D.Function)))
  return
 End if
End if
// Preserve selected rows that subsequently became unselectable. Clearing and
// re-adding them would ask 4D to select a restricted row as a new operation.
For ($position; 1; $state.binding.keys.length)
 If ($state.binding.selected[$position-1])
  If (AXB_KeyIndex($action.value; $state.binding.keys[$position-1])<0)
   LISTBOX SELECT ROW(*; $options.objectName; $position; lk remove from selection)
  End if
 End if
End for
For each ($position; $positions)
 If (Not($state.binding.selected[$position-1]))
  LISTBOX SELECT ROW(*; $options.objectName; $position; lk add to selection)
 End if
End for each
// Collection/entity selected-items bindings settle after this form callback.
// Confirm before invoking the shared handler or reporting successful selection.
$data:=New object("options"; $options; "state"; $state; "action"; $action; "generation"; $descriptor.generation; "retainedSelection"; $descriptor.selected; "deadline"; Milliseconds+2000)
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
