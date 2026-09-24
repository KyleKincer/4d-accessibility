// Flat array-backed AreaList Pro 11.4 adapter. Keys must be bound to the area and sorted with its display arrays.
#DECLARE($area : Integer; $objectName : Text; $keys : Pointer; $tableID : Text) -> $nodes : Collection
var $table; $node : Object
var $row; $column; $left; $top; $right; $bottom; $error : Integer
var $listLeft; $listTop; $width; $height; $rowTop; $rowHeight; $cellLeft; $cellWidth : Real
var $rowID; $text; $label : Text
ARRAY LONGINT($selected; 0)
$nodes:=New collection
$table:=AXB_ALPNode($objectName; $tableID; "Invoice fixture line items")
$nodes.push($table)
// The demonstrator is deliberately limited to the verified legacy, flat, two-visible-column layout.
If ((AL_GetAreaLongProperty($area; ALP_Area_Compatibility)#1) | (AL_GetAreaLongProperty($area; ALP_Area_Columns)#3))
 $table.enabled:=False
 $table.label:="Unsupported grid layout"
 return
End if
If ((Size of array($keys->)>60) | (Size of array($keys->)#AL_GetAreaLongProperty($area; ALP_Area_Rows)))
 $table.enabled:=False
 $table.label:="Unsupported grid: row count or key mapping"
 return
End if
$error:=AL_GetObjects($area; ALP_Object_Selection; $selected)
If ($error#0)
 $table.enabled:=False
 $table.label:="Grid selection unavailable"
 return
End if
OBJECT GET COORDINATES(*; $objectName; $left; $top; $right; $bottom)
$listLeft:=AL_GetAreaRealProperty($area; ALP_Area_ListLeft)
$listTop:=AL_GetAreaRealProperty($area; ALP_Area_ListTop)
$width:=AL_GetAreaRealProperty($area; ALP_Area_ListWidth)
$height:=AL_GetAreaRealProperty($area; ALP_Area_ListHeight)
For ($row; 1; Size of array($keys->))
 $rowID:=$tableID+"."+$keys->{$row}
 $rowHeight:=AL_GetRowRealProperty($area; $row; ALP_Row_Height)
 $rowTop:=$listTop+AL_GetRowRealProperty($area; $row; ALP_Row_RowOffset)-AL_GetAreaRealProperty($area; ALP_Area_ScrollTop)
 $label:=AL_GetCellTextProperty($area; $row; 1; ALP_Cell_FormattedValue)+"; "+AL_GetCellTextProperty($area; $row; 2; ALP_Cell_FormattedValue)
 $node:=New object("id"; $rowID; "parent"; $tableID; "role"; "row"; "label"; $label; "value"; $label; "index"; $row-1; "selected"; Find in array($selected; $row)>0; "enabled"; $table.enabled; "visible"; $table.visible & (AL_GetRowLongProperty($area; $row; ALP_Row_Hide)=0); "frame"; New collection($listLeft; $rowTop; $width; $rowHeight); "clip"; New collection($listLeft; $listTop; $width; $height))
 $nodes.push($node)
 $cellLeft:=$listLeft-AL_GetAreaRealProperty($area; ALP_Area_ScrollLeft)
 For ($column; 1; 2)
  $cellWidth:=AL_GetColumnRealProperty($area; $column; ALP_Column_Width)
  $text:=AL_GetCellTextProperty($area; $row; $column; ALP_Cell_FormattedValue)
  $nodes.push(New object("id"; $rowID+".c"+String($column); "parent"; $rowID; "role"; "cell"; "label"; Choose($column=1; "Item"; "Description"); "value"; $text; "enabled"; False; "visible"; $node.visible; "frame"; New collection($cellLeft; $rowTop; $cellWidth; $rowHeight)))
  $cellLeft:=$cellLeft+$cellWidth
 End for
End for
