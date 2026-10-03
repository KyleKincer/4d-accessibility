// A logical record grid for classic list subforms. Row values come from the
// isolated selection reader, never from the form's single loaded record.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $node; $reply; $info; $binding; $column; $attribute; $columnsByID; $positions; $known; $frames; $headers; $rowFrames; $descriptor; $issue; $data : Object
var $rows; $columns; $selected; $visible; $rowLayout; $columnLayout; $clip; $columnBindings : Collection
var $name; $key; $orderState : Text
var $first; $row; $left; $top; $right; $bottom; $savedOK : Integer
var $x; $y; $r; $b : Real
var $editable; $canEdit : Boolean
$name:=$options.objectName
$result:=New object("ok"; True; "nodes"; New collection; "pages"; New collection; "unsupported"; New collection; "status"; "rejected"; "message"; "List subform changed before the request")
If ($operation="readGrid")
 return AXB_GridReadPages($state; $request.requests)
End if
If ($operation#"describe")
 If ($operation="apply")
  // Recheck the actual row form, field bindings and selection before EDIT ITEM
  // or a click can invoke any original application handler.
  $reply:=AXB_ListSubform("describe"; $options; $state; New object)
  If (Not($state.valid=True))
   return
  End if
 End if
 If (($operation="apply") && ($request.action.operation="gridSelect") && ($state.valid=True) && (Current form window=Frontmost window) && OBJECT Get enabled(*; $name))
  $descriptor:=$state.descriptor
  If (Not($descriptor.actions.select=True) | (($descriptor.selectionMode="single") & ($request.action.value.length>1)))
   return
  End if
  $known:=New object
  For each ($key; $request.action.value)
   If (Not(OB Is defined($state.positions; $key)) | OB Is defined($known; $key))
    return
   End if
   $known[$key]:=True
  End for each
  $data:=New object("options"; $options; "state"; $state; "action"; $request.action; "generation"; $descriptor.generation; "serial"; 0; "deadline"; Milliseconds+30000; "stepDeadline"; Milliseconds+2000)
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformSelect($1)); "data"; $data)
 End if
 If (($operation="apply") && (New collection("gridEdit"; "gridPress"; "gridSetValue"; "gridSetSelection"; "gridReplaceSelection").indexOf($request.action.operation)>=0) && ($state.valid=True) && (Current form window=Frontmost window) && OBJECT Get enabled(*; $name))
  $descriptor:=$state.descriptor
  $key:=$request.action.value.row
  If (($request.action.value.generation#$descriptor.generation) | Not(OB Is defined($state.positions; $key)) | Not(OB Is defined($state.columns; $request.action.value.column)))
   return
  End if
  $column:=$state.columns[$request.action.value.column]
  If (Not($column.editable=True))
   return
  End if
  $reply:=AXB_GridValue($state; $column; $state.positions[$key])
  If (Not($reply.ok & $reply.editable & $reply.enabled))
   return
  End if
  $data:=New object("options"; $options; "state"; $state; "action"; $request.action; "generation"; $descriptor.generation; "deadline"; Milliseconds+2000)
  If ($column.controlRole="checkbox")
   If (($request.action.operation#"gridPress") || ($request.action.value.expectedCell=Null) || ($request.action.value.expectedCell.role#"checkbox") || ($reply.checked#$request.action.value.expectedCell.checked) || (Compare strings($reply.value; $request.action.value.expectedCell.value; sk char codes)#0))
    return
   End if
   $data.widget:=$reply
   // Clicking the actual checkbox enters its record through the normal UI.
   // EDIT ITEM would first focus an unrelated text field in the row.
   return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformWidget($1)); "data"; $data)
  End if
  If ($request.action.operation="gridPress")
   return
  End if
  If (($request.action.operation="gridSetValue") & ($request.action.value.expectedEditor=Null) && (Compare strings($reply.value; $request.action.value.expectedValue; sk char codes)#0))
   return
  End if
  If ($request.action.value.expectedEditor=Null)
   If (New collection("gridSetSelection"; "gridReplaceSelection").indexOf($request.action.operation)>=0)
    return
   End if
   EDIT ITEM(*; $name; $state.positions[$key])
  End if
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformEdit($1)); "data"; $data)
 End if
 If (($operation="apply") && ($request.action.operation="gridReveal") && ($state.valid=True) && (Current form window=Frontmost window) && OBJECT Get enabled(*; $name))
  $descriptor:=$state.descriptor
  $key:=$request.action.value.row
  If (($request.action.value.generation=$descriptor.generation) && OB Is defined($state.positions; $key) && OB Is defined($state.columns; $request.action.value.column))
   OBJECT SET SCROLL POSITION(*; $name; $state.positions[$key]; *)
   return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformReveal($1)); "data"; New object("options"; $options; "state"; $state; "action"; $request.action; "generation"; $descriptor.generation; "deadline"; Milliseconds+2000))
  End if
 End if
 return
