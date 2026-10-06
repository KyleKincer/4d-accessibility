// A button grid as a group of cell buttons. 4D divides the object evenly into
// its columns and rows and sets the value to the clicked cell, numbered by row;
// each cell is pressed with an ordinary click at its center.
#DECLARE($name : Text; $metadata : Object) -> $result : Object
var $group; $cell : Object
var $parts; $labels : Collection
var $label; $id; $cellLabel : Text
var $left; $top; $right; $bottom; $columns; $rows; $count; $i : Integer
var $width; $height : Real
$result:=New object("nodes"; New collection; "unsupported"; New collection)
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
$parts:=Split string(OBJECT Get format(*; $name); ";")
$columns:=Choose($parts.length>0; Num($parts[0]); 1)
$rows:=Choose($parts.length>1; Num($parts[1]); 1)
If (($columns<1) | ($rows<1) | ($right<=$left) | ($bottom<=$top))
 return
End if
$count:=$columns*$rows
$label:=OBJECT Get help tip(*; $name)
If (($metadata#Null) && (Value type($metadata.label)=Is text) && ($metadata.label#""))
 $label:=$metadata.label
End if
If (($metadata#Null) && (Value type($metadata.cells)=Is collection))
 $labels:=$metadata.cells
End if
If (($labels=Null) || ($labels.length#$count))
 // Pictures carry no text; without labels each cell is only numbered.
 $result.unsupported.push(New object("object"; $name; "reason"; "missingLabel"))
 $labels:=Null
End if
$id:="control."+Substring(Generate digest($name; SHA256 digest); 1; 32)
$group:=New object("id"; $id; "objectName"; $name; "role"; "group"; "label"; $label; "value"; ""; "enabled"; OBJECT Get enabled(*; $name); "visible"; True; \
 "focusable"; False; "editable"; False; "frame"; New collection($left; $top; $right-$left; $bottom-$top))
$result.nodes.push($group)
$width:=($right-$left)/$columns
$height:=($bottom-$top)/$rows
For ($i; 1; $count)
 // Choose evaluates both branches, so read a configured label only when present.
 $cellLabel:=$label+" "+String($i)
 If ($labels#Null)
  $cellLabel:=String($labels[$i-1])
 End if
 $cell:=New object("id"; $id+"."+String($i); "parent"; $id; "objectName"; $name; "role"; "button"; "cell"; $i; \
  "label"; $cellLabel; "value"; ""; "enabled"; $group.enabled; "visible"; True; \
  "focusable"; False; "editable"; False; \
  "frame"; New collection(Int($left+((($i-1)%$columns)*$width)); Int($top+((($i-1)\$columns)*$height)); Int($width); Int($height)))
 // Each cell's stable path extends its grid's, as tabs extend their control's.
 $cell.automationChild:=New collection("cell"; String($i))
 $result.nodes.push($cell)
End for
