#DECLARE -> $description : Object
var $error; $i : Integer
var $keys : Pointer
ARRAY LONGINT($selected; 0)
$keys:=Form.lineKeys
$description:=LinePicker_Describe
Form.nodes:=$description.nodes
If (Not($description.enabled))
 return
End if
$error:=AL_GetObjects(Form.area; ALP_Object_Selection; $selected)
Form.selected:=New collection
For ($i; 1; Size of array($selected))
 Form.selected.push($keys->{$selected{$i}})
End for
$error:=AL_GetAreaLongProperty(0; ALP_Area_LastError)
If ($error#0)
 File("/RESOURCES/vendor-error.json").setText(JSON Stringify(New object("vendorError"; $error)))
 AXBA_Stop
 QUIT 4D
 ABORT
End if
