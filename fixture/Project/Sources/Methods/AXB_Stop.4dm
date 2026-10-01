// A captured lifetime can retire after its form context has gone away.
// No argument preserves the existing application-facing call.
#DECLARE($window : Integer; $session : Text)
var $context; $token; $data : Object
If ($window=0)
 $window:=Current form window
End if
$context:=AXB_CoreWindows[String($window)]
If ($context#Null)
 $token:=$context.token
 If (($session#"") && ($token.session#$session))
  return
 End if
 Use ($token)
  $token.active:=False
 End use
 AXB Detach($token.session)
 OB REMOVE(AXB_CoreWindows; String($window))
 $data:=$context.data
 If (($data#Null) && (New collection(4D.Object).indexOf(OB Class($data))=0) && Not(OB Is shared($data)))
  If (New collection($data.axb).indexOf($context)=0)
   OB REMOVE($data; "axb")
  End if
 End if
End if
