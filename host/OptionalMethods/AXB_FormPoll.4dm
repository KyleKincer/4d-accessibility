// Scope the error handler to this callback, including nested subform callbacks.
// Capture the root data object because Form changes while entering a subform.
var $guard; $context; $registry : Object
var $table : Pointer
var $tableNum; $window : Integer
$context:=AXB_FormContext
If ($context=Null)
 $window:=Current form window
 If (($window#0) && (AXB_FormRoots#Null) && (AXB_FormRoots[String($window)]#Null))
  $registry:=AXB_FormRoots[String($window)]
  If (($registry.context#Null) && ($registry.context.watched=True))
   AXB_FormStop($registry.context)
   AXB_WatchWindow($window)
  End if
 End if
 return
End if
If ($context.watched=True)
 $window:=Current form window
 $table:=Current form table
 $tableNum:=0
 If (Not(Is nil pointer($table)))
  $tableNum:=Table($table)
 End if
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
