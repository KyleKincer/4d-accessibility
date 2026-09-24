// Translate actual layout bounds separately from clipped viewport geometry.
#DECLARE($grid : Object; $offset : Collection; $clip : Collection) -> $result : Object
var $frames; $headers; $cells : Object
var $row; $column : Text
var $frame; $rows; $columns : Collection
var $left; $top; $right; $bottom : Real
$result:=OB Copy($grid)
If ($grid.layout#Null)
 $rows:=New collection
 $columns:=New collection
 For each ($frame; $grid.layout.rows)
  $rows.push(New collection($frame[0]+$offset[1]; $frame[1]))
 End for each
 For each ($frame; $grid.layout.columns)
  $columns.push(New collection($frame[0]+$offset[0]; $frame[1]))
 End for each
 $result.layout:=New object("rows"; $rows; "columns"; $columns)
End if
$frames:=New object
$headers:=New object
$result.visible:=New collection
For each ($row; $grid.visible)
 $cells:=New object
 For each ($column; $grid.frames[$row])
  $frame:=$grid.frames[$row][$column]
  $left:=$frame[0]+$offset[0]
  $top:=$frame[1]+$offset[1]
  $right:=$left+$frame[2]
  $bottom:=$top+$frame[3]
  If ($clip#Null)
   $left:=New collection($left; $clip[0]).max()
   $top:=New collection($top; $clip[1]).max()
   $right:=New collection($right; $clip[0]+$clip[2]).min()
   $bottom:=New collection($bottom; $clip[1]+$clip[3]).min()
  End if
  If (($right>$left) & ($bottom>$top))
   $cells[$column]:=New collection($left; $top; $right-$left; $bottom-$top)
  End if
 End for each
 If (OB Keys($cells).length>0)
  $frames[$row]:=$cells
  $result.visible.push($row)
 End if
End for each
For each ($column; $grid.headers)
 $frame:=$grid.headers[$column]
 $left:=$frame[0]+$offset[0]
 $top:=$frame[1]+$offset[1]
 $right:=$left+$frame[2]
 $bottom:=$top+$frame[3]
 If ($clip#Null)
  $left:=New collection($left; $clip[0]).max()
  $top:=New collection($top; $clip[1]).max()
  $right:=New collection($right; $clip[0]+$clip[2]).min()
  $bottom:=New collection($bottom; $clip[1]+$clip[3]).min()
 End if
 If (($right>$left) & ($bottom>$top))
  $headers[$column]:=New collection($left; $top; $right-$left; $bottom-$top)
 End if
End for each
$result.frames:=$frames
$result.headers:=$headers
