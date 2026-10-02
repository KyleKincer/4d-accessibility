// Read or select the existing editor through its owning provider. The provider
// formula stays in host action state; it is never supplied by an AX client.
#DECLARE($node : Object; $operation : Text; $selection : Collection) -> $result : Object
var $start; $end : Integer
var $styledText : Object
$result:=New object("active"; False)
If (($node.gridCell#Null) && ($node.gridCell.editor#Null))
 return $node.gridCell.editor.call(Null; $node.gridCell; $operation; $selection)
End if
If (Not(AXB_TextFocus($node.objectName; $node.gridCell)) | Not(Is editing text))
 return
End if
If (Not(OBJECT Get enterable(*; $node.objectName)) | Not(OBJECT Get enabled(*; $node.objectName)) | Not(OBJECT Get visible(*; $node.objectName)))
 return
End if
If ((OBJECT Get font(*; $node.objectName)="%password") & Not($node.protected))
 return
End if
If ($operation="select")
 HIGHLIGHT TEXT(*; $node.objectName; $selection[0]; $selection[1])
 If (Not(AXB_TextFocus($node.objectName; $node.gridCell)) | Not(Is editing text) | ((OBJECT Get font(*; $node.objectName)="%password") & Not($node.protected)))
  return
 End if
End if
GET HIGHLIGHT(*; $node.objectName; $start; $end)
$result:=New object("active"; True; "start"; $start; "end"; $end)
If (Not($node.protected))
 $result.text:=Get edited text
 If (OBJECT Is styled text(*; $node.objectName))
  $styledText:=AXB_StyledText($result.text)
  If (Not($styledText.ok) | $styledText.references)
   return New object("active"; False)
  End if
  $result.text:=$styledText.text
 End if
End if
