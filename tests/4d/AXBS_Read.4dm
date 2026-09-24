#DECLARE -> $state : Object
var $x; $y : Integer
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$state:=New object("origin"; New collection($x; $y); "focus"; OBJECT Get name(Object with focus); "first"; Form.first; "last"; Form.last; "clicks"; Form.clicks; "wideClicks"; Form.wideClicks; "edits"; Form.edits; "remembered"; Form.remembered)
