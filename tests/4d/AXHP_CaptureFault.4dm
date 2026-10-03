// Deterministic caller-binding faults. Restore backing data before returning.
#DECLARE($binding : Object; $fault : Text) -> $result : Object
var $candidate; $before; $after; $capture : Object
var $savedKey; $savedOK : Integer
$candidate:=OB Copy($binding)
$savedKey:=AXHP_Key{1}
Case of
 : ($fault="key")
  AXHP_Key{1}:=$savedKey+1000
 : ($fault="keyType")
  $candidate.keyType:=Text array
 : ($fault="hierarchy")
  $candidate.hierarchy[0]:=->AXHP_Subgroup
 : ($fault="selection")
  $candidate.selectionPointer:=->AXHP_Control
 : ($fault="missingHierarchy")
  OB REMOVE($candidate; "hierarchy")
 : ($fault="missingKey")
  OB REMOVE($candidate; "keyPointer")
 : ($fault="missingSelection")
  OB REMOVE($candidate; "selectionPointer")
 : ($fault="missingControl")
  OB REMOVE($candidate; "controlPointer")
 : ($fault="controlType")
  $candidate.controlPointer:="wrong type"
 : ($fault="controlNull")
  $candidate.controlPointer:=Null
End case
$before:=AXHP_GroupedSentinel("Grouped")
$savedOK:=OK
OK:=0
$capture:=AXB_OutlineCapture("Grouped"; $candidate)
$result:=New object("fault"; $fault; "rejected"; Not($capture.ok); "preservesOK"; OK=0)
OK:=$savedOK
$after:=AXHP_GroupedSentinel("Grouped")
$result.preservesState:=JSON Stringify($before)=JSON Stringify($after)
AXHP_Key{1}:=$savedKey
