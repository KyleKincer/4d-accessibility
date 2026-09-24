#DECLARE($action : Object) -> $result : Object
$result:=New object("status"; "rejected"; "message"; "Action unavailable")
Case of
 : (($action.node="name") & ($action.operation="setValue"))
  If ((Value type($action.value)=Is text) & (Length($action.value)>0) & (Length($action.value)<=40))
   Form.name:=$action.value
   Form.acceptedName:=Form.name
   $result:=New object("status"; "completed"; "message"; "Name accepted")
  Else
   Form.name:=Form.acceptedName
   $result.message:="Use 1 to 40 characters"
  End if
 : (($action.node="greet") & ($action.operation="press"))
  Form.calls:=Form.calls+1
  $result:=New object("status"; "completed"; "message"; "Hello, "+Form.acceptedName)
 : (($action.node="close") & ($action.operation="press"))
  AXBD_CloseAction
  $result:=New object("status"; "completed"; "message"; "Closing")
  If (Form.config.axClose="accept")
   ACCEPT
  Else
   CANCEL
  End if
End case
Form.message:=$result.message
AXBD_State(Form)
