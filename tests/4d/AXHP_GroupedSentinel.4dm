// Independent state around a full reader, with no geometry inspection or input.
#DECLARE($name : Text) -> $result : Object
var $savedOK; $vertical; $horizontal : Integer
$savedOK:=OK
$result:=New object("ok"; $savedOK; "focus"; OBJECT Get name(Object with focus); "selection"; New collection; "selectionSlotZero"; AXHP_Selection{0})
ARRAY TO COLLECTION($result.selection; AXHP_Selection)
OBJECT GET SCROLL POSITION(*; $name; $vertical; $horizontal)
$result.scroll:=New collection($vertical; $horizontal)
OK:=$savedOK
