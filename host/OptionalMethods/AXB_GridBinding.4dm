// Read a list box's row identities and selection without moving its current
// row or evaluating a column expression. Values remain in the owning host.
#DECLARE($options : Object) -> $binding : Object
var $name; $property; $key; $metaExpression; $metaProperty; $flag : Text
var $count; $row; $flags : Integer
var $keys; $selection; $control : Pointer
var $source; $selected; $item; $value; $meta : Variant
var $dataClass; $attribute; $sourceStore; $selectedStore : Object
var $rawKeys; $selectedKeys; $selectedTextKeys : Collection
var $hierarchical; $entity : Boolean
$binding:=New object("ok"; False; "message"; "Unsupported list box binding"; "keys"; New collection; "selected"; New collection)
$name:=$options.objectName
$count:=LISTBOX Get number of rows(*; $name)
$binding.count:=$count
If ($options.kind="array")
 LISTBOX GET HIERARCHY(*; $name; $hierarchical)
 If ($hierarchical)
  return
 End if
 $keys:=OBJECT Get pointer(Object named; $options.keyColumn)
 $selection:=OBJECT Get pointer(Object named; $name)
 $control:=LISTBOX Get array(*; $name; lk control array)
 If (Is nil pointer($keys) | Is nil pointer($selection))
  return
 End if
 If ((Type($keys->)#Text array) | (Type($selection->)#Boolean array))
  return
 End if
 If ((Size of array($keys->)#$count) | (Size of array($selection->)#$count))
  return
 End if
 If (Not(Is nil pointer($control)))
  If ((Type($control->)#LongInt array) | (Size of array($control->)#$count))
   return
  End if
 End if
 ARRAY TO COLLECTION($binding.keys; $keys->)
 ARRAY TO COLLECTION($binding.selected; $selection->)
 $binding.keyPointer:=$keys
 $binding.selectionPointer:=$selection
 $binding.controlPointer:=$control
 $binding.identity:="array"
 $binding.ok:=True
 return
End if
$entity:=$options.kind="entity"
If (Not($entity | ($options.kind="collection")))
 return
End if
$source:=OBJECT Get value($name)
If ($source=Null)
 return
End if
If ($entity)
 If ((Value type($source)#Is object) || Not(OB Instance of($source; 4D.EntitySelection)))
  return
 End if
 $dataClass:=$source.getDataClass()
 $property:=$dataClass.getInfo().primaryKey
 If (OB Is defined($options; "keyProperty"))
  $property:=$options.keyProperty
 End if
 $attribute:=$dataClass[$property]
 If (($attribute=Null) || ($attribute.kind#"storage") || (New collection("string"; "number").indexOf($attribute.type)<0))
  $binding.message:="Entity identity must be a stored text or integer attribute"
  return
 End if
 $sourceStore:=$dataClass.getDataStore().getInfo()
 $key:=""
 If ($sourceStore.type="4D Server")
  $key:=$sourceStore.connection.hostname
 End if
 $binding.identity:=JSON Stringify(New collection("entity"; $property; $dataClass.getInfo().name; $sourceStore.type; $sourceStore.localID; $key))
 // Keep nulls so a dropped/missing identity cannot shift later row positions.
 $rawKeys:=$source.extract($property; ck keep null)
 $binding.dataClass:=$dataClass
Else
 If (Value type($source)#Is collection)
  return
 End if
 $property:=$options.keyProperty
 $binding.identity:="collection:"+$property
 $rawKeys:=New collection
 $binding.itemsByKey:=New object
 For each ($item; $source)
  If (($item=Null) || (Value type($item)#Is object))
   return
  End if
  $rawKeys.push($item[$property])
 End for each
End if
If (($source.length#$count) | ($rawKeys.length#$count))
 return
End if
$metaExpression:=LISTBOX Get property(*; $name; lk meta expression)
$metaProperty:=""
If (($metaExpression="") & ($options.meta#Null))
 $binding.message:="A meta Formula is configured but the list box has no Meta Info Expression"
 return
End if
If ($metaExpression#"")
 If ($options.meta=Null)
  If (Not(Match regex("^This[.][[:alpha:]_][[:alnum:]_]*$"; $metaExpression)))
   $binding.message:="Provide a meta Formula calling the existing row metadata expression"
   return
  End if
  $metaProperty:=Substring($metaExpression; 6)
 End if
End if
$binding.metaExpression:=$metaExpression
$binding.meta:=$options.meta
$binding.rowFlags:=New collection
$selected:=Null
If ($options.selection#Null)
 $selected:=$options.selection.call()
Else
 If (LISTBOX Get property(*; $name; lk selection mode)>0)
  $binding.message:="Provide a Formula reading the list box's selected items"
  return
 End if
End if
If ($entity)
 If ($selected=Null)
  $selected:=$dataClass.newSelection()
 End if
 If ((Value type($selected)#Is object) || Not(OB Instance of($selected; 4D.EntitySelection)))
  return
 End if
 $selectedStore:=$selected.getDataClass().getDataStore().getInfo()
 If ((Compare strings($sourceStore.type; $selectedStore.type; sk char codes)#0) | (Compare strings($sourceStore.localID; $selectedStore.localID; sk char codes)#0) | (Compare strings($dataClass.getInfo().name; $selected.getDataClass().getInfo().name; sk char codes)#0))
  return
 End if
 If (($sourceStore.type="4D Server") && (Compare strings($sourceStore.connection.hostname; $selectedStore.connection.hostname; sk char codes)#0))
  return
 End if
 $selectedKeys:=$selected.extract($property; ck keep null)
 $selectedTextKeys:=New collection
 For each ($value; $selectedKeys)
  If (Value type($value)=Is text)
   $selectedTextKeys.push($value)
  End if
 End for each
Else
 If ($selected=Null)
  $selected:=New collection
 End if
 If (Value type($selected)#Is collection)
  return
 End if
End if
For ($row; 0; $count-1)
 $value:=$rawKeys[$row]
 Case of
  : (Value type($value)=Is text)
   If ($value="")
    return
   End if
   $key:="s:"+$value
  : (New collection(Is real; Is integer; Is longint).indexOf(Value type($value))>=0)
   If (($value#Int($value)) | ($value<(-2147483648)) | ($value>2147483647))
    return
   End if
   $key:="n:"+String($value; "&xml")
  Else
   return
 End case
 $binding.keys.push($key)
 $flags:=0
 If ($metaExpression#"")
  $item:=$source[$row]
  If ($options.meta#Null)
   $meta:=$options.meta.call($item; New object("key"; $value; "row"; $row+1; "item"; $item))
  Else
   $meta:=$item[$metaProperty]
  End if
  If ($meta#Null)
   If (Value type($meta)#Is object)
    $binding.message:="Row metadata must return an object or Null"
    return
   End if
   For each ($flag; New collection("disabled"; "unselectable"))
    If (OB Is defined($meta; $flag))
     If (($meta[$flag]#Null) & (Value type($meta[$flag])#Is Boolean))
      $binding.message:="Row metadata "+$flag+" must be Boolean"
      return
     End if
    End if
   End for each
   If ($meta.disabled=True)
    $flags:=$flags+lk row is disabled
   End if
   If ($meta.unselectable=True)
    $flags:=$flags+lk row is not selectable
   End if
  End if
 End if
 $binding.rowFlags.push($flags)
 If ($entity)
  // Text identity uses character codes, not 4D's case/accent-insensitive
  // collection search. Numeric primary keys have exact integer comparison.
  If (Value type($value)=Is text)
   $binding.selected.push(AXB_KeyIndex($selectedTextKeys; $value)>=0)
  Else
   $binding.selected.push($selectedKeys.indexOf($value)>=0)
  End if
 Else
  $binding.itemsByKey[$key]:=$source[$row]
  $binding.selected.push($selected.indexOf($source[$row])>=0)
 End if
End for
$binding.source:=$source
$binding.keyProperty:=$property
$binding.ok:=True
