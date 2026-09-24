// Paging does not change selection, scroll position, focus or the record buffer.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $descriptor; $query; $column; $definition; $cell; $action; $reply; $editor; $data; $value : Object
var $rows; $cells; $actual; $requested : Collection
var $key; $columnID; $text : Text
var $area; $r; $c; $start; $end; $firstColumn; $lastColumn; $position; $error; $mode; $unit; $code : Integer
ARRAY LONGINT($selection; 0)
$result:=New object("ok"; True; "pages"; New collection; "status"; "rejected"; "message"; "AreaList changed before the request")
If (Not($state.valid=True))
 return
End if
$area:=$state.area
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
     $value:=AXB_ALPGridValue($state; $column; $position)
     If (Not($value.ok))
      return New object("ok"; False; "error"; "invalidGridCellDescription")
     End if
     OB REMOVE($value; "ok")
     OB REMOVE($value; "active")
     $value.column:=$columnID
     $cells.push($value)
    End for
    $rows.push(New object("id"; $key; "cells"; $cells))
   End for
   $result.pages.push(New object("node"; $query.node; "generation"; $descriptor.generation; "order"; $descriptor.order; "row"; $start; "column"; $firstColumn; "rows"; $rows))
  End if
 End for each
 return
End if
If ($operation#"apply")
 return
End if
$action:=$request.action
If (($action.node#$options.id) | Not(OBJECT Get enabled(*; $options.objectName)))
 return
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
 $position:=$state.positions[$key]
 $column:=$state.columns[$columnID]
 // The vendor corrupts memory while reading or committing supplementary
 // Unicode, including text inserted by ordinary Paste without this bridge.
 // Reject before entering/selecting/deleting text in the tested versions.
 If (New collection("gridSetValue"; "gridReplaceSelection").indexOf($action.operation)>=0)
  $text:=$action.value.text
  For ($unit; 1; Length($text))
   $code:=Character code(Substring($text; $unit; 1))
   If (($code>=55296) & ($code<=57343))
    $result.message:="AreaList cannot safely edit supplementary Unicode in the tested vendor versions"
    return
   End if
  End for
 End if
 $data:=New object("options"; $options; "state"; $state; "action"; $action; "generation"; $descriptor.generation; "deadline"; Milliseconds+1500)
 If ($action.operation="gridReveal")
  AL_SetCellLongProperty($area; $position; $column.number; ALP_Cell_Reveal; 0; 1; 1)
 Else
  If (Current form window#Frontmost window)
   return
  End if
  If ($column.checkbox)
   If (New collection("gridPress"; "gridEdit").indexOf($action.operation)<0)
    return
   End if
   $value:=AXB_ALPGridValue($state; $column; $position)
   $cell:=$action.value.expectedCell
   If (($cell=Null) || Not($value.ok & $value.enabled & $value.editable) || ($value.role#$cell.role) || ($value.checked#$cell.checked) || ($value.value#$cell.value) || ($value.focusable#$cell.focusable))
    return
   End if
   If (($action.operation="gridEdit") & Not($value.focusable))
    $result.message:="This AreaList checkbox activates without keyboard focus"
    return
   End if
   $data.widget:=$value
   // A non-focusable checkbox toggles immediately through this vendor call.
   // A focusable checkbox only opens its editor. Never change the host's mode.
   If (Not($value.active) | Not(AXB_ControlFocus($options.objectName)))
    GOTO OBJECT(*; $options.objectName)
    AL_SetAreaTextProperty($area; ALP_Area_EntryGotoCell; String($position)+","+String($column.gridCell))
   End if
   return New object("status"; "pending"; "confirm"; Formula(AXB_ALPGridConfirm($1)); "data"; $data)
  End if
  If ($action.operation="gridPress")
   return
  End if
  $mode:=AL_GetCellLongProperty($area; $position; $column.number; ALP_Cell_Enterable)
  If ($mode=-1)
   $mode:=AL_GetColumnLongProperty($area; $column.number; ALP_Column_Enterable)
  End if
  If (Not($column.typed) | (New collection(1; 3; 5).indexOf($mode)<0) | ((AL_GetAreaLongProperty($area; ALP_Area_ReadOnly)%2)#0) | (AL_GetCellLongProperty($area; $position; $column.number; ALP_Cell_Invisible)#0))
   return
  End if
  If (AL_GetCellTextProperty($area; $position; $column.number; ALP_Cell_FormatResolved)=Char(8226))
   $result.message:="Protected AreaList editing requires a write-only editor"
   return
  End if
  $cell:=New object("objectName"; $options.objectName; "row"; $key; "column"; $columnID; "generation"; $descriptor.generation; "state"; $state)
  If ($action.value.expectedEditor#Null)
   $editor:=AXB_ALPEditor($cell; "read"; Null)
   If (Not($editor.active))
    return
   End if
   If ((Compare strings($editor.text; $action.value.expectedValue; sk char codes)#0) | (($editor.start-1)#$action.value.expectedEditor.selection[0]) | (($editor.end-$editor.start)#$action.value.expectedEditor.selection[1]))
    $result.message:="AreaList editor changed before the request"
    return
   End if
  Else
   If (New collection("gridSetSelection"; "gridReplaceSelection").indexOf($action.operation)>=0)
    return
   End if
   If ($action.operation="gridSetValue")
    $text:=AL_GetCellTextProperty($area; $position; $column.number; ALP_Cell_FormattedValue)
    If (Compare strings($text; $action.value.expectedValue; sk char codes)#0)
     $result.message:="AreaList value changed before editing"
     return
    End if
   End if
   GOTO OBJECT(*; $options.objectName)
   AL_SetAreaTextProperty($area; ALP_Area_EntryGotoCell; String($position)+","+String($column.gridCell))
  End if
 End if
 return New object("status"; "pending"; "confirm"; Formula(AXB_ALPGridConfirm($1)); "data"; $data)
End if
If (($action.operation#"gridSelect") | (Value type($action.value)#Is collection))
 return
End if
If (($action.value.length>1) & (AL_GetAreaLongProperty($area; ALP_Area_SelMultiple)=0))
 return
End if
If (($action.value.length=0) & (AL_GetAreaLongProperty($area; ALP_Area_SelNone)=0))
 return
End if
$requested:=New collection
For each ($key; $action.value)
 If (Not(OB Is defined($state.positions; $key)) | (AXB_KeyIndex($requested; $key)>=0))
  return
 End if
 $requested.push($key)
 APPEND TO ARRAY($selection; $state.positions[$key])
End for each
$error:=AL_SetObjects($area; ALP_Object_Selection; $selection)
If ($error#0)
 return
End if
If ($options.onSelection#Null)
 $options.onSelection.call()
End if
$reply:=AXB_ALPGrid("describe"; $options; $state; New object)
If (Not($state.valid=True))
 return
End if
$actual:=$state.descriptor.selected
If ($actual.length#$requested.length)
 return
End if
For each ($key; $requested)
 If (AXB_KeyIndex($actual; $key)<0)
  return
 End if
End for each
If ($requested.length>0)
 $key:=$requested[$requested.length-1]
 AL_SetRowLongProperty($state.area; $state.positions[$key]; ALP_Row_Reveal; 0; 1)
End if
$result.status:="completed"
$result.message:="AreaList selection confirmed"
