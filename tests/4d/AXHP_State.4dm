var $state; $beforeA; $beforeB; $afterA; $afterB; $beforeGroup; $afterGroup; $groupSentinelBefore; $groupSentinelAfter : Object
var $savedOK; $rows; $cols; $column; $row; $left; $top; $right; $bottom; $scroll; $lastRow : Integer
var $hierarchical : Boolean
var $hitX; $hitY : Real
var $item; $address : Object
var $fault : Text
ARRAY POINTER($hierarchy; 0)
ARRAY BOOLEAN($selection; 0)
$state:=New object("command"; Form.command; "runId"; Form.runId; "compiled"; Is compiled mode; "events"; Form.events; "focus"; OBJECT Get name(Object with focus))
$beforeA:=AXHP_ListState("TreeA")
$beforeB:=AXHP_ListState("TreeB")
$savedOK:=OK
OK:=0
$groupSentinelBefore:=AXHP_GroupedSentinel("Grouped")
$beforeGroup:=AXHP_GroupedRead("Grouped")
$groupSentinelAfter:=AXHP_GroupedSentinel("Grouped")
$state.topology:=AXHP_Topology(Form.tree; New collection)
$state.okPreserved:=OK=0
OK:=$savedOK
$afterA:=AXHP_ListState("TreeA")
$afterB:=AXHP_ListState("TreeB")
$afterGroup:=AXHP_GroupedRead("Grouped")
$state.beforeGroup:=$beforeGroup
$state.afterGroup:=$afterGroup
$state.groupSentinelBefore:=$groupSentinelBefore
$state.groupSentinelAfter:=$groupSentinelAfter
$state.beforeA:=$beforeA
$state.beforeB:=$beforeB
$state.afterA:=$afterA
$state.afterB:=$afterB
$state.focusAfter:=OBJECT Get name(Object with focus)
LISTBOX GET HIERARCHY(*; "Grouped"; $hierarchical; $hierarchy)
$state.grouped:=New object("hierarchical"; $hierarchical; "levels"; Size of array($hierarchy); "rows"; LISTBOX Get number of rows(*; "Grouped"); "coordinates"; New collection)
$lastRow:=$state.grouped.rows
If ($lastRow>12)
 $lastRow:=12
End if
For ($row; 1; $lastRow)
 For ($column; 1; 5)
  LISTBOX GET CELL COORDINATES(*; "Grouped"; $column; $row; $left; $top; $right; $bottom)
  $address:=New object("row"; $row; "column"; $column; "frame"; New collection($left; $top; $right; $bottom))
  If (($right>$left) & ($bottom>$top))
   $hitX:=($left+$right)/2
   $hitY:=($top+$bottom)/2
   LISTBOX GET CELL POSITION(*; "Grouped"; $hitX; $hitY; $cols; $rows)
   $address.hit:=New collection($cols; $rows)
   If (($cols>0) & ($rows>0))
    LISTBOX GET CELL COORDINATES(*; "Grouped"; $cols; $rows; $left; $top; $right; $bottom)
    $address.roundTrip:=New collection($left; $top; $right; $bottom)
   End if
  End if
  $state.grouped.coordinates.push($address)
 End for
End for
$state.grouped.physicalLeafHits:=New collection
If ($state.grouped.rows>0)
 LISTBOX GET CELL COORDINATES(*; "Grouped"; 3; 1; $left; $top; $right; $bottom)
 If (($right>$left) & ($bottom>$top))
  $hitY:=($top+$bottom)/2
  For each ($hitX; New collection(100; 260; 475))
   LISTBOX GET CELL POSITION(*; "Grouped"; $hitX; $hitY; $cols; $rows)
   $address:=New object("point"; New collection($hitX; $hitY); "hit"; New collection($cols; $rows))
   If (($cols>0) & ($rows>0))
    LISTBOX GET CELL COORDINATES(*; "Grouped"; $cols; $rows; $left; $top; $right; $bottom)
    $address.frame:=New collection($left; $top; $right; $bottom)
   End if
   $state.grouped.physicalLeafHits.push($address)
  End for each
 End if
End if
// Only a synthetic baseline point, not discovered disclosure geometry.
If ($state.grouped.rows>0)
 LISTBOX GET CELL COORDINATES(*; "Grouped"; 1; 1; $left; $top; $right; $bottom)
 $state.grouped.firstBreakFrame:=New collection($left; $top; $right; $bottom)
 If (($right>$left) & ($bottom>$top))
  $hitX:=$left+8
  $hitY:=($top+$bottom)/2
  LISTBOX GET CELL POSITION(*; "Grouped"; $hitX; $hitY; $cols; $rows)
  $state.grouped.disclosurePointHit:=New collection($cols; $rows)
  CONVERT COORDINATES($hitX; $hitY; XY Current form; XY Screen)
  $state.grouped.disclosureTestPoint:=New collection($hitX; $hitY)
 End if
End if
$state.grouped.selected:=New collection
ARRAY TO COLLECTION($state.grouped.selected; AXHP_Selection)
// Pure host capture, without a production accessibility package or UI input.
var $binding; $capture : Object
var $controlPointer : Pointer
var $modelKeys; $modelHierarchy : Collection
$modelKeys:=New collection
For ($row; 1; Size of array(AXHP_Key))
 $modelKeys.push(String(AXHP_Key{$row}; "&xml"))
End for
$controlPointer:=LISTBOX Get array(*; "Grouped"; lk control array)
$binding:=New object("count"; Size of array(AXHP_Key); "keys"; $modelKeys; "controlPointer"; $controlPointer)
$modelHierarchy:=New collection
For ($row; 1; Size of array($hierarchy))
 $modelHierarchy.push($hierarchy{$row})
End for
$binding.hierarchy:=$modelHierarchy
$binding.coordinateOffset:=Choose(Size of array($hierarchy)=1; 0; Size of array($hierarchy)-1)
$binding.keyPointer:=->AXHP_Key
$binding.keyType:=Type(AXHP_Key)
$binding.selectionPointer:=->AXHP_Selection
If (Not(Is nil pointer(OBJECT Get pointer(Object named; "RowKey"))))
 $binding.keyObjectName:="RowKey"
End if
$state.modelSentinelBefore:=AXHP_GroupedSentinel("Grouped")
$savedOK:=OK
OK:=0
$capture:=AXB_OutlineCapture("Grouped"; $binding)
$state.capturePreservesOK:=OK=0
OK:=$savedOK
$state.capture:=$capture
OB REMOVE($state.capture; "hierarchy")
If (Form.command.operation="groupFaultBinding")
 $state.bindingFaults:=New collection
 For each ($fault; New collection("key"; "keyType"; "hierarchy"; "selection"; "missingHierarchy"; "missingKey"; "missingSelection"; "missingControl"; "controlType"; "controlNull"))
  $state.bindingFaults.push(AXHP_CaptureFault($binding; $fault))
 End for each
End if
If ($capture.ok)
 Form.outlinePrevious:=AXB_OutlineRows($capture.snapshot; Form.outlinePrevious)
 $state.outline:=Form.outlinePrevious
End if
$state.modelSentinelAfter:=AXHP_GroupedSentinel("Grouped")
// Native probe result, when installed.
File("/RESOURCES/state.json").setText(JSON Stringify($state))
