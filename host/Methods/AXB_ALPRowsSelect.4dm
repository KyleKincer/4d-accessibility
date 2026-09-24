// Revalidate the current vendor state, not just the action's older snapshot.
#DECLARE($area : Integer; $objectName : Text; $keys : Pointer; $options : Object; $action : Object) -> $result : Object
var $nodes : Collection
var $node; $allowed : Object
var $rowID : Text
$result:=New object("status"; "rejected"; "message"; "Grid action rejected")
If (($action.operation#"selectRows") | (Compare strings($action.node; $options.id; sk char codes)#0) | (Value type($action.value)#Is collection))
 return
End if
$nodes:=AXB_ALPRows($area; $objectName; $keys; $options)
If (Not($nodes[0].enabled) | Not($nodes[0].visible))
 $result.message:=$nodes[0].label
 return
End if
If (($action.value.length>100) | (($action.value.length>1) & (AL_GetAreaLongProperty($area; ALP_Area_SelMultiple)=0)))
 $result.message:="Selection count exceeds the grid's supported selection mode"
 return
End if
$allowed:=New object
For each ($node; $nodes)
 If (($node.role="row") & $node.enabled & $node.visible)
  $allowed[$node.id]:=True
 End if
End for each
For each ($rowID; $action.value)
 If (Not(OB Is defined($allowed; $rowID)))
  $result.message:="Row is no longer available for selection"
  return
 End if
End for each
$result:=AXB_ALPSelect($area; $keys; $options.id; $action)
