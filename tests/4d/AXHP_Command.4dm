// Native command behavior probe. These are not bridge action implementations.
#DECLARE($request : Object) -> $result : Object
var $ref; $child; $i : Integer
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
 : ($request.operation="groupCollapseAll")
  LISTBOX COLLAPSE(*; "Grouped")
 : ($request.operation="groupExpandAll")
  LISTBOX EXPAND(*; "Grouped")
 : ($request.operation="groupHeight37")
  LISTBOX SET ROWS HEIGHT(*; "Grouped"; 37; lk pixels)
 : ($request.operation="groupVariableHeight")
  LISTBOX SET ROW HEIGHT(*; "Grouped"; 2; 45)
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
 : ($request.operation="groupCase")
  AXHP_GroupedCase(String($request.name))
  Form.outlinePrevious:=Null
 : ($request.operation="groupHideFirst")
  If (Form.groupedCase="repeated")
   For ($i; 1; 3)
    AXHP_Control{$i}:=1
   End for
  Else
   $result.error:="requiresRepeatedCase"
  End if
 : ($request.operation="groupShowAll")
  For ($i; 1; Size of array(AXHP_Control))
   AXHP_Control{$i}:=0
  End for
 : ($request.operation="groupFormatNested")
  Form.faultFormat:=OBJECT Get format(AXHP_Subgroup)
  OBJECT SET FORMAT(AXHP_Subgroup; "(######)")
 : ($request.operation="groupProtectNested")
  Form.faultFont:=OBJECT Get font(AXHP_Subgroup)
  OBJECT SET FONT(AXHP_Subgroup; "%password")
 : ($request.operation="groupRestoreCaption")
  If (Form.faultFormat#Null)
   OBJECT SET FORMAT(AXHP_Subgroup; Form.faultFormat)
   OB REMOVE(Form; "faultFormat")
  End if
  If (Form.faultFont#Null)
   OBJECT SET FONT(AXHP_Subgroup; Form.faultFont)
   OB REMOVE(Form; "faultFont")
  End if
 : ($request.operation="groupCaseVariants")
  AXHP_Group{2}:="a"
 : ($request.operation="groupFaultBinding")
  // AXHP_State exercises the caller's retained binding without UI input.
 : ($request.operation="groupControlRestore")
  LISTBOX SET ARRAY(*; "Grouped"; lk control array; ->AXHP_Control)
 : ($request.operation="groupSelectFirstLeaves")
  If (Form.groupedCase="repeated")
   LISTBOX SELECT ROW(*; "Grouped"; 1; lk replace selection)
   LISTBOX SELECT ROW(*; "Grouped"; 2; lk add to selection)
   LISTBOX SELECT ROW(*; "Grouped"; 3; lk add to selection)
  Else
   $result.error:="requiresRepeatedCase"
  End if
 : ($request.operation="groupCollapseNested")
  LISTBOX COLLAPSE(*; "Grouped"; False; lk break row; 1; 2)
 : ($request.operation="groupExpandNested")
  LISTBOX EXPAND(*; "Grouped"; False; lk break row; 1; 2)
 : ($request.operation="groupSelectLaterBreak")
  If (Form.groupedCase="repeated")
   LISTBOX SELECT BREAK(*; "Grouped"; 6; 1; lk replace selection)
  Else
   $result.error:="requiresRepeatedCase"
  End if
 Else
  $result.error:="unknownProbeOperation"
End case
$result.eventsAfter:=Form.events.length
