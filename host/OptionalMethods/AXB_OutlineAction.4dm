// Disclosure requires explicit application intent. No editor, scrolling, header
// activation or object handler is synthesized here. A leaf is selected from the
// keyboard, as a user would, so the list box's own events run.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $action; $target; $data; $callback; $focus : Object
var $focusPointer : Pointer
var $focusName : Text
var $start; $end : Integer
ARRAY TEXT($parts; 0)
$result:=New object("status"; "rejected"; "message"; "Grouped grid action is unavailable")
If (($operation#"apply") | (Current form window#Frontmost window))
 return
End if
If (($request.action=Null) || (Value type($request.action)#Is object))
 return
End if
$action:=$request.action
If (($action.operation="gridSelect") && ($action.node=$options.id) && OBJECT Get enabled(*; $options.objectName))
 return AXB_OutlineSelect(New object("state"; $state; "options"; $options; "action"; $action; "start"; True))
End if
If (($action.node#$options.id) || Not(OBJECT Get enabled(*; $options.objectName)) || ($options.setExpanded=Null) || (New collection($options.setExpanded).indexOf($state.setExpanded)#0))
 return
End if
$target:=AXB_OutlineTarget($state; $action; True)
If (Not($target.ok))
 return New object("status"; "rejected"; "message"; $target.message)
End if
If ($target.expanded=$action.value.expanded)
 return New object("status"; "completed"; "message"; "Group already has the requested disclosure state")
End if
$focusName:=OBJECT Get name(Object with focus)
$focusPointer:=OBJECT Get pointer(Object with focus)
$focus:=AXB_Focus
If (($focusName#"") & ($focus.node=Null))
 return New object("status"; "rejected"; "message"; "Native focus ownership is unavailable for disclosure")
End if
If (Is editing text)
 // Resolve an unrelated local editor through the existing exact-frame focus
 // guard. Listbox parts and ambiguous repeated/subform ownership reject.
 LISTBOX GET OBJECTS(*; $options.objectName; $parts)
 If (($focusName=$options.objectName) | (Find in array($parts; $focusName)>0) | Not(AXB_ControlFocus($focusName)))
  return New object("status"; "rejected"; "message"; "Finish native editing before changing this group")
 End if
End if
$data:=New object("state"; $state; "action"; $action; "controller"; $state.setExpanded; "objectName"; $options.objectName; "focusName"; $focusName; "editing"; Is editing text; "invoked"; True)
$data.focusPointer:=$focusPointer
$data.focusID:=""
If ($focus.node#Null)
 $data.focusID:=$focus.node.id
End if
If ($data.editing)
 GET HIGHLIGHT(*; $focusName; $start; $end)
 $data.editor:=New object("value"; Get edited text; "start"; $start; "end"; $end)
End if
// The Formula receives a new object containing only provider-resolved data.
// Mark invocation first; no confirmation path calls application code again.
$callback:=New object("objectName"; $options.objectName; "backingRow"; $target.backingRow; "breakLevel"; $target.breakLevel; "expanded"; $action.value.expanded; "actionID"; $action.id)
$data.controller.call(Null; $callback)
$data.deadline:=Milliseconds+2000
return New object("status"; "pending"; "confirm"; Formula(AXB_OutlineConfirm($1)); "data"; $data)
