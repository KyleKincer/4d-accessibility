// Return form metadata ("options", "controls", "grids", "lists", "hints", "meta")
// for the current form. Prefers the native FormCatalog plugin command (loose Project/Sources
// or compiled .4DZ), falling back to Resources/AXB.FormMetadata.json when running with an older
// plugin or a synthetic test fixture.
#DECLARE($section : Text) -> $result : Object
var $table : Pointer
var $tableNum; $savedOK : Integer
var $formName; $resourcesPath : Text
var $reply; $data; $forms; $tableForms; $form : Object
var $file : 4D.File
$formName:=Current form name
If ($formName="")
 return
End if
$table:=Current form table
$tableNum:=Choose(Is nil pointer($table); 0; Table($table))
$reply:=AXB_Host("formMetadata"; New object("table"; $tableNum; "form"; $formName))
If (($reply#Null) && (Value type($reply)=Is object) && ($reply.ok=True) && ($reply.found=True))
 If ($section="meta")
  $result:=$reply
  return
 End if
 If (OB Is defined($reply; $section) && (Value type($reply[$section])=Is object) && ($reply[$section]#Null))
  $result:=$reply[$section]
 End if
 return
End if
// Fallback to Resources/AXB.FormMetadata.json (resolve host Resources folder inside components).
$resourcesPath:=Get 4D folder(Current resources folder; *)
If ($resourcesPath#"")
 $file:=Folder($resourcesPath; fk platform path).file("AXB.FormMetadata.json")
End if
If (($file=Null) || Not($file.exists))
 $file:=File("/RESOURCES/AXB.FormMetadata.json")
End if
If (Not($file.exists))
 return
End if
$savedOK:=OK
$data:=JSON Parse($file.getText("UTF-8"))
OK:=$savedOK
If (($data=Null) || (Value type($data)#Is object) || ($data.schema#1) || (Value type($data.forms)#Is object))
 return
End if
$forms:=$data.forms
$tableForms:=$forms[String($tableNum)]
If (($tableForms=Null) || (Value type($tableForms)#Is object))
 return
End if
$form:=$tableForms[$formName]
If (($form=Null) || (Value type($form)#Is object))
 return
End if
If ($section="meta")
 $result:=$form
 return
End if
If (OB Is defined($form; $section) && (Value type($form[$section])=Is object) && ($form[$section]#Null))
 $result:=$form[$section]
End if
