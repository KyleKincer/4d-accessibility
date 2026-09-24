// Call from On Unload and fatal adapter errors. Never changes the form timer.
var $context; $token : Object
$context:=AXB_CoreWindows[String(Current form window)]
If ($context#Null)
 $token:=$context.token
 Use ($token)
  $token.active:=False
 End use
 AXB Detach($token.session)
 OB REMOVE(AXB_CoreWindows; String(Current form window))
 If ((New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
  If (New collection(Form.axb).indexOf($context)=0)
   OB REMOVE(Form; "axb")
  End if
 End if
End if
