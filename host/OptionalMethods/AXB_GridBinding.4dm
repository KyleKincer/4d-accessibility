// Read a list box's row identities and selection without moving its current
// row or evaluating a column expression. Values remain in the owning host.
#DECLARE($options : Object; $state : Object) -> $binding : Object
var $name; $property; $key; $metaExpression; $metaProperty; $flag : Text
var $count; $row; $flags; $level; $visibleIndex : Integer
var $keys; $selection; $control : Pointer
var $source; $selected; $item; $value; $meta : Variant
var $dataClass; $attribute; $sourceStore; $selectedStore : Object
var $rawKeys; $selectedKeys; $selectedTextKeys : Collection
var $hierarchical; $entity; $positional; $hidden : Boolean
$binding:=New object("ok"; False; "message"; "Unsupported list box binding"; "keys"; New collection; "selected"; New collection)
ARRAY POINTER($hierarchy; 0)
If ($options.kind="selection")
 return AXB_SelectionSource($options; $state)
End if
$name:=$options.objectName
$count:=LISTBOX Get number of rows(*; $name)
$binding.count:=$count
$positional:=($options.positionalKeys=True)
If (New collection("array"; "outline").indexOf($options.kind)>=0)
 LISTBOX GET HIERARCHY(*; $name; $hierarchical; $hierarchy)
 If ($hierarchical#($options.kind="outline"))
  return
 End if
 If ($hierarchical)
  If ((Size of array($hierarchy)<1) | (Size of array($hierarchy)>10))
   return
  End if
  $binding.hierarchy:=New collection
  For ($level; 1; Size of array($hierarchy))
   $binding.hierarchy.push($hierarchy{$level})
  End for
  $binding.coordinateOffset:=Choose(Size of array($hierarchy)=1; 0; Size of array($hierarchy)-1)
 End if
 $selection:=OBJECT Get pointer(Object named; $name)
 $control:=LISTBOX Get array(*; $name; lk control array)
 If (Is nil pointer($selection))
  return
 End if
 If (Type($selection->)#Boolean array)
  return
 End if
 If (Size of array($selection->)#$count)
  If ($options.auto=True)
   $binding.loading:=True
  End if
  return
 End if
 If (Not(Is nil pointer($control)))
  If ((New collection(Boolean array; LongInt array).indexOf(Type($control->))<0) || (Size of array($control->)#$count))
   If ($options.auto=True)
    $binding.loading:=True
   End if
   return
  End if
 End if
 If ($positional & Not(OB Is defined($options; "keyColumn")))
  // 1-based visible positional row keys ("1", "2", ...), skipping hidden rows.
  $visibleIndex:=0
  For ($row; 1; $count)
   $hidden:=False
   If (Not(Is nil pointer($control)))
    If (Type($control->)=Boolean array)
     $hidden:=$control->{$row}
    Else
     $hidden:=($control->{$row} & lk row is hidden)#0
    End if
   End if
   If ($hidden)
    $binding.keys.push("_axb_hidden_"+String($row))
   Else
    $visibleIndex:=$visibleIndex+1
    $binding.keys.push(String($visibleIndex))
   End if
  End for
  ARRAY TO COLLECTION($binding.selected; $selection->)
  $binding.selectionPointer:=$selection
  $binding.controlPointer:=$control
  $binding.positionalKeys:=True
  $binding.identity:=$options.kind+":positional:"+String(Size of array($hierarchy))
  $binding.ok:=True
  return
 End if
 $keys:=OBJECT Get pointer(Object named; $options.keyColumn)
 If (Is nil pointer($keys))
  return
 End if
 If (New collection(Text array; Integer array; LongInt array).indexOf(Type($keys->))<0)
  return
 End if
 If (Size of array($keys->)#$count)
  If ($options.auto=True)
   $binding.loading:=True
  End if
  return
 End if
 ARRAY TO COLLECTION($binding.keys; $keys->)
 If (Type($keys->)#Text array)
  For ($row; 0; $count-1)
   $binding.keys[$row]:=String($binding.keys[$row]; "&xml")
  End for
 End if
 ARRAY TO COLLECTION($binding.selected; $selection->)
 $binding.keyPointer:=$keys
 $binding.keyType:=Type($keys->)
 $binding.keyObjectName:=$options.keyColumn
 $binding.selectionPointer:=$selection
 $binding.controlPointer:=$control
 $binding.identity:=$options.kind+":"+String(Type($keys->))+":"+String(Size of array($hierarchy))
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
 If ($positional & Not(OB Is defined($options; "keyProperty")))
  $sourceStore:=$dataClass.getDataStore().getInfo()
  $key:=""
  If ($sourceStore.type="4D Server")
   $key:=$sourceStore.connection.hostname
  End if
  $binding.identity:=JSON Stringify(New collection("entity"; "positional"; $dataClass.getInfo().name; $sourceStore.type; $sourceStore.localID; $key))
  $rawKeys:=New collection
  For ($row; 1; $count)
   $rawKeys.push(String($row))
  End for
  $binding.dataClass:=$dataClass
  $binding.positionalKeys:=True
 Else
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
 End if
Else
 If (Value type($source)#Is collection)
  return
 End if
 If ($positional & Not(OB Is defined($options; "keyProperty")))
  $property:=""
  $binding.identity:="collection:positional"
  $binding.positionalKeys:=True
  $rawKeys:=New collection
  $binding.itemsByKey:=New object
  For ($row; 1; $count)
   $rawKeys.push(String($row))
  End for
 Else
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
   If ($options.auto=True)
    $metaExpression:=""
   Else
    $binding.message:="Provide a meta Formula calling the existing row metadata expression"
    return
   End if
  Else
   $metaProperty:=Substring($metaExpression; 6)
  End if
 End if
End if
$binding.metaExpression:=$metaExpression
$binding.meta:=$options.meta
$binding.rowFlags:=New collection
$selected:=Null
If ($options.selection#Null)
 $selected:=$options.selection.call()
Else
 If (OB Is defined($options; "selectedSource") && (Form#Null) && OB Is defined(Form; $options.selectedSource))
  $selected:=Form[$options.selectedSource]
 Else
  If (OB Is defined($options; "currentSource") && (Form#Null) && OB Is defined(Form; $options.currentSource))
   If (Form[$options.currentSource]#Null)
    If ($entity)
     If (OB Instance of(Form[$options.currentSource]; 4D.Entity))
      $selected:=$dataClass.newSelection()
      $selected.add(Form[$options.currentSource])
     End if
    Else
     $selected:=New collection(Form[$options.currentSource])
    End if
   End if
  Else
   If ((LISTBOX Get property(*; $name; lk selection mode)>0) & Not($options.auto=True) & Not($positional))
    $binding.message:="Provide a Formula reading the list box's selected items"
    return
   End if
  End if
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
  If ($binding.positionalKeys=True)
   $selectedKeys:=$selected.extract($dataClass.getInfo().primaryKey; ck keep null)
  Else
   $selectedKeys:=$selected.extract($property; ck keep null)
  End if
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
  If ($binding.positionalKeys=True)
   $key:=String($row+1)
  Else
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
  End if
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
   If ($binding.positionalKeys=True)
    $value:=$source[$row][$dataClass.getInfo().primaryKey]
   End if
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
