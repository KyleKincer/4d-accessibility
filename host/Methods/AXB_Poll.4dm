// CALL FORM executes this method in the target form's owning process.
#DECLARE($session : Text; $seq : Integer)
var $context; $token : Object
$context:=AXB_CoreWindows[String(Current form window)]
If ($context=Null)
 return
End if
$token:=$context.token
// Protect against queued callbacks reaching a replacement form/window or stale retries.
If (($token.session#$session) | Not($token.active) | ($token.window#Current form window) | ($token.owner#Current process))
 return
End if
If (($seq#0) && (Num($token.seq)#$seq))
 return
End if
$context.poll.call()
// Use the captured token: the callback may have closed or replaced its form.
Use ($token)
 $token.pending:=False
End use
