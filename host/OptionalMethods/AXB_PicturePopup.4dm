// A picture popup menu as a popup of its picture's cells. 4D's own palette is a
// menu of one unlabeled picture, so the plugin offers these choices in a menu of
// its own; the value is the chosen cell, numbered by row, or 0 for none.
#DECLARE($name : Text; $metadata : Object) -> $result : Object
var $parts : Collection
var $label : Text
var $columns; $rows; $count; $choice; $i : Integer
$result:=New object("choices"; New collection; "choice"; 0; "value"; ""; "unsupported"; New collection)
$parts:=Split string(OBJECT Get format(*; $name); ";")
$columns:=Choose($parts.length>0; Num($parts[0]); 1)
$rows:=Choose($parts.length>1; Num($parts[1]); 1)
$count:=New collection($columns; 1).max()*New collection($rows; 1).max()
$label:=OBJECT Get help tip(*; $name)
If (($metadata#Null) && (Value type($metadata.label)=Is text) && ($metadata.label#""))
 $label:=$metadata.label
End if
If (($metadata#Null) && (Value type($metadata.cells)=Is collection) && ($metadata.cells.length=$count))
 $result.choices:=$metadata.cells.copy()
Else
 // Pictures carry no text; without labels each choice is only numbered.
 $result.unsupported.push(New object("object"; $name; "reason"; "missingLabel"))
 For ($i; 1; $count)
  $result.choices.push(Choose($label=""; "Choice "+String($i); $label+" "+String($i)))
 End for
End if
$choice:=Num(OBJECT Get value($name))
If (($choice>=1) & ($choice<=$count))
 $result.choice:=$choice
 $result.value:=$result.choices[$choice-1]
End if
