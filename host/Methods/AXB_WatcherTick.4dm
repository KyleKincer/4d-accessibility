// Worker entrypoint invoked by the native plugin watcher when accessibility is active.
// Scans open 4D windows and attaches sessions via CALL FORM without requiring %AXB Area.
#DECLARE($reason : Text)
var $status; $winState : Object
var $raw : Text
var $index; $win : Integer
If (AXB Active#1)
 $raw:=AXB Watcher("deactivate"; 0)
 KILL WORKER
 return
End if
$raw:=AXB Watcher("status"; 0)
If ($raw="")
 KILL WORKER
 return
End if
$status:=JSON Parse($raw)
If (($status=Null) || (Value type($status)#Is object) || ($status.stopping=True))
 KILL WORKER
 return
End if
$raw:=AXB Watcher("activate"; 0)
ARRAY LONGINT($windows; 0)
WINDOW LIST($windows; *)
For ($index; 1; Size of array($windows))
 $win:=$windows{$index}
 If ($win#0)
  $raw:=AXB Watcher("hasWindow"; $win)
  If ($raw#"")
   $winState:=JSON Parse($raw)
   If (($winState#Null) && (Value type($winState)=Is object))
    If ($winState.stopping=True)
     KILL WORKER
     return
    End if
    If ($winState.hasSession#True)
     CALL FORM($win; Formula(AXB_WatchWindow($1)); $win)
    End if
   End if
  End if
 End if
End for
