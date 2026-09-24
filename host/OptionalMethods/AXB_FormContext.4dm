// Resolve this root form independently of the business-data object it binds.
#DECLARE() -> $context : Object
var $registry : Object
var $x; $y : Integer
$context:=Null
$registry:=AXB_FormRoots[String(Current form window)]
If ($registry=Null)
 return
End if
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
If (($registry.formName=Current form name) & ($registry.origin[0]=$x) & ($registry.origin[1]=$y))
 $context:=$registry.context
End if
