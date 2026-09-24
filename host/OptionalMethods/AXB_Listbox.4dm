// Read a flat native list box in its owning form. Only allowlisted columns
// intersecting the viewport contribute text. Positions are never public IDs.
#DECLARE($options : Object) -> $result : Object
var $reply; $table; $column; $known; $node; $dataClass; $attribute; $sourceStore; $selectedStore : Object
var $columns; $keys; $nodes; $labels; $clip; $cell; $items; $selectedFlags : Collection
var $data; $item; $value; $selected : Variant
var $keysPtr; $selectionPtr; $controlPtr; $ptr : Pointer
var $name; $id; $key; $label; $columnName : Text
var $count; $row; $i; $position; $flags; $left; $top; $right; $bottom; $lockedRight; $locked; $mode : Integer
var $hierarchical; $array; $entity; $visible; $enabled : Boolean
ARRAY TEXT($objects; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
ARRAY TEXT($parts; 0)
$result:=New object("ok"; False; "error"; "unsupportedListbox"; "nodes"; New collection; "positions"; New object; "selectedIDs"; New collection)
If (($options=Null) | (Value type($options)#Is object))
 return
End if
$name:=$options.objectName
$id:=$options.id
FORM GET OBJECTS($objects; $variables; $pages; Form all pages+Form inherited)
If (Find in array($objects; $name)<1)
 $result.error:="unknownControl"
 return
End if
FORM GET OBJECTS($objects; $variables; $pages; Form current page+Form inherited)
If (Find in array($objects; $name)<1)
 $result.ok:=True
 OB REMOVE($result; "error")
 return
End if
If (OBJECT Get type(*; $name)#Object type listbox)
 return
End if
$reply:=AXB_Host("node"; New object("objectName"; $name; "id"; $id; "role"; "table"; "label"; $options.label; "value"; ""; "enabled"; True))
If (Not($reply.ok=True))
 $result.error:=$reply.error
 return
End if
$table:=$reply.node
$result.nodes.push($table)
// A disabled explanatory table is usable even when this particular layout is
// unsupported. Do not detach the rest of a form for a grid's adapter limit.
$result.ok:=True
$table.enabled:=False
$table.label:=Substring($options.label; 1; 400)+": unsupported list box layout"
$array:=$options.kind="array"
$entity:=$options.kind="entity"
If (Not($array | $entity | ($options.kind="collection")))
 return
End if
$count:=LISTBOX Get number of rows(*; $name)
If (($count<0) | ($count>10000))
 $table.label:=Substring($options.label; 1; 400)+": filter to 10000 rows or fewer"
 return
End if
// Entity reads can touch the datastore. Bound this family more tightly than
// in-memory arrays/collections; larger result sets need application paging.
If ($entity & ($count>1000))
 $table.label:=Substring($options.label; 1; 400)+": filter to 1000 entities or fewer"
 return
End if
$mode:=LISTBOX Get property(*; $name; lk selection mode)
$result.selectionMode:=$mode
$controlPtr:=Null
If ($array)
 LISTBOX GET HIERARCHY(*; $name; $hierarchical)
 If ($hierarchical)
  return
 End if
 $selectionPtr:=OBJECT Get pointer(Object named; $name)
 $keysPtr:=OBJECT Get pointer(Object named; $options.keyColumn)
 If (Is nil pointer($selectionPtr) | Is nil pointer($keysPtr))
  return
 End if
 If ((Type($selectionPtr->)#Boolean array) | (Type($keysPtr->)#Text array))
  return
 End if
 If ((Size of array($selectionPtr->)#$count) | (Size of array($keysPtr->)#$count))
  return
 End if
 $controlPtr:=LISTBOX Get array(*; $name; lk control array)
 If (Not(Is nil pointer($controlPtr)))
  If ((Type($controlPtr->)#LongInt array) | (Size of array($controlPtr->)#$count))
   return
  End if
 End if
Else
 If ((Value type($options.keyProperty)#Is text) | ($options.keyProperty=""))
  return
 End if
 $data:=OBJECT Get value($name)
 If ($data=Null)
  return
 End if
 If ($entity)
  If (Value type($data)#Is object)
   return
  End if
  If (Not(OB Instance of($data; 4D.EntitySelection)))
   return
  End if
  $dataClass:=$data.getDataClass()
  $attribute:=$dataClass[$options.keyProperty]
  If (($attribute=Null) | (Value type($attribute)#Is object))
   return
  End if
  If (($attribute.kind#"storage") | (New collection("string"; "number").indexOf($attribute.type)<0))
   $table.label:=Substring($options.label; 1; 400)+": key must be a stored text or integer attribute"
   return
  End if
 Else
  If (Value type($data)#Is collection)
   return
  End if
 End if
 If (($data.length#$count) | (LISTBOX Get property(*; $name; lk meta expression)#""))
  return
 End if
 If ((Value type($options.selection)#Is object) | ($options.selection=Null))
  return
 End if
 If (Not(OB Instance of($options.selection; 4D.Function)))
  return
 End if
 $selected:=$options.selection.call()
 If ($entity)
  If ($selected=Null)
   $selected:=$data.getDataClass().newSelection()
  End if
  If (Value type($selected)#Is object)
   return
  End if
  If (Not(OB Instance of($selected; 4D.EntitySelection)))
   return
  End if
  // 4D returns fresh dataclass wrappers. Compare the documented datastore
  // identity and class name, not wrapper references or class names alone.
  $sourceStore:=$dataClass.getDataStore().getInfo()
  $selectedStore:=$selected.getDataClass().getDataStore().getInfo()
  If ((Compare strings($sourceStore.type; $selectedStore.type; sk char codes)#0) | (Compare strings($sourceStore.localID; $selectedStore.localID; sk char codes)#0) | (Compare strings($dataClass.getInfo().name; $selected.getDataClass().getInfo().name; sk char codes)#0))
   return
  End if
  If ($sourceStore.type="4D Server")
   If (Compare strings($sourceStore.connection.hostname; $selectedStore.connection.hostname; sk char codes)#0)
    return
   End if
  End if
 Else
  If ($selected=Null)
   $selected:=New collection
  End if
  If (Value type($selected)#Is collection)
   return
  End if
 End if
 If (Compare strings(LISTBOX Get column formula(*; $options.keyColumn); "This."+$options.keyProperty; sk char codes)#0)
  return
 End if
End if
LISTBOX GET OBJECTS(*; $name; $parts)
If (Find in array($parts; $options.keyColumn)<1)
 return
End if
If ((Value type($options.labelColumns)#Is collection) | ($options.labelColumns=Null))
 return
End if
If (($options.labelColumns.length<1) | ($options.labelColumns.length>16))
 return
End if
$columns:=New collection
For each ($column; $options.labelColumns)
 If (($column=Null) | (Value type($column.objectName)#Is text))
  return
 End if
 $columnName:=$column.objectName
 $position:=Find in array($parts; $columnName)
 If (($position<1) | (OBJECT Get type(*; $columnName)#Object type listbox column))
  return
 End if
 // Formatted/masked/multistyle values need an application-specific adapter;
 // publishing their raw backing values would expose different information.
 If ((OBJECT Get format(*; $columnName)#"") | (LISTBOX Get property(*; $columnName; lk multi style)=1))
  return
 End if
 $node:=New object("name"; $columnName; "number"; Int(($position-1)/3)+1; "property"; $column.property)
 If ($array)
  $ptr:=OBJECT Get pointer(Object named; $columnName)
  If (Is nil pointer($ptr))
   return
  End if
  If (Type($ptr->)#Text array)
   return
  End if
  If (Size of array($ptr->)#$count)
   return
  End if
  $node.pointer:=$ptr
 Else
  If ((Value type($column.property)#Is text) | ($column.property=""))
   return
  End if
  If (Compare strings(LISTBOX Get column formula(*; $columnName); "This."+$column.property; sk char codes)#0)
   return
  End if
  If ($entity)
   $attribute:=$dataClass[$column.property]
   If (($attribute=Null) | (Value type($attribute)#Is object))
    return
   End if
   If (($attribute.kind#"storage") | ($attribute.type#"string"))
    $table.label:=Substring($options.label; 1; 400)+": labels must be stored text attributes"
    return
   End if
  End if
 End if
 $columns.push($node)
End for each
// Validate identities over the entire binding, including offscreen rows.
// Duplicate offscreen keys must never alias a visible row after scrolling.
$keys:=New collection
$items:=New collection
$selectedFlags:=New collection
$known:=New object
For ($row; 1; $count)
 If ($array)
  $value:=$keysPtr->{$row}
 Else
  $item:=$data[$row-1]
  If ((Value type($item)#Is object) | ($item=Null))
   $table.label:=Substring($options.label; 1; 400)+": reload missing rows before selecting"
   return
  End if
  $items.push($item)
  $value:=$item[$options.keyProperty]
 End if
 If ($entity & (Value type($value)=Is real))
  If (($value#Int($value)) | ($value<(-2147483648)) | ($value>2147483647))
   $table.label:=Substring($options.label; 1; 400)+": numeric keys must be 32-bit integers"
   return
  End if
  $value:="n:"+String($value; "&xml")
 End if
 If (Value type($value)#Is text)
  return
 End if
 $key:=$value
 If (($key="") | (Length($id+"."+$key)>78) | OB Is defined($known; $key))
  $table.label:=Substring($options.label; 1; 400)+": row keys must be unique nonempty text"
  return
 End if
 $known[$key]:=True
 $keys.push($key)
 If ($array)
  If ($selectionPtr->{$row})
   $result.selectedIDs.push($id+"."+$key)
  End if
 Else
  If ($entity)
   $visible:=$selected.contains($item)
  Else
   $visible:=$selected.indexOf($item)>=0
  End if
  If ($visible)
   $result.selectedIDs.push($id+"."+$key)
  End if
  $selectedFlags.push($visible)
 End if
End for
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
If (LISTBOX Get property(*; $name; lk display header)=1)
 $top:=$top+LISTBOX Get headers height(*; $name; lk pixels)
End if
If (LISTBOX Get property(*; $name; lk display footer)=1)
 $bottom:=$bottom-LISTBOX Get footers height(*; $name; lk pixels)
End if
$right:=$right-New collection(0; LISTBOX Get property(*; $name; lk ver scrollbar width)).max()
$bottom:=$bottom-New collection(0; LISTBOX Get property(*; $name; lk hor scrollbar height)).max()
$clip:=New collection($left; $top; New collection(0; $right-$left).max(); New collection(0; $bottom-$top).max())
$locked:=LISTBOX Get locked columns(*; $name)
$lockedRight:=$left
If ($count>0)
 For ($i; 1; $locked)
  LISTBOX GET CELL COORDINATES(*; $name; $i; 1; $left; $top; $right; $bottom)
  $lockedRight:=New collection($lockedRight; $right).max()
 End for
End if
$nodes:=New collection
For ($row; 1; $count)
 $flags:=0
 If (Not(Is nil pointer($controlPtr)))
  $flags:=$controlPtr->{$row}
 End if
 $visible:=($flags>=0) & ($flags<=7) & (New collection(1; 3; 5; 7).indexOf($flags)<0)
 $enabled:=($mode>0) & ($flags=0)
 If ($visible)
  $labels:=New collection
  For each ($column; $columns)
   If (OBJECT Get visible(*; $column.name))
    LISTBOX GET CELL COORDINATES(*; $name; $column.number; $row; $left; $top; $right; $bottom)
    If ($column.number>$locked)
     $left:=New collection($left; $lockedRight).max()
    End if
    $cell:=New collection($left; $top; New collection(0; $right-$left).max(); New collection(0; $bottom-$top).max())
    If (AXB_Intersects($cell; $clip))
     If ($array)
      $ptr:=$column.pointer
      $value:=$ptr->{$row}
     Else
      $item:=$items[$row-1]
      $value:=$item[$column.property]
      If ($entity & ($value=Null))
       $value:=""
      End if
     End if
     If (Value type($value)#Is text)
      return
     End if
     If ($value#"")
      $labels.push($value)
     End if
    End if
   End if
  End for each
  If ($labels.length>0)
   $label:=$labels.join("; ")
   If ((Length($label)>512) | ($nodes.length>=100))
    $table.label:=Substring($options.label; 1; 400)+": visible rows exceed adapter limits"
    return
   End if
   $key:=$id+"."+$keys[$row-1]
   $node:=New object("id"; $key; "parent"; $id; "role"; "row"; "label"; $label; "value"; $label; "index"; $nodes.length; "visible"; $table.visible; "enabled"; $enabled & OBJECT Get enabled(*; $name); "selected"; False; "frame"; New collection($clip[0]; $top; $clip[2]; $bottom-$top); "clip"; $clip)
   If ($array)
    $node.selected:=$selectionPtr->{$row}
   Else
    $node.selected:=$selectedFlags[$row-1]
   End if
   $nodes.push($node)
   $result.positions[$key]:=$row
  End if
 End if
End for
$table.enabled:=OBJECT Get enabled(*; $name) & ($mode>0)
$table.label:=$options.label
$result.nodes:=$result.nodes.concat($nodes)
OB REMOVE($result; "error")
