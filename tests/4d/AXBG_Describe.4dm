// Application-owned renderer used by the custom-column regression.
#DECLARE($cell : Object) -> $text : Text
var $row : Integer
If (New collection("ItemSecret"; "RowID").indexOf($cell.column)>=0)
 Form.protectedCalls:=Form.protectedCalls+1
 return "PRIVATE-DESCRIPTION-MUST-NOT-RUN"
End if
Form.descriptionCalls:=Form.descriptionCalls+1
If ($cell.item#Null)
 If (New collection(This).indexOf($cell.item)#0)
  return "Incorrect row renderer context"
 End if
 $text:="Ready: "+This.name
Else
 $row:=$cell.row
 If (((Value type($cell.key)=Is text)#(Type(aGridKey)=Text array)) | ($cell.key#aGridKey{$row}))
  return "Incorrect original row identity"
 End if
 $text:="Ready: "+aGridName{$row}
End if
