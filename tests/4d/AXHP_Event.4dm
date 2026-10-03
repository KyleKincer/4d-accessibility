var $row; $column; $top; $left; $bottom; $right : Integer
var $event : Object
$event:=New object("name"; OBJECT Get name(Object current); "event"; Form event code)
If ($event.name="Grouped")
 LISTBOX GET CELL POSITION(*; "Grouped"; $column; $row)
 $event.row:=$row
 $event.column:=$column
 LISTBOX GET CELL COORDINATES(*; "Grouped"; $column; $row; $left; $top; $right; $bottom)
 $event.frame:=New collection($left; $top; $right; $bottom)
End if
Form.events.push($event)
