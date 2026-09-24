// Activate through 4D's keyboard handling after host focus handlers have run.
#DECLARE($request : Object) -> $result : Object
var $native : Object
$result:=New object("status"; "rejected"; "message"; "Control lost keyboard focus before activation")
If ((Current form window#Frontmost window) | Not(AXB_ControlFocus($request.objectName)))
 return
End if
If (Not(OBJECT Get enabled(*; $request.objectName)) | Not(OBJECT Get visible(*; $request.objectName)))
 return
End if
Case of
 : (New collection("increment"; "decrement").indexOf($request.operation)>=0)
  If ((OBJECT Get type(*; $request.objectName)#Object type ruler) | Not(OBJECT Get enterable(*; $request.objectName)))
   return
  End if
  POST KEY(Choose($request.operation="increment"; Right arrow key; Left arrow key); 0; Current process)
 : ($request.operation="showMenu")
  If (OBJECT Get type(*; $request.objectName)#Object type combobox)
   return
  End if
  POST KEY(Down arrow key; 0; Current process)
 : (New collection("confirm"; "dismissMenu").indexOf($request.operation)>=0)
  If (OBJECT Get type(*; $request.objectName)#Object type combobox)
   return
  End if
  $native:=AXB_Host("focus"; New object)
  If ($native.comboExpanded#True)
   $result.message:="Combo choices are already closed"
   return
  End if
  POST KEY(Choose($request.operation="dismissMenu"; 27; 13); 0; Current process)
 Else
  POST KEY(32; 0; Current process)
End case
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; $request)
