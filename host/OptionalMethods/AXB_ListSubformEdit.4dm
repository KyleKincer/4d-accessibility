// Keep the native row editor and validation. EDIT ITEM enters the row's first
// field; only after verifying its real record can the child focus another field.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid; $action; $column; $cell; $editor; $node; $textAction; $request : Object
var $savedOK : Integer
$result:=New object("status"; "rejected"; "message"; "List subform changed before editing")
If ((Current form window#Frontmost window) | (Milliseconds>=$data.deadline) | Not(OBJECT Get enabled(*; $data.options.objectName)))
 return
End if
$reply:=AXB_ListSubform("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$grid:=$data.state.descriptor
$action:=$data.action
If (($grid.generation#$data.generation) | Not(OB Is defined($data.state.positions; $action.value.row)) | Not(OB Is defined($data.state.columns; $action.value.column)))
 return
End if
$column:=$data.state.columns[$action.value.column]
If (Not($column.enabled & $column.editable) | ($column.controlRole#"text"))
 return
End if
$cell:=New object("objectName"; $data.options.objectName; "row"; $action.value.row; "column"; $action.value.column; "generation"; $grid.generation; "state"; $data.state; "selectAll"; True; "editor"; Formula(AXB_ListEditor($1; $2; $3)))
$editor:=AXB_ListEditor($cell; "read"; Null)
If (Not($editor.active))
 If ($action.value.expectedEditor#Null)
  return
 End if
 If ($data.focusAttempted=True)
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformEdit($1)); "data"; $data)
 End if
 $request:=New object("table"; $data.state.binding.table; "record"; $data.state.binding.records[$data.state.positions[$cell.row]-1]; "form"; $data.state.binding.form; "column"; $cell.column)
 $savedOK:=OK
 EXECUTE METHOD IN SUBFORM($data.options.objectName; "AXB_ListEditorFocus"; $reply; $request)
 OK:=$savedOK
 If (($reply=Null) || Not($reply.ok=True))
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformEdit($1)); "data"; $data)
 End if
 $data.focusAttempted:=True
 return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformEdit($1)); "data"; $data)
End if
If (($action.operation="gridSetValue") & ($action.value.expectedEditor=Null))
 $reply:=AXB_GridValue($data.state; $column; $data.state.positions[$cell.row])
 If (Not($reply.ok & $reply.enabled & $reply.editable) | (Compare strings($reply.value; $action.value.expectedValue; sk char codes)#0))
  $result.message:="Cell value changed before editing"
  return
 End if
End if
If ($action.value.expectedEditor#Null)
 If ((Compare strings($editor.text; $action.value.expectedValue; sk char codes)#0) | (($editor.start-1)#$action.value.expectedEditor.selection[0]) | (($editor.end-$editor.start)#$action.value.expectedEditor.selection[1]))
  $result.message:="Cell editor changed before the request"
  return
 End if
End if
If ($action.operation="gridEdit")
 return New object("status"; "completed"; "message"; "List subform editor is focused")
End if
$node:=New object("objectName"; $data.options.objectName; "gridCell"; $cell; "protected"; False; "multiline"; $column.multiline)
$textAction:=New object("id"; $action.id; "operation"; "setValue"; "value"; $action.value.text)
If ($action.operation="gridSetSelection")
 $textAction.operation:="setSelection"
 $textAction.value:=$action.value.selection
End if
If ($action.operation="gridReplaceSelection")
 $textAction.operation:="replaceSelection"
End if
return AXB_TextAction($textAction; $node; New object)
