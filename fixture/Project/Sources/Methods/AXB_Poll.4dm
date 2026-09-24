// CALL FORM executes this method in the target form's owning process.
#DECLARE($session : Text)
var $context; $token : Object
If (Value type(Form.axb)#Is object)
 return
End if
$context:=Form.axb
$token:=$context.token
// Protect against queued callbacks reaching a replacement form/window.
If (($token.session#$session) | Not($token.active) | ($token.window#Current form window) | ($token.owner#Current process))
 return
End if
$context.poll.call()
// Use the captured token: the callback may have closed or replaced its form.
Use ($token)
 $token.pending:=False
End use
