#DECLARE -> $state : Object
var $inner : Object
var $x; $y; $scrollX; $scrollY : Integer
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
EXECUTE METHOD IN SUBFORM("Nested"; "AXBS_Read"; $inner)
OBJECT GET SCROLL POSITION(*; "Nested"; $scrollY; $scrollX)
$state:=New object("origin"; New collection($x; $y); "inner"; $inner; "scroll"; New collection($scrollX; $scrollY))
