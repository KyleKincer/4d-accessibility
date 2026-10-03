// Read synthetic hierarchy, row-control and geometry state without input.
#DECLARE($name : Text) -> $result : Object
var $savedOK; $count; $columns; $level; $row; $column; $type; $table; $field; $left; $top; $right; $bottom; $hitColumn; $hitRow; $vertical; $horizontal : Integer
var $hierarchical : Boolean
var $pointer; $control; $hitPointer : Pointer
var $variable : Text
var $values : Collection
var $item : Object
var $x; $y; $screenLeft; $screenTop; $screenRight; $screenBottom : Real
ARRAY POINTER($hierarchy; 0)
$savedOK:=OK
LISTBOX GET HIERARCHY(*; $name; $hierarchical; $hierarchy)
$count:=LISTBOX Get number of rows(*; $name)
$columns:=LISTBOX Get number of columns(*; $name)
$result:=New object("case"; Form.groupedCase; "hierarchical"; $hierarchical; "rows"; $count; "columns"; $columns; "levels"; New collection; "coordinates"; New collection; "selection"; New collection; "control"; New collection; "keys"; New collection)
ARRAY TO COLLECTION($result.keys; AXHP_Key)
$result.arrayLengths:=New object("group"; Size of array(AXHP_Group); "subgroup"; Size of array(AXHP_Subgroup); "label"; Size of array(AXHP_Label); "key"; Size of array(AXHP_Key); "selection"; Size of array(AXHP_Selection); "control"; Size of array(AXHP_Control))
OBJECT GET SCROLL POSITION(*; $name; $vertical; $horizontal)
$result.scroll:=New collection($vertical; $horizontal)
$result.focus:=OBJECT Get name(Object with focus)
$result.selectionMode:=LISTBOX Get property(*; $name; lk selection mode)
$result.selectionSlotZero:=AXHP_Selection{0}
ARRAY TO COLLECTION($result.selection; AXHP_Selection)
For ($level; 1; Size of array($hierarchy))
 $pointer:=$hierarchy{$level}
 RESOLVE POINTER($pointer; $variable; $table; $field)
 $type:=Type($pointer->)
 $values:=New collection
 ARRAY TO COLLECTION($values; $pointer->)
 $result.levels.push(New object("level"; $level; "variable"; $variable; "type"; $type; "length"; Size of array($pointer->); "values"; $values; "slotZero"; $pointer->{0}))
End for
$control:=LISTBOX Get array(*; $name; lk control array)
If (Not(Is nil pointer($control)))
 $result.controlType:=Type($control->)
 ARRAY TO COLLECTION($result.control; $control->)
 $result.controlSlotZero:=$control->{0}
End if
// Include candidate break addresses as well as ordinary column addresses.
// Nonpositive rectangles cannot justify any hit test or native input.
For ($row; 1; $count)
 For ($column; 1; $columns+Size of array($hierarchy)-1)
  $left:=0
  $top:=0
  $right:=0
  $bottom:=0
  LISTBOX GET CELL COORDINATES(*; $name; $column; $row; $left; $top; $right; $bottom)
  $item:=New object("row"; $row; "column"; $column; "frame"; New collection($left; $top; $right; $bottom); "positive"; ($right>$left) & ($bottom>$top))
  If ($item.positive)
   $screenLeft:=$left
   $screenTop:=$top
   $screenRight:=$right
   $screenBottom:=$bottom
   CONVERT COORDINATES($screenLeft; $screenTop; XY Current form; XY Screen)
   CONVERT COORDINATES($screenRight; $screenBottom; XY Current form; XY Screen)
   $item.screenFrame:=New collection($screenLeft; $screenTop; $screenRight; $screenBottom)
   $x:=($left+$right)/2
   $y:=($top+$bottom)/2
   $hitColumn:=0
   $hitRow:=0
   CLEAR VARIABLE($hitPointer)
   LISTBOX GET CELL POSITION(*; $name; $x; $y; $hitColumn; $hitRow; $hitPointer)
   $item.hit:=New collection($hitColumn; $hitRow)
   If (Not(Is nil pointer($hitPointer)))
    RESOLVE POINTER($hitPointer; $variable; $table; $field)
    $item.hitVariable:=$variable
   End if
  End if
  $result.coordinates.push($item)
 End for
End for
OK:=$savedOK
