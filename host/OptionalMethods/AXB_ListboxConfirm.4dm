// Wait for native bindings, call shared logic once, then confirm its result.
#DECLARE($confirmation : Object) -> $result : Object
var $snapshot : Object
var $key : Text
var $matches : Boolean
$result:=New object("status"; "rejected"; "message"; "Native list box did not confirm selection")
If ((Milliseconds>=$confirmation.deadline) | (Current form window#Frontmost window))
 return
End if
$snapshot:=AXB_Listbox($confirmation.options)
If (Not($snapshot.ok=True) | OB Is defined($snapshot; "error") | ($snapshot.nodes.length=0))
 return
End if
If (Not($snapshot.nodes[0].enabled & $snapshot.nodes[0].visible))
 return
End if
$matches:=$snapshot.selectedIDs.length=$confirmation.keys.length
For each ($key; $confirmation.keys)
 $matches:=$matches & (AXB_KeyIndex($snapshot.selectedIDs; $key)>=0)
End for each
If (Not($matches) & ($confirmation.hookCalled=True))
 $result.message:="Application changed the requested selection"
 return
End if
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_ListboxConfirm($1)); "data"; $confirmation)
If (Not($matches))
 return
End if
If (Not($confirmation.hookCalled=True))
 $confirmation.hookCalled:=True
 If (OB Is defined($confirmation.options; "onSelection"))
  $confirmation.options.onSelection.call()
  // A later poll revalidates the owning form and the handler's selection.
  return
 End if
End if
$result:=New object("status"; "completed"; "message"; String($snapshot.selectedIDs.length)+" rows selected")
