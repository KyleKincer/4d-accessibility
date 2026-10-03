#DECLARE($list : Integer; $ancestors : Collection) -> $result : Object
var $i; $position; $ref; $child; $count : Integer
var $label : Text
var $expanded : Boolean
var $branch : Object
var $path : Collection
ARRAY TEXT($labels; 0)
ARRAY LONGINT($refs; 0)
$result:=New object("valid"; True; "list"; $list; "rows"; New collection)
If ($ancestors.indexOf($list)>=0)
 $result.valid:=False
 $result.reason:="cycle"
 return
End if
LIST TO ARRAY($list; $labels; $refs)
$position:=1
$count:=Count list items($list)
For ($i; 1; Size of array($refs))
 GET LIST ITEM($list; $position; $ref; $label; $child; $expanded)
 If (($ref#$refs{$i}) | (Compare strings($label; $labels{$i}; sk char codes)#0))
  $result.valid:=False
  $result.reason:="siblingAnchorMismatch"
  $result.position:=$position
  $result.expected:=$refs{$i}
  $result.actual:=$ref
  return
 End if
 $branch:=New object("ref"; $ref; "label"; $label; "expanded"; $expanded; "child"; $child)
 If ($child#0)
  $path:=$ancestors.copy()
  $path.push($list)
  $branch.topology:=AXHP_Topology($child; $path)
  If (Not($branch.topology.valid))
   $result.valid:=False
  End if
 End if
 $result.rows.push($branch)
 $position:=$position+1
 If (($child#0) & $expanded)
  $position:=$position+$branch.topology.disclosedCount
 End if
End for
$result.endPosition:=$position
$result.nativeDisclosedCount:=$count
$result.disclosedCount:=$position-1
