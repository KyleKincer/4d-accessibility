// Call once from On Load. The callback is developer-supplied, never agent input.
#DECLARE($poll : Object) -> $token : Object
var $context; $reply : Object
If (AXB_CoreWindows=Null)
 AXB_CoreWindows:=New object
End if
If (AXB_CoreWindows[String(Current form window)]#Null)
 AXB_Stop
End if
$reply:=JSON Parse(AXB Open(Current form window))
If (Not($reply.ok=True))
 $token:=New shared object("active"; False; "error"; $reply.error)
 return
End if
$token:=New shared object("active"; True; "pending"; False; "window"; Current form window; "owner"; Current process; "session"; $reply.session)
$context:=New object("token"; $token; "poll"; $poll)
AXB_CoreWindows[String(Current form window)]:=$context
// Compatibility alias for low-level integrations. Window ownership lives in
// the process registry, since two dialogs can share the same business object.
If ((New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
 Form.axb:=$context
End if
$context.process:=New process("AXB_Pulse"; 0; "AXB "+$token.session; $token)
