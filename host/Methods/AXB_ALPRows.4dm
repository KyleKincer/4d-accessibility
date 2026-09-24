// Selection-only adapter for explicitly described flat, array-backed AreaList grids.
// Column sources and bound keys are rechecked on every snapshot. No column contents
// are published unless the host lists that column and the vendor marks it visible.
#DECLARE($area : Integer; $objectName : Text; $keys : Pointer; $options : Object) -> $nodes : Collection
var $table; $node; $column; $known : Object
var $row; $error; $rowCount; $originX; $originY : Integer
var $left; $top; $width; $height; $rowTop; $rowHeight; $scrollTop : Real
var $rowID; $label; $text; $reason : Text
var $rows; $labels : Collection
ARRAY LONGINT($selected; 0)
ARRAY LONGINT($levels; 0)
ARRAY LONGINT($expanded; 0)
$table:=AXB_ALPNode($objectName; $options.id; $options.label)
$nodes:=New collection($table)
$reason:="Unsupported AreaList layout"
If ((AL_GetAreaLongProperty($area; ALP_Area_Compatibility)#1) | (AL_GetAreaLongProperty($area; ALP_Area_Columns)#$options.columnCount) | (AL_GetAreaLongProperty($area; ALP_Area_Transposed)#0) | (AL_GetAreaLongProperty($area; ALP_Area_SelType)#0))
 $table.enabled:=False
 $table.label:=$reason
 return
End if
// A flat area has no hierarchy object. Asking ALP_Row_Level for one of its
// rows raises ALP_Err_InvalidRequest and TRACE in interpreted mode. The array
// getter safely returns an empty hierarchy and an explicit result code.
$error:=AL_GetObjects2($area; ALP_Object_Hierarchy; $levels; $expanded)
If (($error#0) | (Size of array($levels)>0) | (AL_GetAreaLongProperty($area; ALP_Area_AutoHierarchy)#0))
 $table.enabled:=False
 $table.label:="Hierarchical grids are not supported by this row adapter"
 return
End if
If (Compare strings(AL_GetColumnTextProperty($area; $options.keyColumn; ALP_Column_Source); $options.keySource; sk char codes)#0)
 $table.enabled:=False
 $table.label:="Grid key column changed"
 return
End if
For each ($column; $options.labelColumns)
 If (($column.column<1) | ($column.column>$options.columnCount))
  $table.enabled:=False
  $table.label:="Invalid grid label column"
  return
 End if
 If (Compare strings(AL_GetColumnTextProperty($area; $column.column; ALP_Column_Source); $column.source; sk char codes)#0)
  $table.enabled:=False
  $table.label:="Grid label column changed"
  return
 End if
End for each
$rowCount:=Size of array($keys->)
If (($rowCount>200) | ($rowCount#AL_GetAreaLongProperty($area; ALP_Area_Rows)))
 $table.enabled:=False
 $table.label:="Grid row count or key mapping is unsupported"
 return
End if
$error:=AL_GetObjects($area; ALP_Object_Selection; $selected)
If ($error#0)
 $table.enabled:=False
 $table.label:="Grid selection unavailable"
 return
End if
$left:=AL_GetAreaRealProperty($area; ALP_Area_ListLeft)
$top:=AL_GetAreaRealProperty($area; ALP_Area_ListTop)
// AreaList reports its viewport in window coordinates, including in subforms.
// The host description uses current-form coordinates; AXB_View adds the origin.
$originX:=0
$originY:=0
CONVERT COORDINATES($originX; $originY; XY Current form; XY Current window)
$left:=$left-$originX
$top:=$top-$originY
$width:=AL_GetAreaRealProperty($area; ALP_Area_ListWidth)
$height:=AL_GetAreaRealProperty($area; ALP_Area_ListHeight)
$scrollTop:=AL_GetAreaRealProperty($area; ALP_Area_ScrollTop)
$known:=New object
$rows:=New collection
For ($row; 1; $rowCount)
 $rowID:=$options.id+"."+$keys->{$row}
 If (($keys->{$row}="") | (Length($rowID)>78) | OB Is defined($known; $rowID) | (Compare strings(AL_GetCellTextProperty($area; $row; $options.keyColumn; ALP_Cell_FormattedValue); $keys->{$row}; sk char codes)#0))
  $table.enabled:=False
  $table.label:="Grid row identities are unavailable or ambiguous"
  return
 End if
 $known[$rowID]:=True
 // Check every key, including offscreen keys, but publish only viewport rows.
 // Hidden/offscreen data must not consume the shared window's node budget.
 $rowHeight:=AL_GetRowRealProperty($area; $row; ALP_Row_Height)
 $rowTop:=$top+AL_GetRowRealProperty($area; $row; ALP_Row_RowOffset)-$scrollTop
 If (($rowHeight>0) & ($rowTop<($top+$height)) & (($rowTop+$rowHeight)>$top) & (AL_GetRowLongProperty($area; $row; ALP_Row_Hide)=0))
 If ($rows.length>=100)
  $table.enabled:=False
  $table.label:="Grid viewport exceeds 100 visible rows"
  return
 End if
 $labels:=New collection
 For each ($column; $options.labelColumns)
  If ((AL_GetColumnLongProperty($area; $column.column; ALP_Column_Visible)=1) & (AL_GetCellLongProperty($area; $row; $column.column; ALP_Cell_Invisible)=0))
   $text:=AL_GetCellTextProperty($area; $row; $column.column; ALP_Cell_FormattedValue)
   If ($text#"")
    $labels.push($text)
   End if
  End if
 End for each
 $label:=$labels.join("; ")
 If (Length($label)>512)
  $table.enabled:=False
  $table.label:="Grid row label exceeds the supported length"
  return
 End if
 $node:=New object("id"; $rowID; "parent"; $options.id; "role"; "row"; "label"; $label; "value"; $label; "index"; $rows.length; "selected"; Find in array($selected; $row)>0; "enabled"; $table.enabled & ($label#""); "visible"; $table.visible; "frame"; New collection($left; $rowTop; $width; $rowHeight); "clip"; New collection($left; $top; $width; $height))
 $rows.push($node)
 End if
End for
$nodes:=$nodes.concat($rows)
