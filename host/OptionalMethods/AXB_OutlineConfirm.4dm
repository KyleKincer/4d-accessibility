// AXB_View has already refreshed the current configuration in this same
// form. Never redescribe using the options retained before invocation.
#DECLARE($data : Object) -> $result : Object
var $target; $focus : Object
var $focusPointer; $retainedFocus : Pointer
var $focusID : Text
var $start; $end : Integer
$result:=New object("status"; "rejected"; "message"; "Disclosure controller or group changed before completion")
If (Not($data.invoked=True) || Not($data.state.valid=True) || ($data.state.setExpanded=Null) || (New collection($data.controller).indexOf($data.state.setExpanded)#0) || (Current form window#Frontmost window))
 return
End if
$target:=AXB_OutlineTarget($data.state; $data.action; False)
If (Not($target.ok))
 return
End if
If ((OBJECT Get name(Object with focus)#$data.focusName) | (Is editing text#$data.editing))
 return New object("status"; "rejected"; "message"; "Native focus changed during disclosure")
End if
$focusPointer:=OBJECT Get pointer(Object with focus)
$retainedFocus:=$data.focusPointer
$focus:=AXB_Focus
$focusID:=""
If ($focus.node#Null)
 $focusID:=$focus.node.id
End if
If (($focusPointer#$retainedFocus) | (Compare strings($focusID; $data.focusID; sk char codes)#0))
 return New object("status"; "rejected"; "message"; "Native focus owner changed during disclosure")
End if
If ($data.editing)
 If (Not(AXB_ControlFocus($data.focusName)))
  return
 End if
 GET HIGHLIGHT(*; $data.focusName; $start; $end)
 If ((Compare strings(Get edited text; $data.editor.value; sk char codes)#0) | ($start#$data.editor.start) | ($end#$data.editor.end))
  return New object("status"; "rejected"; "message"; "Native editor changed during disclosure")
 End if
End if
If ($target.expanded=$data.action.value.expanded)
 return New object("status"; "completed"; "message"; "Group disclosure confirmed")
End if
If (Milliseconds>=$data.deadline)
 return New object("status"; "rejected"; "message"; "Application did not confirm group disclosure")
End if
return New object("status"; "pending"; "confirm"; Formula(AXB_OutlineConfirm($1)); "data"; $data)
