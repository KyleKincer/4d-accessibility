#DECLARE($action : Object) -> $result : Object
var $reply : Object
$result:=New object("status"; "rejected"; "message"; "Unsupported action")
If ($action.operation="press")
Case of
 : (($action.node="fault") & ($action.operation="press"))
  Form.panel.inner.injectError:=True
  $result:=New object("status"; "completed"; "message"; "Fault armed")
  : ($action.node="hide")
   OBJECT SET VISIBLE(*; "Left"; Not(OBJECT Get visible(*; "Left")))
   $result.status:="completed"
  : ($action.node="replace")
   EXECUTE METHOD IN SUBFORM("Left"; "AXB_Form"; $reply; "stop"; New object)
   Form.left:=New object("initialName"; "Replacement"; "title"; "Shipping")
   OBJECT SET SUBFORM(*; "Left"; "GreetingAlternate")
   $result.status:="completed"
  : ($action.node="scope")
   Form.record:=Form.record+1
   $result.status:="completed"
  : ($action.node="page")
   If (FORM Get current page=1)
    FORM GOTO PAGE(2)
   Else
    FORM GOTO PAGE(1)
   End if
   $result.status:="completed"
 End case
End if
Form.message:=$action.node+": "+$result.status
