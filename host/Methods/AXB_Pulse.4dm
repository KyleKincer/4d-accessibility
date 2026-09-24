// One cooperative sleeping process per registered form; one queued callback maximum.
// A blocked/modal form cannot accumulate callbacks. No 4D form timer is used.
#DECLARE($token : Object)
var $send : Boolean
While ($token.active)
 // While a staged editor operation is pending, yield between real UI events
 // without adding a tenth of a second to every character.
 DELAY PROCESS(Current process; Choose($token.fast=True; 1; 6))
 $send:=False
 Use ($token)
  If ($token.active)
   If (Window process($token.window)#$token.owner)
    $token.active:=False
   Else
    If (Not($token.pending))
     $token.pending:=True
     $send:=True
    End if
   End if
  End if
 End use
 If ($send)
  CALL FORM($token.window; "AXB_Poll"; $token.session)
 End if
End while
