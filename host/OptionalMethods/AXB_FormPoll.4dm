// Scope the error handler to this callback, including nested subform callbacks.
// Capture the root data object because Form changes while entering a subform.
var $guard; $context : Object
var $table : Pointer
var $tableNum; $window : Integer
$context:=AXB_FormContext
If ($context=Null)
 return
End if
If ($context.watched=True)
 $window:=Current form window
 $table:=Current form table
 $tableNum:=Choose(Is nil pointer($table); 0; Table($table))
 If (($window#$context.watchWindow) | ($tableNum#$context.watchTable) | (Current form name#$context.watchForm) | (New collection($context.watchFormObj).indexOf(Form)#0))
  AXB_FormStop($context)
  If ($window#0)
   AXB_WatchWindow($window)
  End if
  return
 End if
End if
$guard:=New object("form"; Form; "context"; $context; "window"; Current form window; "previousHandler"; Method called on error(ek local); "previousGuard"; AXB_PollGuard)
AXB_PollGuard:=$guard
ON ERR CALL("AXB_FormError"; ek local)
AXB_FormExchange
ON ERR CALL($guard.previousHandler; ek local)
AXB_PollGuard:=$guard.previousGuard
