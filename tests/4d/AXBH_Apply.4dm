#DECLARE($node : Text; $operation : Text; $value : Variant) -> $result : Object
var $reply : Object
$result:=New object("status"; "rejected"; "message"; "Unsupported action")
Case of
 : (($node="name") & ($operation="setValue"))
  If (Value type($value)=Is text)
   If ((Length($value)>0) & (Length($value)<=40))
    Form.name:=$value
    Form.validName:=$value
    $result:=New object("status"; "completed"; "message"; "Name accepted")
   Else
    Form.name:=Form.validName
    $result.message:="Name must contain 1 to 40 characters"
   End if
  End if
 : (($node="allowed") & (($operation="press") | ($operation="humanChange")))
  If ($operation="press")
   Form.allowed:=Not(Form.allowed)
  End if
  OBJECT SET ENABLED(*; "Submit"; Form.allowed)
  $result:=New object("status"; "completed"; "message"; "Permission changed")
 : (($node="submit") & ($operation="press"))
  If (Form.allowed & OBJECT Get enabled(*; "Submit"))
   Form.count:=Form.count+1
   $result:=New object("status"; "completed"; "message"; "Submissions: "+String(Form.count))
  End if
 : (($node="hide") & ($operation="press"))
  OBJECT SET VISIBLE(*; "Name"; Not(OBJECT Get visible(*; "Name")))
  $result:=New object("status"; "completed"; "message"; "Visibility changed")
 : (($node="restart") & ($operation="press"))
  $reply:=AXB_Host("stop"; New object)
  $reply:=AXB_Host("start"; New object("poll"; Formula(AXBH_Poll)))
  If ($reply.ok=True)
   Form.session:=$reply.session
   Form.revision:=0
   Form.lastState:=""
   OB REMOVE(Form; "receipt")
   $result:=New object("status"; "completed"; "message"; "Bridge restarted")
  End if
 : (($node="close") & ($operation="press"))
  $reply:=AXB_Host("stop"; New object)
  Form.session:=""
  CANCEL
  $result:=New object("status"; "completed"; "message"; "Closing")
End case
Form.message:=$result.message
