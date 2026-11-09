// What the current form's definition stores for the bridge ("axb"), by section:
// "options" (the form's own), "controls" (its objects) or "grids" (its list boxes and
// areas). A compiled project cannot read its form definitions, so the installer
// packages them in Resources/AXB.FormMetadata.json. Returns Null when none is stored.
#DECLARE($section : Text) -> $stored : Object
var $file : 4D.File
var $metadata; $forms; $form : Object
var $table : Pointer
var $key; $name : Text
var $savedOK : Integer
// A process reads the resource once; it cannot change while the application runs.
If (AXB_FormMetadata=Null)
 AXB_FormMetadata:=New object
 $file:=File("/RESOURCES/AXB.FormMetadata.json")
 If ($file.exists)
  $savedOK:=OK
  $metadata:=JSON Parse($file.getText())
  OK:=$savedOK
  If (($metadata#Null) && (Value type($metadata)=Is object) && ($metadata.schema=1))
   For each ($name; New collection("options"; "controls"; "grids"))
    If ((Value type($metadata[$name])=Is object) && ($metadata[$name]#Null))
     AXB_FormMetadata[$name]:=$metadata[$name]
    End if
   End for each
  End if
 End if
End if
$forms:=AXB_FormMetadata[$section]
If (($forms=Null) || (Value type($forms)#Is object))
 return
End if
$table:=Current form table
$key:="0"
If (Not(Is nil pointer($table)))
 $key:=String(Table($table))
End if
$form:=$forms[$key]
If (($form=Null) || (Value type($form)#Is object))
 return
End if
$stored:=$form[Current form name]
If (($stored#Null) && (Value type($stored)#Is object))
 $stored:=Null
End if
