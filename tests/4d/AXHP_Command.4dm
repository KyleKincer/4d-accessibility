// Native command behavior probe. These are not bridge action implementations.
#DECLARE($request : Object) -> $result : Object
var $ref; $child : Integer
var $label : Text
var $expanded : Boolean
$result:=New object("id"; $request.id; "operation"; $request.operation; "eventsBefore"; Form.events.length)
Case of
 : (($request.operation="treeExpand") | ($request.operation="treeCollapse"))
  GET LIST ITEM(Form.tree; 1; $ref; $label; $child; $expanded)
  SET LIST ITEM(*; "TreeA"; 101; $label; 101; $child; $request.operation="treeExpand")
 : ($request.operation="treeSelect")
  SELECT LIST ITEMS BY REFERENCE(Form.tree; -301)
 : ($request.operation="treeSelectRoot")
  SELECT LIST ITEMS BY POSITION(*; "TreeA"; 1)
 : ($request.operation="groupCollapse")
  LISTBOX COLLAPSE(*; "Grouped"; False; lk break row; 1; 1)
 : ($request.operation="groupExpand")
  LISTBOX EXPAND(*; "Grouped"; False; lk break row; 1; 1)
 : ($request.operation="groupSelect")
  LISTBOX SELECT ROW(*; "Grouped"; 4; lk replace selection)
 : ($request.operation="groupSelectRoot")
  LISTBOX SELECT BREAK(*; "Grouped"; 1; 1; lk replace selection)
 : ($request.operation="focusTree")
  GOTO OBJECT(*; "TreeA")
 : ($request.operation="treePostRight")
  POST KEY(Right arrow key; 0; Current process)
 : ($request.operation="treePostLeft")
  POST KEY(Left arrow key; 0; Current process)
 : ($request.operation="treePostDown")
  POST KEY(Down arrow key; 0; Current process)
 : ($request.operation="focusGrouped")
  GOTO OBJECT(*; "Grouped")
 Else
  $result.error:="unknownProbeOperation"
End case
$result.eventsAfter:=Form.events.length