End if
$state.valid:=False
$reply:=AXB_Host("node"; New object("objectName"; $name; "id"; $options.id; "role"; "table"; "label"; $options.label; "value"; ""; "enabled"; False))
If (Not($reply.ok=True))
 return $reply
End if
$node:=$reply.node
$node.objectName:=$name
$result.nodes.push($node)
$info:=AXB_ListSubformInfo($options; $state)
If (Not($info.ok=True))
 $node.label:=$options.label+": "+$info.error
 $result.unsupported.push(New object("object"; $name; "reason"; $info.error))
 return
End if
$result.unsupported:=$info.unsupported
For each ($issue; $result.unsupported)
 $issue.object:=$name
End for each
$binding:=AXB_SelectionSource($options; $state; $info)
$savedOK:=OK
CLEAR SET($info.highlight)
OK:=$savedOK
If (Not($binding.ok=True))
 $node.label:=$options.label+": "+$binding.message
 If ($binding.error#Null)
  $result.unsupported.push(New object("object"; $name; "reason"; $binding.error))
 End if
 return
End if
$columns:=New collection
$columnsByID:=New object
$columnLayout:=New collection
$columnBindings:=New collection
$canEdit:=False
For each ($column; $info.columns)
 If (($column.value=Null) & ($binding.dataClass#Null))
  $attribute:=$binding.dataClass[$column.property]
  If (($attribute=Null) || ($attribute.kind#"storage") || (New collection("string"; "number"; "date"; "bool").indexOf($attribute.type)<0))
   $result.unsupported.push(New object("object"; $name; "column"; $column.name; "reason"; "gridValueDescriptionRequired"))
   continue
  End if
 End if
 $editable:=$column.nativeEditable & Not($column.protected) & ($column.property#"") & ($column.value=Null) & $info.enterable
 $column.editable:=$editable
 $canEdit:=$canEdit | $editable
 $columns.push(New object("id"; $column.id; "label"; $column.label; "automationKey"; $column.automationKey; "enabled"; $column.enabled; "editable"; $editable; "selectionTarget"; ($column.controlRole="text") & Not($column.protected); "header"; New object("visible"; $column.hasHeader=True; "enabled"; True; "press"; False; "sortable"; False; "sort"; "none")))
 $columnsByID[$column.id]:=$column
 $columnBindings.push(New collection($column.name; $column.fieldNumber; $column.property; $column.controlRole; ($column.value#Null)))
 $columnLayout.push(New collection($info.origin[0]+$column.frame[0]; $column.frame[2]))
 If ($info.enterable & $column.nativeEditable & Not($column.protected) & Not($editable) & ($column.value=Null))
  $result.unsupported.push(New object("object"; $name; "column"; $column.name; "reason"; "listSubformEditingPending"))
 End if
End for each
$rows:=New collection
$selected:=New collection
$rowLayout:=New collection
$positions:=New object
$known:=New object
OBJECT GET SCROLL POSITION(*; $name; $first)
$first:=New collection(1; $first).max()
For ($row; 1; $binding.count)
 $key:=$binding.keys[$row-1]
 If (($key="") | (Length($key)>256) | OB Is defined($known; $key))
  $node.label:=$options.label+": row keys must be unique nonempty text"
  return
 End if
 $known[$key]:=True
 $rows.push($key)
 $positions[$key]:=$row
 $rowLayout.push(New collection($info.origin[1]+$info.header+(($row-1)*$info.height); $info.height))
 If ((($info.selectionMode="multiple") & $binding.selected[$row-1]) | (($info.selectionMode="single") & ($info.selectedPosition=$row)))
  $selected.push($key)
 End if
End for
$orderState:=JSON Stringify(New collection($rows; $columns))
If (Compare strings($orderState; $state.orderState; sk char codes)#0)
 $state.order:=$state.order+1
 $state.orderState:=$orderState
End if
$binding.identity:=JSON Stringify(New collection($binding.identity; $columnBindings))
If (($state.binding#Null) && (Compare strings($state.binding.identity; $binding.identity; sk char codes)#0))
 $state.generation:=Generate UUID
End if
$state.binding:=$binding
$state.binding.records:=$info.records
$state.binding.form:=$info.form
$state.liveValues:=$info.liveValues
$state.columns:=$columnsByID
$state.positions:=$positions
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
$clip:=New collection($left; $top; $right-$left; $bottom-$top)
$headers:=New object
For each ($column; $info.columns)
 If (($column.hasHeader=True) & OB Is defined($columnsByID; $column.id))
  $x:=New collection($left; $info.origin[0]+$column.frame[0]).max()
  $r:=New collection($right; $info.origin[0]+$column.frame[0]+$column.frame[2]).min()
  $b:=New collection($bottom; $clip[1]+$info.header).min()
  If (($r>$x) & ($b>$clip[1]))
   $headers[$column.id]:=New collection($x; $clip[1]; $r-$x; $b-$clip[1])
  End if
 End if
End for each
$frames:=New object
$visible:=New collection
For ($row; New collection(1; $first-1).max(); $binding.count)
 $key:=$rows[$row-1]
 // AXB_ListSubformInfo derives origin[1] from the parent viewport, native
 // first visible record and installed markers, so this slot already includes
 // scrolling; column frames carry their own header offset.
 $y:=$info.origin[1]+(($row-1)*$info.height)
 If (($y+$info.header)>=$bottom)
  break
 End if
 $rowFrames:=New object
 For each ($column; $info.columns)
  If (Not(OB Is defined($columnsByID; $column.id)))
   continue
  End if
  $x:=New collection($left; $info.origin[0]+$column.frame[0]).max()
  $top:=$y+$column.frame[1]
  $r:=New collection($right; $info.origin[0]+$column.frame[0]+$column.frame[2]).min()
  $b:=New collection($bottom; $top+$column.frame[3]).min()
  $top:=New collection($clip[1]+$info.header; $top).max()
  If (($r>$x) & ($b>$top))
   $rowFrames[$column.id]:=New collection($x; $top; $r-$x; $b-$top)
  End if
 End for each
 If (OB Keys($rowFrames).length>0)
  $visible.push($key)
  $frames[$key]:=$rowFrames
 End if
End for
$descriptor:=New object("generation"; $state.generation; "order"; $state.order; "rows"; $rows; "columns"; $columns; "selected"; $selected; "visible"; $visible; "frames"; $frames; "headers"; $headers; "headerHeight"; $info.header; "disabled"; New collection; "unselectable"; New collection; "uneditable"; New collection; "selectionMode"; $info.selectionMode; "actions"; New object("select"; $info.selectionMode#"none"; "reveal"; True; "edit"; $canEdit))
If ($columns.length>0)
 $descriptor.layout:=New object("rows"; $rowLayout; "columns"; $columnLayout)
End if
$state.descriptor:=$descriptor
$state.valid:=True
$node.grid:=$descriptor
$node.enabled:=OBJECT Get enabled(*; $name)
If ($info.selectionMode="none")
 $descriptor.unselectable:=$rows.copy()
End if
