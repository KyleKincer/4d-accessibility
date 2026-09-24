// A page subform on 4D 20.8 reports pixel offsets on both axes. Read them
// back after scrolling; never assume the requested offset was accepted.
#DECLARE($name : Text; $frame : Collection) -> $result : Object
var $left; $top; $right; $bottom; $beforeX; $beforeY; $afterX; $afterY : Integer
var $deltaX; $deltaY; $width; $height : Real
var $registry : Object
$result:=New object("ok"; False; "status"; "rejected"; "message"; "Subform content could not be revealed")
If ((Current form window#Frontmost window) | Not(OBJECT Get visible(*; $name)))
 return
End if
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
CONVERT COORDINATES($left; $top; XY Current form; XY Current window)
CONVERT COORDINATES($right; $bottom; XY Current form; XY Current window)
$width:=$right-$left
$height:=$bottom-$top
If (($width<=0) | ($height<=0))
 return
End if
$deltaX:=0
$deltaY:=0
If ($frame[0]<$left)
 $deltaX:=$frame[0]-$left
Else
 If (($frame[0]+$frame[2])>$right)
  $deltaX:=New collection($frame[0]+$frame[2]-$right; $frame[0]-$left).min()
 End if
End if
If ($frame[1]<$top)
 $deltaY:=$frame[1]-$top
Else
 If (($frame[1]+$frame[3])>$bottom)
  $deltaY:=New collection($frame[1]+$frame[3]-$bottom; $frame[1]-$top).min()
 End if
End if
If (($deltaX#0) | ($deltaY#0))
 OBJECT GET SCROLL POSITION(*; $name; $beforeY; $beforeX)
 OBJECT SET SCROLL POSITION(*; $name; New collection(0; $beforeY+$deltaY).max(); New collection(0; $beforeX+$deltaX).max(); *)
 OBJECT GET SCROLL POSITION(*; $name; $afterY; $afterX)
 If (($afterX#$beforeX) | ($afterY#$beforeY))
  $registry:=AXB_FormRoots[String(Current form window)]
  If ($registry#Null)
   $registry.focusGeometryChanged:=True
   If (($registry.observedFocus#Null) && ($registry.observedFocus.id=Null))
    OB REMOVE($registry; "observedFocus")
   End if
  End if
 End if
 $frame:=New collection($frame[0]-($afterX-$beforeX); $frame[1]-($afterY-$beforeY); $frame[2]; $frame[3])
End if
If (Not(AXB_Intersects($frame; New collection($left; $top; $width; $height))))
 return
End if
// Only the visible portion can be revealed by an outer container. An oversized
// control still keeps its full logical AX frame for reading and navigation.
$right:=New collection($right; $frame[0]+$frame[2]).min()
$bottom:=New collection($bottom; $frame[1]+$frame[3]).min()
$left:=New collection($left; $frame[0]).max()
$top:=New collection($top; $frame[1]).max()
$result:=New object("ok"; True; "frame"; New collection($left; $top; $right-$left; $bottom-$top))
