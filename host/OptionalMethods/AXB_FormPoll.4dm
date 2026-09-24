// Scope the error handler to this callback, including nested subform callbacks.
// Capture the root data object because Form changes while entering a subform.
var $guard; $context : Object
$context:=AXB_FormContext
If ($context=Null)
 return
End if
$guard:=New object("form"; Form; "context"; $context; "window"; Current form window; "previousHandler"; Method called on error(ek local); "previousGuard"; AXB_PollGuard)
AXB_PollGuard:=$guard
ON ERR CALL("AXB_FormError"; ek local)
AXB_FormExchange
ON ERR CALL($guard.previousHandler; ek local)
AXB_PollGuard:=$guard.previousGuard
