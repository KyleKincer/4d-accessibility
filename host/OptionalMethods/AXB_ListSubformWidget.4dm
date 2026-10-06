// Click the actual row checkbox or button so 4D enters its record normally.
// Observe its normal handlers and value; never assign the backing field.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid; $column; $value; $native : Object
var $frame : Collection
var $x; $y : Real
$result:=New object("status"; "rejected"; "message"; "List subform checkbox changed before activation")
If ((Current form window#Frontmost window) | Not(OBJECT Get enabled(*; $data.options.objectName)))
 return
End if
$reply:=AXB_ListSubform("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$grid:=$data.state.descriptor
If (($grid.generation#$data.generation) | Not(OB Is defined($data.state.positions; $data.action.value.row)) | Not(OB Is defined($data.state.columns; $data.action.value.column)))
 return
End if
$column:=$data.state.columns[$data.action.value.column]
$value:=AXB_GridValue($data.state; $column; $data.state.positions[$data.action.value.row])
If (Not($value.ok) | (New collection("checkbox"; "button").indexOf($value.role)<0))
 return
End if
If ($data.inputSent=True)
 $native:=AXB_PollGuard.context.controlInputResult
 If (($native=Null) || ($native.action#$data.action.id))
  If ((Milliseconds>=$data.deadline) & (AXB_PollGuard.context.controlInputReadAt>=$data.deadline))
   return
  End if
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformWidget($1)); "data"; $data)
 End if
 If (Not($native.accepted=True))
  return
 End if
 If ($value.role="button")
  return New object("status"; "completed"; "message"; "Row button pressed through its own handler")
 End if
 If ($value.checked#$data.widget.checked)
  return New object("status"; "completed"; "message"; "List subform checkbox state confirmed")
 End if
 If (Milliseconds>=$data.deadline)
  $result.message:="Application did not accept the checkbox state change"
  return
 End if
 return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformWidget($1)); "data"; $data)
End if
If ((Milliseconds>=$data.deadline) | Not($column.enabled & $column.editable & $value.editable & $value.enabled) | (($value.role="checkbox") && ($value.checked#$data.widget.checked)))
 return
End if
If (($grid.frames[$data.action.value.row]=Null) || ($grid.frames[$data.action.value.row][$column.id]=Null))
 return
End if
$frame:=$grid.frames[$data.action.value.row][$column.id]
$x:=$frame[0]+New collection(8; $frame[2]/2).min()
If ($value.role="button")
 $x:=$frame[0]+($frame[2]/2)
End if
$y:=$frame[1]+($frame[3]/2)
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$data.inputSent:=True
$data.deadline:=Milliseconds+2000
AXB_PollGuard.context.controlInput:=New object("action"; $data.action.id; "point"; New collection($x; $y))
return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformWidget($1)); "data"; $data)
