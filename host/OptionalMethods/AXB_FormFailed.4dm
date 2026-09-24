// Called in the root form. Never stop a newer registration on its behalf.
#DECLARE($context : Object; $failure : Object)
var $current; $guard : Object
$current:=AXB_FormContext
If ($current=Null)
 return
End if
If ($current.session#$context.session)
 return
End if
Form.axbError:=$failure.error
Form.axbFailure:=$failure
AXB_FormStop($context)
$guard:=AXB_PollGuard
If (($guard#Null) & (Value type($guard)=Is object))
 If ($guard.context.session=$context.session)
  ON ERR CALL($guard.previousHandler; ek local)
 End if
End if
If ((Value type($context.onError)=Is object) & ($context.onError#Null))
 $context.onError.call(Null; $failure)
End if
