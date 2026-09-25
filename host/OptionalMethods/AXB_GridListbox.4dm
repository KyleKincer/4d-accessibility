// Full logical listbox provider. Host pointers never enter JSON or the
// compiled component. Expensive values are read only for requested pages.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $node; $reply; $column; $columnsByID; $positions; $known; $frames; $headers; $rowFrames; $descriptor; $header; $page; $rowData; $cell; $item; $action; $binding; $attribute; $metadata : Object
var $rows; $columns; $selected; $disabled; $unselectable; $uneditable; $visible; $allKeys; $clip; $frame; $pageRows; $cells; $actual; $rowLayout; $columnLayout : Collection
var $keys; $selection; $control; $pointer; $previous; $headerPointer : Pointer
var $name; $key; $columnID; $columnName; $orderState; $text; $expression; $property : Text
var $count; $row; $i; $c; $first; $scrollColumn; $flags; $left; $top; $right; $bottom; $bodyTop; $lockedRight; $locked; $headerHeight; $sortValue : Integer
var $hierarchical; $enabled; $rebound; $singleClick; $sortable; $headerClick : Boolean
var $selectionMode : Integer
$result:=New object("ok"; False; "error"; "unsupportedLogicalListbox"; "status"; "rejected"; "message"; "Grid is unavailable"; "nodes"; New collection; "pages"; New collection)
$name:=$options.objectName
If ($operation#"describe")
 return AXB_GridListboxAction($operation; $options; $state; $request)
End if
$state.valid:=False
$state.editingIssues:=New collection
ARRAY TEXT($parts; 0)
ARRAY LONGINT($headerEvents; 0)
ARRAY LONGINT($columnEvents; 0)
$reply:=AXB_Host("node"; New object("objectName"; $name; "id"; $options.id; "role"; "table"; "label"; $options.label; "value"; ""; "enabled"; True))
If (Not($reply.ok=True))
 return $reply
End if
$node:=$reply.node
$node.objectName:=$name
$result.ok:=True
$result.nodes.push($node)
$node.enabled:=False
If ($options.meta#Null)
 If (Not(OB Is defined($state; "metaExpression")))
  $state.metaExpression:=LISTBOX Get property(*; $name; lk meta expression)
 End if
 If (Compare strings(LISTBOX Get property(*; $name; lk meta expression); $state.metaExpression; sk char codes)#0)
  $node.label:=$options.label+": row metadata expression changed; restart with its matching Formula"
  return
 End if
End if
$binding:=AXB_GridBinding($options)
If (Not($binding.ok))
 $node.label:=$options.label+": "+$binding.message
 return
End if
$count:=$binding.count
$keys:=Null
$selection:=Null
$control:=Null
If ($options.kind="array")
 $keys:=$binding.keyPointer
 $selection:=$binding.selectionPointer
 $control:=$binding.controlPointer
End if
LISTBOX GET OBJECTS(*; $name; $parts)
$sortable:=LISTBOX Get property(*; $name; lk sortable)=lk yes
OBJECT GET EVENTS(*; $name; $headerEvents)
$headerClick:=Find in array($headerEvents; On Header Click)>0
If ($options.columns#Null)
 For each ($columnName; $options.columns)
  $i:=0
  For ($c; 1; Size of array($parts); 3)
   If (Compare strings($parts{$c}; $columnName; sk char codes)=0)
    $i:=$c
    break
   End if
  End for
  If ($i=0)
   $node.label:=$options.label+": unknown column description "+$columnName
   return
  End if
 End for each
End if
If (($options.kind="array") && (Find in array($parts; $options.keyColumn)<1))
 return
End if
$columns:=New collection
$columnLayout:=New collection
$columnsByID:=New object
For ($i; 1; Size of array($parts); 3)
 $columnName:=$parts{$i}
 If (OBJECT Get visible(*; $columnName))
  $metadata:=New object
  If (($options.columns#Null) && ($options.columns[$columnName]#Null))
   $metadata:=$options.columns[$columnName]
  End if
  If ((($metadata.decorative=True) | ($metadata.value#Null)) & OBJECT Get enterable(*; $columnName))
   $state.editingIssues.push($columnName)
  End if
  // Omitted columns keep their actual layout width in 4D.
  If ($metadata.decorative=True)
   continue
  End if
  $pointer:=Null
  $property:=""
  $expression:=""
  $enabled:=OBJECT Get enterable(*; $columnName) & (OBJECT Get font(*; $columnName)#"%password")
  If ($options.kind="array")
   $pointer:=OBJECT Get pointer(Object named; $columnName)
   If (Is nil pointer($pointer))
    $node.label:=$options.label+": "+$columnName+" has no array binding"
    return
   End if
   If (New collection(Text array; Real array; Integer array; LongInt array; Boolean array; Date array; Time array).indexOf(Type($pointer->))<0)
    If ($metadata.value=Null)
     $node.label:=$options.label+": "+$columnName+" needs a displayed-value description"
     return
    End if
    If (New collection(Picture array; Object array).indexOf(Type($pointer->))<0)
     $node.label:=$options.label+": "+$columnName+" has an unsupported array binding"
     return
    End if
   End if
   If (Size of array($pointer->)#$count)
    $node.label:=$options.label+": "+$columnName+" has a different row count"
    return
   End if
  Else
   $expression:=LISTBOX Get column formula(*; $columnName)
   If ($metadata.value=Null)
    If (Not(Match regex("^This[.][[:alpha:]_][[:alnum:]_]*$"; $expression)))
     $node.label:=$options.label+": "+$columnName+" needs a displayed-value description"
     return
    End if
    $property:=Substring($expression; 6)
    If ($options.kind="entity")
     $attribute:=$binding.dataClass[$property]
     If (($attribute=Null) || ($attribute.kind#"storage") || (New collection("string"; "number"; "date"; "bool").indexOf($attribute.type)<0))
      $node.label:=$options.label+": "+$columnName+" needs a displayed-value description"
      return
     End if
     $enabled:=$enabled & Not($attribute.readOnly=True)
    End if
   End if
  End if
  If ((LISTBOX Get property(*; $columnName; lk multi style)=1) & ($metadata.value=Null))
   $node.label:=$options.label+": "+$columnName+" needs a styled-value description"
   return
  End if
  $enabled:=$enabled & ($metadata.value=Null)
  $columnID:=$columnName
  $text:=OBJECT Get title(*; $parts{$i+1})
  If ($text="")
   $text:=$columnName
  End if
  If ($metadata.label#Null)
   $text:=$metadata.label
  End if
  OBJECT GET EVENTS(*; $columnName; $columnEvents)
  $sortValue:=0
  $headerPointer:=OBJECT Get pointer(Object named; $parts{$i+1})
  If (Not(Is nil pointer($headerPointer)))
   If (New collection(Is real; Is longint).indexOf(Value type($headerPointer->))>=0)
    $sortValue:=$headerPointer->
   End if
  End if
  $header:=New object("visible"; LISTBOX Get property(*; $name; lk display header)=lk yes; "enabled"; OBJECT Get enabled(*; $parts{$i+1}); "press"; $sortable | $headerClick | (Find in array($columnEvents; On Header Click)>0); "sortable"; $sortable | ($sortValue>0); "sort"; "none")
  Case of
   : ($sortValue=1)
    $header.sort:="ascending"
   : ($sortValue=2)
    $header.sort:="descending"
  End case
  $columns.push(New object("id"; $columnID; "label"; $text; "enabled"; OBJECT Get enabled(*; $columnName); "editable"; $enabled; "header"; $header))
  $column:=New object("name"; $columnName; "number"; Int(($i-1)/3)+1; "property"; $property; "format"; OBJECT Get format(*; $columnName); "protected"; OBJECT Get font(*; $columnName)="%password")
  $column.headerName:=$parts{$i+1}
  $column.header:=$header
  $column.display:=LISTBOX Get property(*; $columnName; lk display type)
  $column.value:=$metadata.value
  $column.expression:=$expression
  $column.editable:=$enabled
  If ($options.kind="array")
   $column.pointer:=$pointer
  End if
  $columnsByID[$columnID]:=$column
  If ($count>0)
   LISTBOX GET CELL COORDINATES(*; $name; $column.number; 1; $left; $top; $right; $bottom)
  Else
   OBJECT GET COORDINATES(*; $columnName; $left; $top; $right; $bottom)
  End if
  $columnLayout.push(New collection($left; $right-$left))
 End if
End for
$rows:=New collection
$rowLayout:=New collection
$selected:=New collection
$disabled:=New collection
$unselectable:=New collection
$uneditable:=New collection
$selectionMode:=LISTBOX Get property(*; $name; lk selection mode)
$singleClick:=LISTBOX Get property(*; $name; lk single click edit)=lk yes
$positions:=New object
$known:=New object
$allKeys:=$binding.keys
For ($row; 1; $count)
 $key:=$allKeys[$row-1]
 If (($key="") | (Length($key)>256) | OB Is defined($known; $key))
  $node.label:=$options.label+": row keys must be unique nonempty text"
  return
 End if
 $known[$key]:=True
 $flags:=0
 If (Not(Is nil pointer($control)))
  If (Type($control->)=Boolean array)
   // Legacy hidden-row arrays use True for hidden, False for visible.
   $flags:=Num($control->{$row})
  Else
   $flags:=$control->{$row}
  End if
 Else
  If ($binding.rowFlags#Null)
   $flags:=$binding.rowFlags[$row-1]
  End if
 End if
 If (($flags<0) | ($flags>7))
  return
 End if
 If (New collection(1; 3; 5; 7).indexOf($flags)<0)
  $rows.push($key)
  If ($columns.length>0)
   $column:=$columnsByID[$columns[0].id]
   LISTBOX GET CELL COORDINATES(*; $name; $column.number; $row; $left; $top; $right; $bottom)
   $rowLayout.push(New collection($top; $bottom-$top))
  End if
  $positions[$key]:=$row
  If ($binding.selected[$row-1])
   $selected.push($key)
  End if
  If (New collection(2; 6).indexOf($flags)>=0)
   $disabled.push($key)
   $uneditable.push($key)
  End if
  If ((New collection(4; 6).indexOf($flags)>=0) & ($selectionMode#lk none))
   $unselectable.push($key)
   If (Not($singleClick) & (AXB_KeyIndex($uneditable; $key)<0))
    $uneditable.push($key)
   End if
  End if
 End if
End for
$orderState:=JSON Stringify(New collection($rows; $columns))
If (Compare strings($orderState; $state.orderState; sk char codes)#0)
 $state.order:=$state.order+1
 $state.orderState:=$orderState
 $state.valueIssues:=New object
End if
$rebound:=False
If ($state.binding#Null)
 $rebound:=Compare strings($binding.identity; $state.binding.identity; sk char codes)#0
 If ($options.kind="array")
  If (Value type($state.keyPointer)=Is pointer)
   $previous:=$state.keyPointer
   $rebound:=$rebound | ($previous#$keys)
   $previous:=$state.selectionPointer
   $rebound:=$rebound | ($previous#$selection)
   For each ($columnID; $columnsByID)
    If (($state.columns[$columnID]#Null) && (Value type($state.columns[$columnID].pointer)=Is pointer))
     $previous:=$state.columns[$columnID].pointer
     $pointer:=$columnsByID[$columnID].pointer
     $rebound:=$rebound | ($previous#$pointer)
    End if
   End for each
  End if
 Else
  $rebound:=$rebound | (Compare strings($binding.metaExpression; $state.binding.metaExpression; sk char codes)#0)
  If (($binding.meta#Null) | ($state.binding.meta#Null))
   $rebound:=$rebound | (New collection($binding.meta).indexOf($state.binding.meta)#0)
  End if
  If (($options.kind="collection") && ($state.binding.itemsByKey#Null))
   // Sorting/filtering can create a new collection of the same objects.
   // Preserve those identities; retire a reused key bound to another object.
   For each ($key; $binding.itemsByKey)
    If (OB Is defined($state.binding.itemsByKey; $key))
     $rebound:=$rebound | (New collection($binding.itemsByKey[$key]).indexOf($state.binding.itemsByKey[$key])#0)
    End if
   End for each
  End if
  For each ($columnID; $columnsByID)
   If ($state.columns[$columnID]#Null)
    $rebound:=$rebound | (Compare strings($state.columns[$columnID].expression; $columnsByID[$columnID].expression; sk char codes)#0)
   End if
  End for each
 End if
 For each ($columnID; $columnsByID)
  If ($state.columns[$columnID]#Null)
   If (($state.columns[$columnID].value#Null) | ($columnsByID[$columnID].value#Null))
    $rebound:=$rebound | (New collection($state.columns[$columnID].value).indexOf($columnsByID[$columnID].value)#0)
   End if
  End if
 End for each
End if
If ($rebound)
 $state.generation:=Generate UUID
 $state.valueIssues:=New object
End if
$state.binding:=$binding
$state.keyPointer:=$keys
$state.selectionPointer:=$selection
$state.positions:=$positions
$state.columns:=$columnsByID
$frames:=New object
$headers:=New object
$visible:=New collection
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
$headerHeight:=0
If (LISTBOX Get property(*; $name; lk display header)=1)
 $headerHeight:=LISTBOX Get headers height(*; $name; lk pixels)
End if
$bodyTop:=$top+$headerHeight
If (LISTBOX Get property(*; $name; lk display footer)=1)
 $bottom:=$bottom-LISTBOX Get footers height(*; $name; lk pixels)
End if
$right:=$right-New collection(0; LISTBOX Get property(*; $name; lk ver scrollbar width)).max()
$bottom:=$bottom-New collection(0; LISTBOX Get property(*; $name; lk hor scrollbar height)).max()
$clip:=New collection($left; $bodyTop; New collection(0; $right-$left).max(); New collection(0; $bottom-$bodyTop).max())
$locked:=LISTBOX Get locked columns(*; $name)
$lockedRight:=$left
If ($count>0)
 For ($i; 1; $locked)
  LISTBOX GET CELL COORDINATES(*; $name; $i; 1; $left; $top; $right; $bottom)
  $lockedRight:=New collection($lockedRight; $right).max()
 End for
End if
// Headers exist even when the data has no rows. Read their real geometry
// independently of cell frames, then clip scrolling columns behind locks.
If ($headerHeight>0)
 For each ($item; $columns)
  $column:=$columnsByID[$item.id]
  OBJECT GET COORDINATES(*; $column.headerName; $left; $top; $right; $bottom)
  If ($column.number>$locked)
   $left:=New collection($left; $lockedRight).max()
  End if
  $left:=New collection($left; $clip[0]).max()
  $right:=New collection($right; $clip[0]+$clip[2]).min()
  If ($right>$left)
   $headers[$item.id]:=New collection($left; $bodyTop-$headerHeight; $right-$left; $headerHeight)
  End if
 End for each
End if
OBJECT GET SCROLL POSITION(*; $name; $first; $scrollColumn)
$first:=New collection(1; $first).max()
For ($row; $first; $count)
 $key:=$allKeys[$row-1]
 If (OB Is defined($positions; $key))
  $rowFrames:=New object
  For each ($item; $columns)
   $column:=$columnsByID[$item.id]
   LISTBOX GET CELL COORDINATES(*; $name; $column.number; $row; $left; $top; $right; $bottom)
   If ($column.number>$locked)
    $left:=New collection($left; $lockedRight).max()
   End if
   $left:=New collection($left; $clip[0]).max()
   $right:=New collection($right; $clip[0]+$clip[2]).min()
   $frame:=New collection($left; $top; New collection(0; $right-$left).max(); New collection(0; $bottom-$top).max())
   If (AXB_Intersects($frame; $clip))
    $top:=New collection($top; $clip[1]).max()
    $bottom:=New collection($bottom; $clip[1]+$clip[3]).min()
    $rowFrames[$item.id]:=New collection($left; $top; $right-$left; $bottom-$top)
   End if
  End for each
  If (OB Keys($rowFrames).length>0)
   $visible.push($key)
   $frames[$key]:=$rowFrames
  End if
  If ($top>=($clip[1]+$clip[3]))
   break
  End if
 End if
End for
$descriptor:=New object("generation"; $state.generation; "order"; $state.order; "rows"; $rows; "columns"; $columns; "selected"; $selected; "visible"; $visible; "frames"; $frames; "headers"; $headers; "disabled"; $disabled; "unselectable"; $unselectable)
$descriptor.headerHeight:=$headerHeight
$descriptor.uneditable:=$uneditable
If ($columns.length>0)
 $descriptor.layout:=New object("rows"; $rowLayout; "columns"; $columnLayout)
End if
$descriptor.actions:=New object("select"; LISTBOX Get property(*; $name; lk selection mode)>0; "reveal"; True; "edit"; True)
// Cell position alone survives loss of focus. The root resolves this table's
// exact live instance before adopting its non-text cell position.
If (Not(Is editing text) & (OBJECT Get name(Object with focus)=$name))
 LISTBOX GET CELL POSITION(*; $name; $c; $row)
 If (($row>0) & ($row<=$count))
  $key:=$allKeys[$row-1]
  If (OB Is defined($positions; $key))
   For each ($columnID; $columnsByID)
    If ($columnsByID[$columnID].number=$c)
     $node.cellFocus:=New object("row"; $key; "column"; $columnID)
    End if
   End for each
  End if
 End if
End if
$state.descriptor:=$descriptor
$node.grid:=$descriptor
$node.enabled:=OBJECT Get enabled(*; $name)
$node.label:=$options.label
$state.valid:=True
OB REMOVE($result; "error")
