var $row; $column; $top; $left; $bottom; $right : Integer
var $event : Object
var $columnPointer : Pointer
var $variable : Text
var $table; $field : Integer
$event:=New object("name"; OBJECT Get name(Object current); "event"; Form event code)
If ($event.name="Grouped")
 LISTBOX GET CELL POSITION(*; "Grouped"; $column; $row; $columnPointer)
 $event.row:=$row
 $event.column:=$column
 $event.selection:=New collection
 ARRAY TO COLLECTION($event.selection; AXHP_Selection)
 $event.selectionSlotZero:=AXHP_Selection{0}
 If (Not(Is nil pointer($columnPointer)))
  RESOLVE POINTER($columnPointer; $variable; $table; $field)
  $event.columnVariable:=$variable
 End if
 If (($column>0) & ($row>0))
  LISTBOX GET CELL COORDINATES(*; "Grouped"; $column; $row; $left; $top; $right; $bottom)
  $event.frame:=New collection($left; $top; $right; $bottom)
 End if
End if
Form.events.push($event)
