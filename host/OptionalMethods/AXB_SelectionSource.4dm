// Resolve classic list-box data in a private process. The form's loaded record,
// current selection and unsaved values never become a temporary export buffer.
#DECLARE($options : Object; $state : Object; $list : Object) -> $result : Object
var $table : Pointer
var $tableNumber; $row; $process; $field; $fieldType; $start : Integer
var $selectionName; $highlight; $signature; $keyProperty; $key : Text
var $dataClass; $attribute; $pending; $latest; $column; $fieldInfo : Object
var $records; $rawKeys; $readFields : Collection
var $source; $value : Variant
var $needed : Boolean
ARRAY LONGINT($recordNumbers; 0)
$result:=New object("ok"; False; "message"; "Classic selection is loading"; "keys"; New collection; "selected"; New collection)
If ($list=Null)
 LISTBOX GET TABLE SOURCE(*; $options.objectName; $tableNumber; $selectionName; $highlight)
Else
 $tableNumber:=$list.table
 $selectionName:=$list.form
 $highlight:=$list.highlight
End if
If ($tableNumber<1)
 $result.message:="List box has no classic table source"
 return
End if
$table:=Table($tableNumber)
$dataClass:=Null
If (OB Keys(ds).indexOf(Table name($tableNumber))>=0)
 $dataClass:=ds[Table name($tableNumber)]
End if
$keyProperty:=""
If ($dataClass#Null)
 $keyProperty:=$dataClass.getInfo().primaryKey
End if
If (OB Is defined($options; "keyProperty"))
 $keyProperty:=$options.keyProperty
End if
$readFields:=Null
$attribute:=Null
If ($dataClass=Null)
 If ($list=Null)
  $result.error:="classicDatastoreRequired"
  $result.message:="Classic list box needs a datastore mapping"
  return
 End if
 $readFields:=New shared collection
 For ($field; 1; Get last field number($tableNumber))
  If (Not(Is field number valid($tableNumber; $field)))
   continue
  End if
  GET FIELD PROPERTIES($tableNumber; $field; $fieldType)
  $fieldInfo:=New shared object("name"; Field name($tableNumber; $field); "field"; $field; "type"; $fieldType)
  $needed:=False
  If (Compare strings($fieldInfo.name; $keyProperty; sk char codes)=0)
   $attribute:=$fieldInfo
   $needed:=True
  End if
  For each ($column; $list.columns)
   $needed:=$needed | (($column.fieldNumber=$field) & Not($column.protected))
  End for each
  If ($needed && (New collection(Is alpha field; Is text; Is real; Is integer; Is longint; Is integer 64 bits; Is date; Is time; Is Boolean).indexOf($fieldType)>=0))
   Use ($readFields)
    $readFields.push($fieldInfo)
   End use
  End if
 End for
 If (($attribute=Null) || (New collection(Is alpha field; Is text; Is integer; Is longint).indexOf($attribute.type)<0))
  $result.error:="classicIdentityRequired"
  $result.message:="Classic table without a primary key needs an existing unique text or integer keyProperty"
  return
 End if
Else
 $attribute:=$dataClass[$keyProperty]
 If (($attribute=Null) || ($attribute.kind#"storage") || (New collection("string"; "number").indexOf($attribute.type)<0))
  $result.error:="classicIdentityRequired"
  $result.message:="Classic identity must be a stored text or integer attribute"
  return
 End if
End if
If ($list#Null)
 $records:=$list.records
 $result.count:=$records.length
Else
 If ($selectionName="")
  LONGINT ARRAY FROM SELECTION($table->; $recordNumbers)
 Else
  LONGINT ARRAY FROM SELECTION($table->; $recordNumbers; $selectionName)
 End if
 $records:=New collection
 ARRAY TO COLLECTION($records; $recordNumbers)
 $result.count:=LISTBOX Get number of rows(*; $options.objectName)
End if
If ($result.count#$records.length)
 $result.message:="Classic selection changed during inspection"
 return
End if
$signature:=Generate digest(JSON Stringify(New collection($tableNumber; $selectionName; $highlight; $records; $readFields)); SHA256 digest)
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
 If ($readFields#Null)
  Use ($pending)
   $pending.readFields:=$readFields.copy(ck shared; $pending)
  End use
 End if
 If ($highlight#"")
  Use ($pending)
   $pending.highlight:="<>AXB_"+Generate UUID
  End use
  COPY SET($highlight; $pending.highlight)
 End if
 $state.selectionRead:=$pending
 $process:=New process("AXB_SelectionRead"; 0; "AXB selection read"; $pending)
End if
// A published grid that reorders (a sort) would otherwise report loading and
// lose its rows until the next poll. Its read usually takes milliseconds;
// yield briefly for it. A first read, or a slow one, still reports loading.
$pending:=$state.selectionRead
If (($state.selectionSource#Null) && ($pending#Null) && ($pending.signature=$signature))
 $start:=Milliseconds
 While (($pending.done#True) & ((Milliseconds-$start)<250))
  DELAY PROCESS(Current process; 0)
 End while
 If ($pending.done=True)
  $state.selectionError:=$pending.error
  $state.selectionSource:=Null
  If ($pending.error=Null)
   $state.selectionSource:=$pending
  End if
  $state.selectionRead:=Null
 End if
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
