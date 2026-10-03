var $state; $beforeA; $beforeB; $afterA; $afterB : Object
var $savedOK; $rows; $cols; $column; $row; $left; $top; $right; $bottom; $scroll : Integer
var $hierarchical : Boolean
var $hitX; $hitY : Real
var $item; $address : Object
ARRAY POINTER($hierarchy; 0)
ARRAY BOOLEAN($selection; 0)
$state:=New object("command"; Form.command; "runId"; Form.runId; "compiled"; Is compiled mode; "events"; Form.events; "focus"; OBJECT Get name(Object with focus))
$beforeA:=AXHP_ListState("TreeA")
$beforeB:=AXHP_ListState("TreeB")
$savedOK:=OK
OK:=0
$state.topology:=AXHP_Topology(Form.tree; New collection)
$state.okPreserved:=OK=0
OK:=$savedOK
$afterA:=AXHP_ListState("TreeA")
$afterB:=AXHP_ListState("TreeB")
$state.beforeA:=$beforeA
$state.beforeB:=$beforeB
$state.afterA:=$afterA
$state.afterB:=$afterB
$state.focusAfter:=OBJECT Get name(Object with focus)
LISTBOX GET HIERARCHY(*; "Grouped"; $hierarchical; $hierarchy)
$state.grouped:=New object("hierarchical"; $hierarchical; "levels"; Size of array($hierarchy); "rows"; LISTBOX Get number of rows(*; "Grouped"); "coordinates"; New collection)
For ($row; 1; 12)
 For ($column; 1; 5)
  LISTBOX GET CELL COORDINATES(*; "Grouped"; $column; $row; $left; $top; $right; $bottom)
  $address:=New object("row"; $row; "column"; $column; "frame"; New collection($left; $top; $right; $bottom))
  $hitX:=($left+$right)/2
  $hitY:=($top+$bottom)/2
  LISTBOX GET CELL POSITION(*; "Grouped"; $hitX; $hitY; $cols; $rows)
  $address.hit:=New collection($cols; $rows)
  If (($cols>0) & ($rows>0))
   LISTBOX GET CELL COORDINATES(*; "Grouped"; $cols; $rows; $left; $top; $right; $bottom)
   $address.roundTrip:=New collection($left; $top; $right; $bottom)
  End if
  $state.grouped.coordinates.push($address)
 End for
End for
$state.grouped.physicalLeafHits:=New collection
LISTBOX GET CELL COORDINATES(*; "Grouped"; 3; 1; $left; $top; $right; $bottom)
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
// Only a synthetic baseline point, not discovered disclosure geometry.
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
$state.grouped.selected:=New collection
ARRAY TO COLLECTION($state.grouped.selected; AXHP_Selection)
// Native probe result, when installed.
File("/RESOURCES/state.json").setText(JSON Stringify($state))
