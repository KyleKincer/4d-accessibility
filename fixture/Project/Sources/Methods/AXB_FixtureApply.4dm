#DECLARE($node : Text; $operation : Text; $value : Text) -> $result : Object
var $window; $process; $row : Integer
$result:=New object("status"; "rejected"; "message"; "Unknown action")
Case of
 : (($node="name") & ($operation="setValue"))
  If ((Length($value)>0) & (Length($value)<=40))
   Form.name:=$value
   Form.validName:=$value
   $result:=New object("status"; "completed"; "message"; "Name accepted by 4D")
  Else
   Form.name:=Form.validName
   $result.message:="Name must contain 1 to 40 characters"
  End if
 : (($node="allowed") & (($operation="press") | ($operation="humanChange")))
  If ($operation="press")
   Form.allowed:=Not(Form.allowed)
  End if
  OBJECT SET ENABLED(*; "Submit"; Form.allowed)
  $result:=New object("status"; "completed"; "message"; "Permission changed by 4D")
 : (($node="submit") & ($operation="press"))
  If (Form.allowed & (Length(Form.validName)>0))
   Form.count:=Form.count+1
   $result:=New object("status"; "completed"; "message"; "4D submissions: "+String(Form.count)+"; tester: "+Form.validName)
  Else
   $result.message:="Submission is disabled"
  End if
 : (($node="reverse") & ($operation="press"))
  Form.reversed:=Not(Form.reversed)
  If (Form.reversed)
   SORT ARRAY(aAXBKeys; aAXBItems; aAXBDescriptions; <)
  Else
   SORT ARRAY(aAXBKeys; aAXBItems; aAXBDescriptions; >)
  End if
  AL_SetAreaLongProperty(vAXBGrid; ALP_Area_UpdateData; 0)
  $result:=New object("status"; "completed"; "message"; "Rows reordered by stable key")
 : (($node="hide") & ($operation="press"))
  OBJECT SET VISIBLE(*; "Name"; Not(OBJECT Get visible(*; "Name")))
  $result:=New object("status"; "completed"; "message"; "Name visibility changed")
 : (($node="remove") & ($operation="press"))
  $row:=Find in array(aAXBKeys; "line-003")
  If ($row>0)
   DELETE FROM ARRAY(aAXBKeys; $row)
   DELETE FROM ARRAY(aAXBItems; $row)
   DELETE FROM ARRAY(aAXBDescriptions; $row)
   AL_SetAreaLongProperty(vAXBGrid; ALP_Area_UpdateData; 0)
  End if
  $result:=New object("status"; "completed"; "message"; "Line 003 removed")
 : (($node="modal") & ($operation="press"))
  $window:=Open form window("Modal"; Movable form dialog box; Horizontally centered; Vertically centered)
  DIALOG("Modal"; New object)
  CLOSE WINDOW($window)
  $result:=New object("status"; "completed"; "message"; "Modal closed")
 : (($node="second") & ($operation="press"))
  $process:=New process("AXB_FixtureWindow"; 0; "Accessibility second window")
  $result:=New object("status"; "completed"; "message"; "Second window opened")
 : (($node="more") & ($operation="press"))
  For ($row; Size of array(aAXBKeys)+1; 60)
   APPEND TO ARRAY(aAXBKeys; "scroll-"+String($row))
   APPEND TO ARRAY(aAXBItems; "TEST-"+String($row))
   APPEND TO ARRAY(aAXBDescriptions; "Synthetic scrolling row "+String($row))
  End for
  AL_SetAreaLongProperty(vAXBGrid; ALP_Area_UpdateData; 0)
  $result:=New object("status"; "completed"; "message"; "60 synthetic rows loaded")
End case
Form.message:=$result.message
