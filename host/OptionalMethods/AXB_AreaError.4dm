// Retire only the captured area lifetime; preserve the application's handler.
var $guard; $failure : Object
$guard:=AXB_AreaGuard
$failure:=New object("ok"; False; "error"; "areaCallbackError"; "code"; Error; "method"; Error method; "line"; Error line)
ON ERR CALL($guard.previousHandler; ek local)
AXB_AreaGuard:=$guard.previousGuard
$guard.record.state:="failed"
$guard.record.failure:=$failure
If (($guard.record.starting=True) && (AXB_FormRoots#Null))
 $guard.record.context:=AXB_FormRoots[String($guard.record.window)].context
End if
If ($guard.record.context#Null)
 AXB_FormStop($guard.record.context)
End if
If (Not($guard.record.failureReported=True))
 $guard.record.failureReported:=True
 AXB_DynamicFailure($failure; $guard.record.options; "start")
End if
ABORT
