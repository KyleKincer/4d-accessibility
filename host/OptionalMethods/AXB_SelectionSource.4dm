// Resolve classic list-box data in a private process. The form's loaded record,
// current selection and unsaved values never become a temporary export buffer.
#DECLARE($options : Object; $state : Object) -> $result : Object
var $table : Pointer
var $tableNumber; $row; $process : Integer
var $selectionName; $highlight; $signature; $keyProperty; $key : Text
var $dataClass; $attribute; $pending; $latest : Object
var $records; $rawKeys : Collection
var $source : 4D.EntitySelection
var $value : Variant
ARRAY LONGINT($recordNumbers; 0)
$result:=New object("ok"; False; "message"; "Classic selection is loading"; "keys"; New collection; "selected"; New collection)
LISTBOX GET TABLE SOURCE(*; $options.objectName; $tableNumber; $selectionName; $highlight)
If ($tableNumber<1)
 $result.message:="List box has no classic table source"
 return
End if
$table:=Table($tableNumber)
$dataClass:=ds[Table name($tableNumber)]
If ($dataClass=Null)
 $result.message:="Classic table needs a datastore mapping"
 return
End if
$keyProperty:=$dataClass.getInfo().primaryKey
If (OB Is defined($options; "keyProperty"))
 $keyProperty:=$options.keyProperty
End if
$attribute:=$dataClass[$keyProperty]
If (($attribute=Null) || ($attribute.kind#"storage") || (New collection("string"; "number").indexOf($attribute.type)<0))
 $result.message:="Classic identity must be a stored text or integer attribute"
 return
End if
If ($selectionName="")
 LONGINT ARRAY FROM SELECTION($table->; $recordNumbers)
Else
 LONGINT ARRAY FROM SELECTION($table->; $recordNumbers; $selectionName)
End if
$records:=New collection
ARRAY TO COLLECTION($records; $recordNumbers)
$result.count:=LISTBOX Get number of rows(*; $options.objectName)
If ($result.count#$records.length)
 $result.message:="Classic selection changed during inspection"
 return
End if
$signature:=Generate digest(JSON Stringify(New collection($tableNumber; $selectionName; $highlight; $records)); SHA256 digest)
$pending:=$state.selectionRead
If (($pending#Null) && ($pending.done=True))
 If ($pending.signature=$signature)
  $state.selectionError:=$pending.error
  If ($pending.error=Null)
   $state.selectionSource:=$pending
  Else
   $state.selectionSource:=Null
  End if
 End if
 $state.selectionRead:=Null
End if
If ($state.selectionRead=Null)
 $pending:=New shared object("done"; False; "signature"; $signature; "table"; $tableNumber; "records"; $records.copy(ck shared); "highlight"; "")
 If ($highlight#"")
  Use ($pending)
   $pending.highlight:="<>AXB_"+Generate UUID
  End use
  COPY SET($highlight; $pending.highlight)
 End if
 $state.selectionRead:=$pending
 $process:=New process("AXB_SelectionRead"; 0; "AXB selection read"; $pending)
End if
$latest:=$state.selectionSource
If (($latest=Null) || ($latest.signature#$signature))
 If ($state.selectionError#Null)
  $result.message:="Classic selection read failed: "+$state.selectionError
 End if
 return
End if
$source:=$latest.source
If (($source.length#$records.length) | ($source.length#$result.count))
 $result.message:="Classic records became unavailable"
 return
End if
$rawKeys:=$source.extract($keyProperty; ck keep null)
For ($row; 0; $records.length-1)
 $value:=$rawKeys[$row]
 Case of
  : ((Value type($value)=Is text) && ($value#""))
   $key:="s:"+$value
  : (New collection(Is real; Is integer; Is longint).indexOf(Value type($value))>=0)
   If (($value#Int($value)) | ($value<(-2147483648)) | ($value>2147483647))
    $result.message:="Classic row identity must be text or a 32-bit integer"
    return
   End if
   $key:="n:"+String($value; "&xml")
  Else
   $result.message:="Classic row identity is unavailable"
   return
 End case
 $result.keys.push($key)
 $result.selected.push($latest.selected[String($records[$row])]=True)
End for
$result.identity:=JSON Stringify(New collection("selection"; $tableNumber; $selectionName; $highlight; $keyProperty))
$result.metaExpression:=""
$result.source:=$source
$result.dataClass:=$dataClass
$result.table:=$tableNumber
$result.keyProperty:=$keyProperty
$result.noSelection:=$highlight=""
$result.ok:=True
