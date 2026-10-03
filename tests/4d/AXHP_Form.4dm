var $child; $grand; $empty; $i : Integer
ARRAY POINTER($hierarchy; 3)
Case of
 : (Form event code=On Load)
  Form.events:=New collection
  Form.command:=New object("id"; "")
  Form.groupedCase:="initial"
  Form.tree:=New list
  $grand:=New list
  APPEND TO LIST($grand; "Deep leaf 🎹"; -301)
  APPEND TO LIST($grand; ""; -302)
  $child:=New list
  APPEND TO LIST($child; "Nested branch"; 201; $grand; True)
  APPEND TO LIST($child; "Sibling leaf"; 202)
  APPEND TO LIST(Form.tree; "First branch"; 101; $child; True)
  $empty:=New list
  APPEND TO LIST(Form.tree; "Empty branch"; 102; $empty; False)
  For ($i; 1; 60)
   APPEND TO LIST(Form.tree; "Distant "+String($i); 1000+$i)
  End for
  SET LIST ITEM(*; "TreeB"; 101; "First branch"; 101; $child; False)
  SELECT LIST ITEMS BY POSITION(*; "TreeA"; 1)
  SELECT LIST ITEMS BY POSITION(*; "TreeB"; 2)
  ARRAY TEXT(AXHP_Group; 60)
  ARRAY TEXT(AXHP_Subgroup; 60)
  ARRAY TEXT(AXHP_Label; 60)
  ARRAY LONGINT(AXHP_Key; 60)
  ARRAY BOOLEAN(AXHP_Selection; 60)
  ARRAY LONGINT(AXHP_Control; 60)
  For ($i; 1; 60)
   AXHP_Group{$i}:="Group "+String(Int(($i-1)/20))
   AXHP_Subgroup{$i}:="Subgroup "+String(Int(($i-1)/5))
   AXHP_Label{$i}:="Leaf "+String($i)
   AXHP_Key{$i}:=$i
   AXHP_Control{$i}:=0
  End for
  $hierarchy{1}:=->AXHP_Group
  $hierarchy{2}:=->AXHP_Subgroup
  $hierarchy{3}:=->AXHP_Label
  LISTBOX SET HIERARCHY(*; "Grouped"; True; $hierarchy)
  GOTO OBJECT(*; "Close")
  SET TIMER(6)
 : (Form event code=On Timer)
  var $request : Object
  If (File("/RESOURCES/request.json").exists)
   $request:=JSON Parse(File("/RESOURCES/request.json").getText())
   If (($request.id#"") & ($request.id#Form.command.id))
    Form.command:=AXHP_Command($request)
   End if
  End if
  AXHP_State
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
End case
