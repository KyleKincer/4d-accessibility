// Revalidate the owning list and keyed row after its native scroll has painted.
#DECLARE($data : Object) -> $result : Object
var $reply; $descriptor : Object
var $row; $column : Text
$result:=New object("status"; "rejected"; "message"; "List subform changed before reveal completion")
If ((Current form window#Frontmost window) | (Milliseconds>=$data.deadline))
 return
End if
$reply:=AXB_ListSubform("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$descriptor:=$data.state.descriptor
$row:=$data.action.value.row
$column:=$data.action.value.column
If (($descriptor.generation#$data.generation) | Not(OB Is defined($data.state.positions; $row)))
 return
End if
If (($descriptor.frames[$row]#Null) && ($descriptor.frames[$row][$column]#Null))
 return New object("status"; "completed"; "message"; "List subform cell is visible")
End if
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformReveal($1)); "data"; $data)
