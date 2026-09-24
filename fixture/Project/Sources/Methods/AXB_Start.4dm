// Call once from On Load. The callback is developer-supplied, never agent input.
#DECLARE($poll : Object)
var $context; $token : Object
If (Value type(Form.axb)=Is object)
 AXB_Stop
End if
$token:=New shared object("active"; True; "pending"; False; "window"; Current form window; "owner"; Current process; "session"; Generate UUID)
$context:=New object("token"; $token; "poll"; $poll)
Form.axb:=$context
$context.process:=New process("AXB_Pulse"; 0; "AXB "+$token.session; $token)
