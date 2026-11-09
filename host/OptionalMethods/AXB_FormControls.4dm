// Merge the metadata the current form's definition gives its objects ("axb") into
// $options.controls. A compiled project cannot read its form definitions, so the
// installer packages them in Resources/AXB.FormMetadata.json. Options from the
// application win key by key; $options itself is never changed.
#DECLARE($options : Object) -> $result : Object
var $file : 4D.File
var $metadata; $forms; $form; $controls; $merged : Object
var $explicit : Variant
var $table : Pointer
var $name; $key : Text
var $savedOK : Integer
$result:=$options
If (($options=Null) || (Value type($options)#Is object))
 return
End if
// A process reads the resource once; it cannot change while the application runs.
If (AXB_FormMetadata=Null)
 AXB_FormMetadata:=New object
 $file:=File("/RESOURCES/AXB.FormMetadata.json")
 If ($file.exists)
  $savedOK:=OK
  $metadata:=JSON Parse($file.getText())
  OK:=$savedOK
  If (($metadata#Null) && ($metadata.schema=1) && (Value type($metadata.controls)=Is object) && ($metadata.controls#Null))
   AXB_FormMetadata:=$metadata.controls
  End if
 End if
End if
$table:=Current form table
$key:="0"
If (Not(Is nil pointer($table)))
 $key:=String(Table($table))
End if
$forms:=AXB_FormMetadata[$key]
If (($forms=Null) || (Value type($forms)#Is object))
 return
End if
$form:=$forms[Current form name]
If (($form=Null) || (Value type($form)#Is object))
 return
End if
If (OB Is defined($options; "controls") && ((Value type($options.controls)#Is object) || ($options.controls=Null)))
 // Invalid application options are reported as they are.
 return
End if
$controls:=New object
For each ($name; $form)
 $controls[$name]:=$form[$name]
End for each
If ($options.controls#Null)
 For each ($name; $options.controls)
  $explicit:=$options.controls[$name]
  If (($controls[$name]=Null) || (Value type($explicit)#Is object) || ($explicit=Null))
   $controls[$name]:=$explicit
  Else
   $merged:=New object
   For each ($key; $controls[$name])
    $merged[$key]:=$controls[$name][$key]
   End for each
   For each ($key; $explicit)
    $merged[$key]:=$explicit[$key]
   End for each
   $controls[$name]:=$merged
  End if
 End for each
End if
// A shallow copy: formulas, pointers and data in the options stay shared.
$result:=New object
For each ($name; $options)
 $result[$name]:=$options[$name]
End for each
$result.controls:=$controls
