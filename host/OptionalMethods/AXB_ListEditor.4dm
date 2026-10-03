// Resolve the actual caret before re-entering the verified row form. This
// formula is internal provider state, never supplied by an accessibility client.
#DECLARE($cell : Object; $operation : Text; $selection : Collection) -> $result : Object
var $focus; $request; $reply : Object
var $savedOK : Integer
$result:=New object("active"; False)
If ((Current form window#Frontmost window) | Not($cell.state.valid=True) | ($cell.state.descriptor.generation#$cell.generation))
 return
End if
$focus:=AXB_Focus
If (($focus.node=Null) || ($focus.cell=Null) || ($focus.node.grid.generation#$cell.generation) || ($focus.cell.row#$cell.row) || ($focus.cell.column#$cell.column) || Not($focus.editing=True))
 return
End if
$request:=New object("operation"; $operation; "selection"; $selection; "column"; $cell.column; "table"; $cell.state.binding.table; "record"; $cell.state.binding.records[$cell.state.positions[$cell.row]-1]; "form"; $cell.state.binding.form)
$savedOK:=OK
EXECUTE METHOD IN SUBFORM($cell.objectName; "AXB_ListEditorRead"; $reply; $request)
OK:=$savedOK
If ($reply#Null)
 $result:=$reply
End if
If ($result.active=True)
 // GET HIGHLIGHT on a list's template field does not describe its overlay
 // editor. Read the verified native input client's actual UTF-16 selection.
 $focus:=AXB_Focus
 If (($focus.node=Null) || ($focus.cell=Null) || ($focus.node.grid.generation#$cell.generation) || ($focus.cell.row#$cell.row) || ($focus.cell.column#$cell.column) || Not($focus.editing=True) || ($focus.native.selection=Null))
  return New object("active"; False)
 End if
 $result.start:=$focus.native.selection[0]+1
 $result.end:=$result.start+$focus.native.selection[1]
End if
