// Resolve keys against a fresh snapshot before making any selection change.
// 4D updates collection/entity selected-items bindings on the next event cycle.
#DECLARE($options : Object; $action : Object) -> $result : Object
var $snapshot; $node; $allowed; $confirmation : Object
var $positions : Collection
var $id : Text
var $row : Integer
$result:=New object("status"; "rejected"; "message"; "List box selection rejected")
If (Current form window#Frontmost window)
 return
End if
If (($action.operation#"selectRows") | (Compare strings($action.node; $options.id; sk char codes)#0) | (Value type($action.value)#Is collection) | ($action.value=Null))
 return
End if
$snapshot:=AXB_Listbox($options)
If (Not($snapshot.ok=True) | OB Is defined($snapshot; "error") | ($snapshot.nodes.length=0))
 return
End if
If (Not($snapshot.nodes[0].enabled & $snapshot.nodes[0].visible))
 return
End if
If (($action.value.length>100) | (($snapshot.selectionMode=1) & ($action.value.length>1)))
 return
End if
$allowed:=New object
For each ($node; $snapshot.nodes)
 If (($node.role="row") & $node.enabled & $node.visible)
  $allowed[$node.id]:=True
 End if
End for each
$positions:=New collection
For each ($id; $action.value)
 If (Not(OB Is defined($allowed; $id)) | ($positions.indexOf($snapshot.positions[$id])>=0))
  return
 End if
 $positions.push($snapshot.positions[$id])
End for each
If (OB Is defined($options; "onSelection"))
 If ((Value type($options.onSelection)#Is object) | ($options.onSelection=Null))
  return
 End if
 If (Not(OB Instance of($options.onSelection; 4D.Function)))
  return
 End if
End if
LISTBOX SELECT ROW(*; $options.objectName; 0; lk remove from selection)
For each ($row; $positions)
 LISTBOX SELECT ROW(*; $options.objectName; $row; lk add to selection)
End for each
$confirmation:=New object("options"; $options; "keys"; $action.value; "deadline"; Milliseconds+2000; "hookCalled"; False)
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_ListboxConfirm($1)); "data"; $confirmation)
