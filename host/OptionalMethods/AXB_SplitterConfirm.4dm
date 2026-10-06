// Confirm a splitter adjustment: 4D moves the splitter and its attached objects
// within their limits once the form applies the assigned offset.
#DECLARE($request : Object) -> $result : Object
var $left; $top; $right; $bottom : Integer
var $position : Real
OBJECT GET COORDINATES(*; $request.objectName; $left; $top; $right; $bottom)
$position:=Choose($request.vertical; $left; $top)
If ($position=$request.previousValue)
 If (Milliseconds<$request.deadline)
  return New object("status"; "pending"; "confirm"; Formula(AXB_SplitterConfirm($1)); "data"; $request)
 End if
 return New object("status"; "rejected"; "message"; "The splitter cannot move further")
End if
If (($position>$request.previousValue)#($request.operation="increment"))
 return New object("status"; "rejected"; "message"; "Application moved the splitter the other way")
End if
return New object("status"; "completed"; "message"; "Splitter moved")
