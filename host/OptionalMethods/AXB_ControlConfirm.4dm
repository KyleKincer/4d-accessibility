#DECLARE($request : Object) -> $result : Object
var $value : Variant
var $native; $description; $node; $target : Object
var $unchanged : Boolean
var $valueType : Integer
$result:=New object("status"; "completed"; "message"; "Activation dispatched through the control's normal event path")
If (New collection("increment"; "decrement").indexOf($request.operation)>=0)
 If ($request.awaitNative=True)
  $native:=AXB_PollGuard.context.controlInputResult
  If (($native=Null) || ($native.action#$request.actionID))
   $result:=New object("status"; "rejected"; "message"; "Native adjustment timed out")
   If ((Milliseconds<$request.deadline) | (AXB_PollGuard.context.controlInputReadAt<$request.deadline))
    $result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; $request)
   End if
   return
  End if
  If (Not($native.accepted=True))
   $result:=New object("status"; "rejected"; "message"; "Control changed before native input delivery")
   return
  End if
 End if
 $description:=AXB_Discover($request.options)
 For each ($node; $description.nodes)
  If (Compare strings($node.objectName; $request.objectName; sk char codes)=0)
   $target:=$node
  End if
 End for each
 $result:=New object("status"; "rejected"; "message"; "Application did not accept the adjustment")
 If (($target#Null) && ($target.role=$request.role) && $target.adjustable && $target.enabled && $target.visible)
  // A date's slider offset can stay the same when its handler shifts the
  // range. Confirm the actual binding value, not that presentation offset.
  $value:=OBJECT Get value($request.objectName)
  $valueType:=Value type($value)
  If ($valueType#$request.previousType)
   return New object("status"; "rejected"; "message"; "Control binding type changed during adjustment")
  End if
  If ($valueType=Is date)
   $value:=$value-!1904-01-01!
  Else
   $value:=Num($value)
  End if
  If ($value#$request.previousValue)
   $result:=New object("status"; "completed"; "message"; "Control value confirmed")
  Else
   If ((Value type($target.value)=Is real) && ((($request.operation="increment") & ($target.value=$target.max)) | (($request.operation="decrement") & ($target.value=$target.min))))
    $result:=New object("status"; "completed"; "message"; "Control is at its limit")
   End if
  End if
 End if
 return
End if
If (New collection("showMenu"; "confirm"; "dismissMenu").indexOf($request.operation)>=0)
 $native:=AXB_Host("focus"; New object)
 If (AXB_ControlFocus($request.objectName) & ($native.ok=True) & ($native.comboExpanded=($request.operation="showMenu")))
  $result.message:="Native combo choice state confirmed"
 Else
  $result:=New object("status"; "rejected"; "message"; "Application did not change the combo choice state")
  If (Milliseconds<$request.deadline)
   $result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; $request)
  End if
 End if
 return
End if
If ($request.operation="focus")
 If (AXB_ControlFocus($request.objectName))
  $result.message:="Keyboard focus confirmed"
 Else
  $result:=New object("status"; "rejected"; "message"; "Application did not transfer keyboard focus")
 End if
Else
 If (New collection("checkbox"; "radio").indexOf($request.role)>=0)
  $value:=OBJECT Get value($request.objectName)
  If (Value type($value)#Is Boolean)
   If (($request.role="checkbox") && OBJECT Get three states checkbox(*; $request.objectName) && (Num($value)=2))
    $value:=2
   Else
    $value:=Num($value)#0
   End if
  End if
  // Mixed is numeric 2; checked/unchecked remain Boolean for compatibility.
  // Do not let implicit conversion make mixed and checked compare equal.
  $unchanged:=(Value type($value)=Value type($request.previousValue)) && ($value=$request.previousValue)
  If ((($request.role="checkbox") & $unchanged) | (($request.role="radio") && Not($value)))
   $result:=New object("status"; "rejected"; "message"; "Application did not accept the state change")
  Else
   $result.message:="Control state confirmed"
  End if
 End if
End if
