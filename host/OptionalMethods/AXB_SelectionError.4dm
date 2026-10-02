// Worker errors report through its private reply, never the form's handler.
var $failure : Text
$failure:=String(Error)+": "+Error method+": "+String(Error line)
ON ERR CALL("")
If (AXB_SelectionWorkerReply.highlight#"")
 CLEAR SET(AXB_SelectionWorkerReply.highlight)
End if
Use (AXB_SelectionWorkerReply)
 AXB_SelectionWorkerReply.highlight:=""
 AXB_SelectionWorkerReply.error:=$failure
 AXB_SelectionWorkerReply.done:=True
End use
ABORT
