// Call from On Unload and fatal adapter errors. Never changes the form timer.
var $context; $token : Object
If (Value type(Form.axb)=Is object)
 $context:=Form.axb
 $token:=$context.token
 Use ($token)
  $token.active:=False
 End use
 AXB Detach($token.session)
 OB REMOVE(Form; "axb")
End if
