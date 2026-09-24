#DECLARE($action : Object) -> $result : Object
$result:=New object("status"; "rejected"; "message"; "Unsupported fixture action")
If (($action.operation="press") & (New collection("sort"; "hide"; "disable"; "replace"; "identity"; "reload"; "badkey"; "loaded").indexOf($action.node)>=0))
 AXBA_Change($action.node)
 $result:=New object("status"; "completed"; "message"; $action.node+" complete")
End if
