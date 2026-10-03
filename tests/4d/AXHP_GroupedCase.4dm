// Programmatic synthetic baselines, never proposed accessibility actions.
#DECLARE($name : Text)
var $i; $count : Integer
ARRAY POINTER($hierarchy; 3)
Case of
 : ($name="longRepeated")
  $count:=60
 : (New collection("repeated"; "singleText"; "singleDate").indexOf($name)>=0)
  $count:=8
 : ($name="placeholder")
  $count:=1
 : ($name="empty")
  $count:=0
 Else
  return
End case
Form.groupedCase:=$name
ARRAY TEXT(AXHP_Group; $count)
ARRAY TEXT(AXHP_Subgroup; $count)
ARRAY TEXT(AXHP_Label; $count)
ARRAY DATE(AXHP_Date; $count)
ARRAY LONGINT(AXHP_Key; $count)
ARRAY BOOLEAN(AXHP_Selection; $count)
ARRAY LONGINT(AXHP_Control; $count)
AXHP_Selection{0}:=False
For ($i; 1; $count)
 AXHP_Group{$i}:=Choose($i<=3; "A"; Choose($i<=5; "B"; Choose($i<=7; "A"; "C")))
 AXHP_Subgroup{$i}:=Choose($i=3; "other"; "shared")
 AXHP_Label{$i}:="Leaf "+String($i)
 AXHP_Key{$i}:=$i
 AXHP_Date{$i}:=!2026-10-01!+Choose($i<=3; 0; Choose($i<=5; 1; Choose($i<=7; 0; 2)))
 AXHP_Selection{$i}:=False
 AXHP_Control{$i}:=0
 If ($name="longRepeated")
  AXHP_Group{$i}:=Choose($i<=20; "A"; Choose($i<=40; "B"; "A"))
  AXHP_Subgroup{$i}:="Part "+String(Int(($i-1)/5))
 End if
End for
If ($name="placeholder")
 AXHP_Subgroup{1}:=""
 AXHP_Label{1}:=""
End if
$hierarchy{1}:=->AXHP_Group
$hierarchy{2}:=->AXHP_Subgroup
$hierarchy{3}:=->AXHP_Label
If (New collection("singleText"; "singleDate").indexOf($name)>=0)
 ARRAY POINTER($hierarchy; 1)
 $hierarchy{1}:=Choose($name="singleDate"; ->AXHP_Date; ->AXHP_Group)
End if
LISTBOX SET HIERARCHY(*; "Grouped"; True; $hierarchy)
If ($count>0)
 // Reset break and leaf selections explicitly.
 LISTBOX SELECT BREAK(*; "Grouped"; 1; 1; lk replace selection)
 LISTBOX SELECT BREAK(*; "Grouped"; 1; 1; lk remove from selection)
End if
LISTBOX SELECT ROW(*; "Grouped"; 0; lk remove from selection)
LISTBOX EXPAND(*; "Grouped")
If ($count>0)
 OBJECT SET SCROLL POSITION(*; "Grouped"; 1; 1; *)
End if
GOTO OBJECT(*; "Close")
