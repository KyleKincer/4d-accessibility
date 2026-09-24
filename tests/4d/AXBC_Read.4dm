#DECLARE() -> $result : Object
var $x; $y : Integer
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$result:=New object("name"; Form.name; "clicked"; Form.clicked; "focus"; OBJECT Get name(Object with focus); "editing"; Is editing text; "origin"; New collection($x; $y); "hasProviderState"; OB Is defined(Form; "axbView"))
If (Form=Null)
 $result.name:=AXBC_UnboundName
 $result.clicked:=AXBC_UnboundClicks
 $result.nullForm:=True
End if
If (Is editing text)
 $result.edited:=Get edited text
End if
