// Array-backed AreaList provider. Vendor calls run in the owning host form;
// native accessibility readers consume only the published descriptor/pages.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $node; $columnsByID; $column; $known; $positions; $frames; $headers; $rowFrames; $descriptor; $item; $cell; $editor; $metadata : Object
var $rows; $columns; $selected; $visible; $rowLayout; $columnLayout; $bindings; $allKeys : Collection
var $handle; $keys; $previous : Pointer
var $area; $error; $count; $columnCount; $row; $i; $number; $originX; $originY; $locked; $keyColumn; $entryRow; $entryColumn; $display; $entry; $kind; $visibleIndex : Integer
var $left; $top; $width; $height; $scrollTop; $scrollLeft; $offset; $columnLeft; $columnWidth; $rowTop; $rowHeight; $headerHeight; $lockedRight; $x; $y; $right; $bottom : Real
var $name; $key; $id; $label; $orderState : Text
var $rebound; $typed; $editable; $checkbox; $focusable; $positional; $calculated; $fallbackEmpty : Boolean
ARRAY LONGINT($grid; 0)
ARRAY LONGINT($selection; 0)
ARRAY LONGINT($levels; 0)
ARRAY LONGINT($expanded; 0)
ARRAY POINTER($sources; 0)
If ($operation="ping")
 return New object("ok"; True; "provider"; "areaList")
