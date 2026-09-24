// Validate the resolved global focus against this exact local control frame.
#DECLARE($name : Text) -> $focused : Boolean
var $focus; $registry : Object
var $left; $top; $right; $bottom : Integer
$focused:=False
$focus:=AXB_Focus
If ($focus.node=Null)
 return
End if
If (Compare strings($focus.node.objectName; $name; sk char codes)#0)
 return
End if
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
CONVERT COORDINATES($left; $top; XY Current form; XY Current window)
$registry:=AXB_FormRoots[String(Current form window)]
$focused:=($left=($focus.node.frame[0]+$registry.origin[0])) & ($top=($focus.node.frame[1]+$registry.origin[1]))
