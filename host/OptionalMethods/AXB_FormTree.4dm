// Binding identity stays in process-owned state, outside the application's
// Form object. Referencing Form from its own provider would create a cycle.
// $changes, from the plugin, names the objects whose drawing changed since the last description;
// without it, or when it asks for the whole form, every object is described again.
#DECLARE($changes : Object) -> $result : Object
var $registry; $node; $focus; $column; $observed; $styledText : Object
var $keys : Collection
var $key : Text
var $x; $y : Integer
$registry:=AXB_FormRoots[String(Current form window)]
$registry.seen:=New object
// Controls' contexts and pointers are looked up by the ids of the current nodes, so the
// entries of nodes reused from the last description stay valid. Forms are bound again.
If ($registry.controlPointers=Null)
 $registry.controlPointers:=New object
 $registry.controlContexts:=New object
 $registry.cellPointers:=New object
End if
$registry.formContexts:=New object
// Views still checking their objects for the backstop ask to be described again soon.
$registry.verifying:=False
$registry.focusPointerOwners:=New collection
$registry.focusPointerName:=""
If (($registry.observedFocus#Null) && ($registry.observedFocus.id=Null))
 $registry.focusPointerName:=OBJECT Get name(Object with focus)
End if
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$registry.origin:=New collection($x; $y)
// A reused node keeps no state from the last description: only one node is focused.
If ($registry.focusedNode#Null)
 $registry.focusedNode.focused:=False
 $registry.focusedNode.value:=$registry.focusedValue
 $registry.focusedNode.editable:=$registry.focusedEditable
 OB REMOVE($registry.focusedNode; "selection")
 OB REMOVE($registry; "focusedNode")
End if
$result:=AXB_View(New object("operation"; "describe"; "rootView"; $registry.context.view; "path"; New collection; "ancestors"; New collection; "navigation"; New collection; "rootOrigin"; New collection($x; $y); "enabled"; True; "depth"; 0; "changes"; $changes))
$registry.controls:=New collection
If ($result.ok=True)
 For each ($node; $result.nodes)
  If (Value type($node.objectName)=Is text)
   $registry.controls.push($node)
  End if
 End for each
 $observed:=AXB_FormEvent("resolve")
 OB REMOVE($registry; "focusGeometryChanged")
 If ($registry.controls.length>0)
  $focus:=AXB_Focus
  If ($focus.error#Null)
   For each ($node; $registry.controls)
    If ((Compare strings($node.objectName; $focus.object; sk char codes)=0) & $node.visible & $node.enabled)
     $result.issues.push(New object("path"; $result.routes[$node.id].path.copy(); "object"; $focus.object; "reason"; $focus.error))
    End if
   End for each
  End if
  If ($focus.node#Null)
   $node:=$focus.node
   $registry.focusedNode:=$node
   $registry.focusedValue:=$node.value
   $registry.focusedEditable:=$node.editable
   $node.focused:=True
   If ($focus.cell#Null)
    $node.grid.focused:=$focus.cell
    For each ($column; $node.grid.columns)
     If (($column.id=$focus.cell.column) & $column.editable & ($node.editor=Null) & $focus.editing)
      $node.grid.focused.value:=Get edited text
      If ($focus.native.selection#Null)
       $node.grid.focused.selection:=$focus.native.selection
      End if
     End if
    End for each
   End if
   If (($node.role="textfield") && $focus.editing && Not($node.protected))
    $node.value:=Get edited text
    If ($node.styled=True)
     $styledText:=AXB_StyledText($node.value)
     $node.value:=$styledText.text
     $node.editable:=$node.editable & $styledText.ok & Not($styledText.references)
    End if
    If (($focus.native.selection#Null) & (Not($node.styled=True) | $node.editable))
     $node.selection:=$focus.native.selection
    End if
   End if
  End if
 End if
End if
$keys:=OB Keys($registry.bindings)
For each ($key; $keys)
 If (Not(OB Is defined($registry.seen; $key)))
  OB REMOVE($registry.bindings; $key)
  If ($registry.focusObserverBindings#Null)
   OB REMOVE($registry.focusObserverBindings; $key)
  End if
 End if
End for each
OB REMOVE($registry; "seen")