End if
If ($operation="probe")
 $result:=New object("ok"; True; "isAreaList"; False; "rows"; 0)
 If (($options=Null) || (Value type($options.objectName)#Is text))
  return
 End if
 $name:=$options.objectName
 If (OBJECT Get type(*; $name)#Object type plugin area)
  return
 End if
 $handle:=OBJECT Get pointer(Object named; $name)
 If (Is nil pointer($handle) || (New collection(Is real; Is integer; Is longint).indexOf(Value type($handle->))<0))
  return
 End if
 $area:=$handle->
 If (($area=0) || (AL_GetAreaLongProperty($area; ALP_Area_IsArea)#1))
  return
 End if
 If ((AL_GetAreaLongProperty($area; ALP_Area_Transposed)#0) | (AL_GetAreaLongProperty($area; ALP_Area_SelType)#0) | (AL_GetAreaLongProperty($area; ALP_Area_RowsInGrid)#1) | (AL_GetAreaLongProperty($area; ALP_Area_DontSortArrays)#0))
  return
 End if
 $error:=AL_GetObjects2($area; ALP_Object_Hierarchy; $levels; $expanded)
 If (($error#0) | (Size of array($levels)>0) | (AL_GetAreaLongProperty($area; ALP_Area_AutoHierarchy)#0))
  return
 End if
 $result.isAreaList:=True
 $result.rows:=AL_GetAreaLongProperty($area; ALP_Area_Rows)
 return
End if
$result:=New object("ok"; True; "nodes"; New collection; "pages"; New collection; "status"; "rejected"; "message"; "AreaList is unavailable")
If ($operation#"describe")
 return AXB_ALPGridAction($operation; $options; $state; $request)
End if
$state.valid:=False
$name:=$options.objectName
$node:=AXB_ALPNode($name; $options.id; $options.label)
$node.objectName:=$name
$node.enabled:=False
$node.label:=$options.label+": grid provider requires a flat array-backed AreaList"
$result.nodes.push($node)
If (OBJECT Get type(*; $name)#Object type plugin area)
 return
End if
$handle:=OBJECT Get pointer(Object named; $name)
If (Is nil pointer($handle))
 return
End if
If (New collection(Is real; Is integer; Is longint).indexOf(Value type($handle->))<0)
 return
End if
$area:=$handle->
If (($area=0) || (AL_GetAreaLongProperty($area; ALP_Area_IsArea)#1))
 return
End if
If ((AL_GetAreaLongProperty($area; ALP_Area_Transposed)#0) | (AL_GetAreaLongProperty($area; ALP_Area_SelType)#0) | (AL_GetAreaLongProperty($area; ALP_Area_RowsInGrid)#1) | (AL_GetAreaLongProperty($area; ALP_Area_DontSortArrays)#0))
 return
End if
$error:=AL_GetObjects2($area; ALP_Object_Hierarchy; $levels; $expanded)
If (($error#0) | (Size of array($levels)>0) | (AL_GetAreaLongProperty($area; ALP_Area_AutoHierarchy)#0))
 return
End if
$columnCount:=AL_GetAreaLongProperty($area; ALP_Area_Columns)
$count:=AL_GetAreaLongProperty($area; ALP_Area_Rows)
$positional:=($options.positionalKeys=True) & Not(OB Is defined($options; "keys"))
If (Not($positional))
 If (Value type($options.keys)#Is pointer)
  return
 End if
 $keys:=$options.keys
 If (Is nil pointer($keys))
  return
 End if
 If (New collection(Text array; Integer array; LongInt array).indexOf(Type($keys->))<0)
  $node.label:=$options.label+": keys require a Text, Integer or LongInt array"
  return
 End if
 If (Size of array($keys->)#$count)
  return
 End if
End if
$error:=AL_GetObjects($area; ALP_Object_Columns; $sources)
If (($error#0) | (Size of array($sources)#$columnCount))
 return
End if
$keyColumn:=0
If (Not($positional))
 If (OB Is defined($options; "keyColumn"))
  $keyColumn:=$options.keyColumn
  If (($keyColumn<1) | ($keyColumn>$columnCount))
   $node.label:=$options.label+": key column binding changed"
   return
  End if
  If ($sources{$keyColumn}#$keys)
   $node.label:=$options.label+": key column binding changed"
   return
  End if
 Else
  // Legacy vendor setup can omit blank columns and shift physical numbers.
  // Resolve the caller's key array against the actual live column bindings.
  For ($i; 1; $columnCount)
   If ($sources{$i}=$keys)
    If ($keyColumn#0)
     $node.label:=$options.label+": key array has more than one column binding"
     return
    End if
    $keyColumn:=$i
   End if
  End for
  If ($keyColumn=0)
   $node.label:=$options.label+": key array is not bound to the area"
   return
  End if
 End if
End if
$error:=AL_GetObjects($area; ALP_Object_Grid; $grid)
If ($error#0)
 return
End if
$error:=AL_GetObjects($area; ALP_Object_Selection; $selection)
If ($error#0)
 return
End if
// Source text is unavailable for calculated columns. Compare the actual
// pointers already returned by the vendor, retaining them only in the host.
$rebound:=False
If ($state.binding#Null)
 $rebound:=($state.area#$area) | ($state.binding.length#$columnCount) | ($state.positionalKeys#$positional)
 If (Not($positional) & Not($rebound))
  $previous:=$state.keyPointer
  $rebound:=($previous#$keys)
 End if
End if
$bindings:=New collection
For ($i; 1; $columnCount)
 $bindings.push($sources{$i})
 If (($state.binding#Null) && Not($rebound))
  $previous:=$state.binding[$i-1]
  $rebound:=($previous#$sources{$i})
 End if
End for
If ($rebound)
 $state.generation:=Generate UUID
End if
$state.binding:=$bindings
If ($positional)
 OB REMOVE($state; "keyPointer")
Else
 $state.keyPointer:=$keys
End if
$state.positionalKeys:=$positional
$state.area:=$area
$originX:=0
$originY:=0
CONVERT COORDINATES($originX; $originY; XY Current form; XY Current window)
$left:=AL_GetAreaRealProperty($area; ALP_Area_ListLeft)-$originX
$top:=AL_GetAreaRealProperty($area; ALP_Area_ListTop)-$originY
$width:=AL_GetAreaRealProperty($area; ALP_Area_ListWidth)
$height:=AL_GetAreaRealProperty($area; ALP_Area_ListHeight)
$scrollTop:=AL_GetAreaRealProperty($area; ALP_Area_ScrollTop)
$scrollLeft:=AL_GetAreaRealProperty($area; ALP_Area_ScrollLeft)
$locked:=AL_GetAreaLongProperty($area; ALP_Area_ColsLocked)
$headerHeight:=0
If (AL_GetAreaLongProperty($area; ALP_Area_HideHeaders)=0)
 $headerHeight:=AL_GetRowRealProperty($area; 0; ALP_Row_Height)
End if
$editable:=(AL_GetAreaLongProperty($area; ALP_Area_ReadOnly)%2)=0
$columns:=New collection
$columnLayout:=New collection
$columnsByID:=New object
$headers:=New object
$known:=New object
$offset:=0
$lockedRight:=$left
For ($i; 1; Size of array($grid))
 $number:=$grid{$i}
 If (($number<1) | ($number>$columnCount))
  return
 End if
 If (AL_GetColumnLongProperty($area; $number; ALP_Column_Visible)=1)
  // Repeated columns and multiline/spanned grids need their own cell map.
  $id:="column."+String($number)
  If (OB Is defined($known; $id))
   return
  End if
  $known[$id]:=True
  $columnWidth:=AL_GetColumnRealProperty($area; $number; ALP_Column_Width)
  If ($columnWidth<=0)
   continue
  End if
  $columnLeft:=$left+$offset
  If ($i>$locked)
   $columnLeft:=$columnLeft-$scrollLeft
  Else
   $lockedRight:=$columnLeft+$columnWidth
  End if
  $offset:=$offset+$columnWidth
  $metadata:=New object
  If ($options.columns#Null)
   If ($options.columns[String($number)]#Null)
    $metadata:=$options.columns[String($number)]
   End if
  End if
  // Decorative spacers still occupy their real width in the vendor grid.
  If ($metadata.decorative=True)
   continue
  End if
  $calculated:=False
  $fallbackEmpty:=False
  If (Is nil pointer($sources{$number}))
   If ($metadata.value=Null)
    $fallbackEmpty:=True
   End if
  Else
   If ($metadata.value=Null)
    If (AL_GetColumnLongProperty($area; $number; ALP_Column_Calculated)#0)
     $calculated:=True
    Else
     If (New collection(Text array; Real array; Integer array; LongInt array; Boolean array; Date array; Time array).indexOf(Type($sources{$number}->))<0)
      $fallbackEmpty:=True
     End if
    End if
   Else
    If (New collection(Text array; Real array; Integer array; LongInt array; Boolean array; Date array; Time array; Picture array).indexOf(Type($sources{$number}->))<0)
     return
    End if
   End if
   If (Not($fallbackEmpty) & Not($calculated) & (Size of array($sources{$number}->)#$count))
    return
   End if
  End if
  $label:=AL_GetColumnTextProperty($area; $number; ALP_Column_HeaderText)
  If ($metadata.label#Null)
   $label:=$metadata.label
  End if
  If ($label="")
   $label:="Column "+String($columns.length+1)
  End if
  $kind:=-1
  If (Not(Is nil pointer($sources{$number})))
   $kind:=Type($sources{$number}->)
  End if
  $display:=AL_GetColumnLongProperty($area; $number; ALP_Column_DisplayControl)
  $entry:=AL_GetColumnLongProperty($area; $number; ALP_Column_EntryControl)
  $checkbox:=Not($fallbackEmpty) & Not($calculated) & (New collection(Boolean array; Integer array; LongInt array).indexOf($kind)>=0) & (New collection(0; 1; 2; 4).indexOf($display)>=0) & (New collection(0; 1).indexOf($entry)>=0) & ($metadata.value=Null)
  $focusable:=$checkbox & (New collection(0; 1; 2).indexOf($display)>=0) & (AL_GetColumnLongProperty($area; $number; ALP_Column_FocusableCheckbox)=1)
  $typed:=Not($fallbackEmpty) & Not($calculated) & (New collection(Text array; Real array; Integer array; LongInt array; Date array; Time array).indexOf($kind)>=0)
  $typed:=$typed & Not($checkbox)
  $typed:=$typed & (AL_GetColumnLongProperty($area; $number; ALP_Column_Attributed)=0) & ($metadata.value=Null)
  $columns.push(New object("id"; $id; "label"; $label; "enabled"; True; "editable"; ($typed | $checkbox) & $editable))
  If ($metadata.automationKey#Null)
   $columns[$columns.length-1].automationKey:=$metadata.automationKey
  End if
  $columnLayout.push(New collection($columnLeft; $columnWidth))
  $column:=New object("number"; $number; "gridCell"; $i; "left"; $columnLeft; "width"; $columnWidth; "locked"; $i<=$locked; "typed"; $typed; "calculated"; $calculated; "fallbackEmpty"; $fallbackEmpty)
  $column.value:=$metadata.value
  $column.checkbox:=$checkbox
  $column.focusable:=$focusable
  $column.source:=$sources{$number}
  $columnsByID[$id]:=$column
  $x:=New collection($left; $columnLeft).max()
  If ($i>$locked)
   $x:=New collection($x; $lockedRight).max()
  End if
  $right:=New collection($left+$width; $columnLeft+$columnWidth).min()
  If (($right>$x) & ($headerHeight>0))
   $headers[$id]:=New collection($x; $top-$headerHeight; $right-$x; $headerHeight)
  End if
 End if
End for
$rows:=New collection
$rowLayout:=New collection
$selected:=New collection
$visible:=New collection
$frames:=New object
$positions:=New object
$known:=New object
$allKeys:=New collection
If (Not($positional))
 ARRAY TO COLLECTION($allKeys; $keys->)
Else
 For ($row; 1; $count)
  $allKeys.push("")
 End for
End if
$visibleIndex:=0
For ($row; 1; $count)
 If ($positional)
  If (AL_GetRowLongProperty($area; $row; ALP_Row_Hide)=0)
   $rowHeight:=AL_GetRowRealProperty($area; $row; ALP_Row_Height)
   If ($rowHeight<=0)
    $allKeys[$row-1]:="_axb_hidden_"+String($row)
    continue
   End if
   $visibleIndex:=$visibleIndex+1
   $key:=String($visibleIndex)
   $allKeys[$row-1]:=$key
  Else
   $allKeys[$row-1]:="_axb_hidden_"+String($row)
   continue
  End if
 Else
  If (Type($keys->)=Text array)
   $key:=$allKeys[$row-1]
  Else
   // Integer identity is normalized only in the descriptor. Keep the original
   // bound array and vendor sort/insert/delete behavior unchanged.
   $key:=String($allKeys[$row-1])
  End if
  $allKeys[$row-1]:=$key
  If (($key="") | (Length($key)>256) | OB Is defined($known; $key))
   $node.label:=$options.label+": row keys must be unique nonempty text"
   return
  End if
  $known[$key]:=True
 End if
 If (AL_GetRowLongProperty($area; $row; ALP_Row_Hide)=0)
  $rowHeight:=AL_GetRowRealProperty($area; $row; ALP_Row_Height)
  If ($rowHeight<=0)
   continue
  End if
  $rowTop:=$top+AL_GetRowRealProperty($area; $row; ALP_Row_RowOffset)-$scrollTop
  $rows.push($key)
  $rowLayout.push(New collection($rowTop; $rowHeight))
  $positions[$key]:=$row
  If (Find in array($selection; $row)>0)
   $selected.push($key)
  End if
  If (($rowTop<($top+$height)) & (($rowTop+$rowHeight)>$top))
   $rowFrames:=New object
   For each ($item; $columns)
    $column:=$columnsByID[$item.id]
    $x:=New collection($left; $column.left).max()
    If (Not($column.locked))
     $x:=New collection($x; $lockedRight).max()
    End if
    $right:=New collection($left+$width; $column.left+$column.width).min()
    $y:=New collection($top; $rowTop).max()
    $bottom:=New collection($top+$height; $rowTop+$rowHeight).min()
    If (($right>$x) & ($bottom>$y))
     $rowFrames[$item.id]:=New collection($x; $y; $right-$x; $bottom-$y)
    End if
   End for each
   If (OB Keys($rowFrames).length>0)
    $frames[$key]:=$rowFrames
    $visible.push($key)
   End if
  End if
 End if
End for
$orderState:=JSON Stringify(New collection($rows; $columns))
If (Compare strings($orderState; $state.orderState; sk char codes)#0)
 $state.order:=$state.order+1
 $state.orderState:=$orderState
End if
$descriptor:=New object("generation"; $state.generation; "order"; $state.order; "rows"; $rows; "columns"; $columns; "selected"; $selected; "visible"; $visible; "frames"; $frames; "headers"; $headers; "disabled"; New collection; "unselectable"; New collection; "actions"; New object("select"; True; "reveal"; True; "edit"; $editable))
If ($columns.length>0)
 $descriptor.layout:=New object("rows"; $rowLayout; "columns"; $columnLayout)
End if
$state.descriptor:=$descriptor
$state.positions:=$positions
$state.rowKeys:=$allKeys
$state.columns:=$columnsByID
$state.valid:=True
$node.grid:=$descriptor
$node.enabled:=OBJECT Get enabled(*; $name)
$node.label:=$options.label
If ((AL_GetAreaLongProperty($area; ALP_Area_Selected)=1) & (AL_GetAreaLongProperty($area; ALP_Area_EntryInProgress)=1))
 $entryRow:=AL_GetAreaLongProperty($area; ALP_Area_EntryRow)
 $entryColumn:=AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)
 If (($entryRow>0) & ($entryRow<=$count))
  $cell:=New object("objectName"; $name; "row"; $allKeys[$entryRow-1]; "column"; "column."+String($entryColumn); "generation"; $state.generation; "state"; $state)
  $column:=$state.columns[$cell.column]
  If (($column#Null) && $column.checkbox)
   $editor:=AXB_ALPGridValue($state; $column; $entryRow)
   If ($editor.ok & $editor.active)
    $node.editor:=New object("row"; $cell.row; "column"; $cell.column)
   End if
  Else
   $editor:=AXB_ALPEditor($cell; "read"; Null)
   If ($editor.active)
    $node.editor:=New object("row"; $cell.row; "column"; $cell.column; "value"; $editor.text; "selection"; New collection($editor.start-1; $editor.end-$editor.start))
   End if
  End if
 End if
End if
