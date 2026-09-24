// Binding identity stays in process-owned state, outside the application's
// Form object. Referencing Form from its own provider would create a cycle.
#DECLARE() -> $result : Object
var $registry; $node; $focus; $column; $observed : Object
var $keys : Collection
var $key : Text
var $x; $y : Integer
$registry:=AXB_FormRoots[String(Current form window)]
$registry.seen:=New object
$registry.controlPointers:=New object
$registry.controlContexts:=New object
$registry.cellPointers:=New object
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$registry.origin:=New collection($x; $y)
$result:=AXB_View(New object("operation"; "describe"; "rootView"; $registry.context.view; "path"; New collection; "ancestors"; New collection; "navigation"; New collection; "rootOrigin"; New collection($x; $y); "enabled"; True; "depth"; 0))
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
    If ($focus.native.selection#Null)
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
 End if
End for each
OB REMOVE($registry; "seen")
