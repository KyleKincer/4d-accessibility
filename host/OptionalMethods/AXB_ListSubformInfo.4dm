// Capture a classic list selection and body geometry in the owning parent.
// A private read-only worker resolves records; this method never loads them.
#DECLARE($options : Object; $state : Object) -> $result : Object
var $table; $parent : Pointer
var $detail; $list : Text
var $definition; $fields; $metadata; $listMetadata : Object
var $file : 4D.File
var $packet : Object
var $mode : Text
var $parentMetadataMissing : Boolean
var $header; $body; $savedOK; $parentX; $parentY; $parentTable; $left; $top; $right; $bottom; $first : Integer
ARRAY LONGINT($records; 0)
$result:=New object("ok"; False; "error"; "listSubformUnavailable")
If ((OBJECT Get type(*; $options.objectName)#Object type subform) | Not(OBJECT Get visible(*; $options.objectName)))
 return
End if
OBJECT GET SUBFORM(*; $options.objectName; $table; $detail; $list)
If (Is nil pointer($table) | ($list=""))
 return
End if
If ($state.nativeListSupport=Null)
 $packet:=AXB_Host("info"; New object)
 $state.nativeListSupport:=($packet.ok=True) && (Position("; listSubforms 1;"; $packet.nativeStatus)>0)
End if
If (Not($state.nativeListSupport=True))
 $result.error:="nativeListSubformUnavailable"
 return
End if
$metadata:=$state.formMetadata
If ($metadata=Null)
 $file:=File("/RESOURCES/AXB.FormMetadata.json")
 If ($file.exists)
  $savedOK:=OK
  $metadata:=JSON Parse($file.getText())
  OK:=$savedOK
  If (($metadata#Null) && ($metadata.schema=1))
   $state.formMetadata:=$metadata
  End if
 End if
End if
$definition:=Null
If (($metadata#Null) && ($metadata.schema=1) && ($metadata.forms#Null) && ($metadata.forms[String(Table($table))]#Null))
 $definition:=$metadata.forms[String(Table($table))][$list]
End if
If ($definition=Null)
 $result.error:="listSubformDefinitionRequired"
 return
End if
$parent:=Current form table
$parentTable:=0
If (Not(Is nil pointer($parent)))
 $parentTable:=Table($parent)
End if
$mode:="none"
$parentMetadataMissing:=True
$listMetadata:=New object("enterable"; False)
If (($metadata.forms[String($parentTable)]#Null) && ($metadata.forms[String($parentTable)][Current form name]#Null) && ($metadata.forms[String($parentTable)][Current form name].lists#Null) && ($metadata.forms[String($parentTable)][Current form name].lists[$options.objectName]#Null))
 $listMetadata:=$metadata.forms[String($parentTable)][Current form name].lists[$options.objectName]
 $mode:=$listMetadata.selection
 $parentMetadataMissing:=False
End if
$header:=Num($definition.header)
$body:=Num($definition.body)
If ($body<=$header)
 $result.error:="listSubformBodyUnavailable"
 return
End if
$packet:=New object("table"; Table($table); "form"; $list; "options"; $options; "header"; $header; "body"; $body)
$fields:=Null
$savedOK:=OK
EXECUTE METHOD IN SUBFORM($options.objectName; "AXB_ListSubformFields"; $fields; $packet)
OK:=$savedOK
If (($fields=Null) || Not($fields.ok=True))
 return
End if
LONGINT ARRAY FROM SELECTION($table->; $records)
$parentX:=0
$parentY:=0
CONVERT COORDINATES($parentX; $parentY; XY Current form; XY Current window)
$fields.origin:=New collection($fields.origin[0]-$parentX; $fields.origin[1]-$parentY)
// A header keeps the row-form origin fixed while scrolling; an overlay editor
// returns its own row origin. Derive vertical slots from the actual parent,
// native first visible record and installed markers in both presentations.
OBJECT GET COORDINATES(*; $options.objectName; $left; $top; $right; $bottom)
OBJECT GET SCROLL POSITION(*; $options.objectName; $first)
$first:=New collection(1; $first).max()
// At the bottom 4D clamps scrolling in pixels, while its public position
// remains a row number rounded upward. Bound the offset by the full content
// height so the final record retains its viewport position.
$fields.origin[1]:=$top-New collection(($first-1)*($body-$header); New collection(0; $header+(Size of array($records)*($body-$header))-($bottom-$top)).max()).min()
$result:=New object("ok"; True; "table"; Table($table); "form"; $list; "header"; $header; "height"; $body-$header; "columns"; $fields.columns; "origin"; $fields.origin; "unsupported"; $fields.unsupported; "records"; New collection)
$result.liveValues:=$fields.liveValues
If ($parentMetadataMissing)
 $result.unsupported.push(New object("reason"; "listSubformParentMetadataRequired"))
End if
$result.enterable:=$listMetadata.enterable=True
ARRAY TO COLLECTION($result.records; $records)
If ($state.highlight=Null)
 $state.highlight:="AXB_List_"+Generate UUID
End if
$savedOK:=OK
GET HIGHLIGHTED RECORDS($table->; $state.highlight)
OK:=$savedOK
$result.highlight:=$state.highlight
$result.selectionMode:=$mode
If ($mode="single")
 $result.selectedPosition:=Choose(Is record loaded($table->); Selected record number($table->); 0)
End if
