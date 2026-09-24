#DECLARE($objectName : Text; $id : Text; $role : Text; $label : Text; $value : Variant; $enabled : Boolean) -> $node : Object
var $left; $top; $right; $bottom : Integer
OBJECT GET COORDINATES(*; $objectName; $left; $top; $right; $bottom)
$node:=New object("id"; $id; "role"; $role; "label"; $label; "value"; $value; "enabled"; $enabled & OBJECT Get enabled(*; $objectName); "visible"; OBJECT Get visible(*; $objectName); "frame"; New collection($left; $top; $right-$left; $bottom-$top))
