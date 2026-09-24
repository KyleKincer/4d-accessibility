// Normalize application receipts before sending them across the native boundary.
#DECLARE($candidate : Object) -> $result : Object
$result:=New object("status"; "rejected"; "message"; "Handler returned an invalid completion result")
If ($candidate=Null)
 return
End if
If (New collection("completed"; "rejected").indexOf($candidate.status)<0)
 return
End if
$result.status:=$candidate.status
If (Value type($candidate.message)=Is text)
 $result.message:=Substring($candidate.message; 1; 512)
Else
 $result.message:="Action "+$result.status
End if
