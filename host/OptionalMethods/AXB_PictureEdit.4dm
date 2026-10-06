// Run an editable picture's requested edit through 4D's standard action, as
// Cut, Copy, Paste and Delete do from the keyboard. GOTO OBJECT applies after
// its event, so the edit waits until the picture actually has focus.
#DECLARE($request : Object) -> $result : Object
If (OBJECT Get name(Object with focus)#$request.objectName)
 If (Milliseconds<$request.deadline)
  return New object("status"; "pending"; "confirm"; Formula(AXB_PictureEdit($1)); "data"; $request)
 End if
 return New object("status"; "rejected"; "message"; "Picture did not receive focus")
End if
Case of
 : ($request.edit="cut")
  INVOKE ACTION(ak cut)
 : ($request.edit="copy")
  INVOKE ACTION(ak copy)
 : ($request.edit="paste")
  INVOKE ACTION(ak paste)
 : ($request.edit="clear")
  INVOKE ACTION(ak clear)
End case
$result:=New object("status"; "completed"; "message"; "Picture edited through its standard action")
