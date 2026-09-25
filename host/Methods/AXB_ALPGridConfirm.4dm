// Re-enter the same owning view and verify the resulting vendor viewport.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid; $action; $cell; $editor; $node; $textAction; $value : Object
var $key; $column : Text
$result:=New object("status"; "rejected"; "message"; "AreaList changed before action completion")
$reply:=AXB_ALPGrid("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$grid:=$data.state.descriptor
$action:=$data.action
$key:=$action.value.row
$column:=$action.value.column
If (($grid.generation#$data.generation) | Not(OB Is defined($data.state.positions; $key)) | Not(OB Is defined($data.state.columns; $column)))
 return
End if
If ($data.resumeAfterExit=True)
 // The owning form rechecks scope before this callback. Revalidate the
 // target's value, permissions and binding after application exit handlers.
 If ((Current form window#Frontmost window) | (AL_GetAreaLongProperty($data.state.area; ALP_Area_EntryInProgress)=1))
  return New object("status"; "rejected"; "message"; "AreaList focus changed after leaving the editor")
 End if
 return AXB_ALPGridAction("apply"; $data.options; $data.state; New object("action"; $action))
End if
If ($action.operation="gridReveal")
 If (($grid.frames[$key]#Null) && ($grid.frames[$key][$column]#Null))
  return New object("status"; "completed"; "message"; "AreaList cell is visible")
 End if
Else
 If ($data.widget#Null)
  $value:=AXB_ALPGridValue($data.state; $data.state.columns[$column]; $data.state.positions[$key])
  If (Not($value.ok) | ($value.role#$data.widget.role))
   return
  End if
  If (($data.inputSent=True) | Not($data.widget.focusable))
   If ($value.checked#$data.widget.checked)
    return New object("status"; "completed"; "message"; "AreaList checkbox state confirmed")
   End if
  Else
   If (Not($value.enabled & $value.editable & $value.active & $value.focusable) | (Current form window#Frontmost window) | Not(AXB_ControlFocus($data.options.objectName)))
    return
   End if
   If (($value.checked#$data.widget.checked) | ($value.value#$data.widget.value))
    return New object("status"; "rejected"; "message"; "AreaList checkbox changed before activation")
   End if
   If ($action.operation="gridEdit")
    return New object("status"; "completed"; "message"; "AreaList checkbox is focused")
   End if
   // Use the same process-targeted keyboard path as ordinary controls.
   // The vendor retains its entry callbacks, validation and commit/cancel.
   $data.inputSent:=True
   POST KEY(32; 0; Current process)
  End if
  If (Milliseconds<$data.deadline)
   return New object("status"; "pending"; "confirm"; Formula(AXB_ALPGridConfirm($1)); "data"; $data)
  End if
  return New object("status"; "rejected"; "message"; "AreaList did not accept the checkbox state change")
 End if
 $cell:=New object("objectName"; $data.options.objectName; "row"; $key; "column"; $column; "generation"; $grid.generation; "state"; $data.state; "editor"; Formula(AXB_ALPEditor($1; $2; $3)))
 $editor:=AXB_ALPEditor($cell; "read"; Null)
 If ($editor.active)
  If ($action.value.expectedEditor#Null)
   If ((Compare strings($editor.text; $action.value.expectedValue; sk char codes)#0) | (($editor.start-1)#$action.value.expectedEditor.selection[0]) | (($editor.end-$editor.start)#$action.value.expectedEditor.selection[1]))
    return New object("status"; "rejected"; "message"; "AreaList editor changed before the request")
   End if
  End if
  If ($action.operation="gridEdit")
   return New object("status"; "completed"; "message"; "AreaList cell editor is focused")
  End if
  $node:=New object("objectName"; $data.options.objectName; "gridCell"; $cell; "protected"; False; "multiline"; False)
  $textAction:=New object("id"; $action.id; "operation"; "setValue"; "value"; $action.value.text)
  If ($action.operation="gridSetSelection")
   $textAction.operation:="setSelection"
   $textAction.value:=$action.value.selection
  End if
  If ($action.operation="gridReplaceSelection")
   $textAction.operation:="replaceSelection"
  End if
  return AXB_TextAction($textAction; $node; New object)
 End if
End if
If (Milliseconds<$data.deadline)
 $result:=New object("status"; "pending"; "confirm"; Formula(AXB_ALPGridConfirm($1)); "data"; $data)
End if
