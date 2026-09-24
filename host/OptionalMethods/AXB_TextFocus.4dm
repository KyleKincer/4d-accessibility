// A grid editor must resolve to the exact live row and column, including when
// another repeated subform contains the same object name and shared binding.
#DECLARE($name : Text; $cell : Object) -> $focused : Boolean
var $focus : Object
var $uneditable : Collection
If ($cell=Null)
 return AXB_ControlFocus($name)
End if
$focused:=False
$focus:=AXB_Focus
If (($focus.node=Null) || ($focus.cell=Null))
 return
End if
$uneditable:=$focus.node.grid.uneditable
If ($uneditable=Null)
 $uneditable:=$focus.node.grid.unselectable
End if
$focused:=(AXB_KeyIndex($focus.node.grid.disabled; $cell.row)<0) & (AXB_KeyIndex($uneditable; $cell.row)<0) & (Compare strings($focus.cell.row; $cell.row; sk char codes)=0) & (Compare strings($focus.cell.column; $cell.column; sk char codes)=0) & ($focus.node.grid.generation=$cell.generation) & AXB_ControlFocus($cell.objectName)
