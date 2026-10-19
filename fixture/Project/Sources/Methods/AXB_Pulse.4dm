// One cooperative sleeping process per registered form; one queued callback maximum.
// A blocked/modal form cannot accumulate callbacks. No 4D form timer is used.
#DECLARE($token : Object)
var $send; $dormant; $due : Boolean
var $delay; $started : Real
$delay:=6
While ($token.active)
 // While a staged editor operation is pending, yield between real UI events
 // without adding a tenth of a second to every character.
 DELAY PROCESS(Current process; Choose($token.fast=True; 1; $delay))
 $send:=False
 // Until an assistive technology needs the form, it runs without polling.
 $dormant:=AXB Active=0
 // Describe the form again only when what it shows can have changed: describing an
 // unchanged form makes its user wait for nothing. A staged operation always continues.
 $due:=False
 If (Not($dormant) & Not($token.pending))
  // So is the backstop's check of every object, a few at a time, and a description a grid's
  // page read asked for.
  $due:=($token.fast=True) | ($token.verify=True) | ($token.again=True) | (AXB Refresh due($token.session)=1)
 End if
 Use ($token)
  If ($token.active)
   If (Window process($token.window)#$token.owner)
    $token.active:=False
   Else
    If (Not($token.pending) & $due)
     $token.pending:=True
     $send:=True
    End if
   End if
  End if
 End use
 Case of
  : ($dormant)
   $delay:=15
  : (Not($send))
   // Asking whether the form changed costs nothing; ask often, so a change is described promptly.
   $delay:=6
 End case
 If ($send)
  $started:=Tickcount
  CALL FORM($token.window; "AXB_Poll"; $token.session)
  // Start the next interval after this callback finishes. An expensive form
  // must leave time for AppKit/VoiceOver instead of polling continuously.
  While ($token.active & $token.pending)
   DELAY PROCESS(Current process; Choose($token.fast=True; 1; 6))
   If (Window process($token.window)#$token.owner)
    Use ($token)
     $token.active:=False
    End use
   End if
  End while
  // Reserve time for input/assistive clients in proportion to the last
  // callback. Small forms retain the 100 ms minimum; idle delay caps at 1 s.
  $delay:=Tickcount-$started
  If ($delay<0)
   // A wrapped clock should cause a bounded pause, never a tight loop.
   $delay:=60
  Else
   $delay:=New collection(60; New collection(6; $delay*2).max()).min()
  End if
 End if
End while
