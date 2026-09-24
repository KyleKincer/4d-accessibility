// Build the grid's table node entirely in the host. This keeps AreaList adapters
// compilable when the optional bridge component and native plugin are absent.
#DECLARE($objectName : Text; $id : Text; $label : Text) -> $node : Object
var $left; $top; $right; $bottom : Integer
OBJECT GET COORDINATES(*; $objectName; $left; $top; $right; $bottom)
$node:=New object("id"; $id; "role"; "table"; "label"; $label; "value"; ""; "enabled"; OBJECT Get enabled(*; $objectName); "visible"; OBJECT Get visible(*; $objectName); "frame"; New collection($left; $top; $right-$left; $bottom-$top))
