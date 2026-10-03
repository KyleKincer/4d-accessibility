// Select through verified native row clicks. Each click runs the application's
// original selection event; no replacement callback or record export is used.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid; $native; $column : Object
var $key; $target : Text
var $changed; $frame : Collection
var $matches : Boolean
var $index; $pass : Integer
var $x; $y : Real
$result:=New object("status"; "rejected"; "message"; "List subform selection changed before completion")
If ((Current form window#Frontmost window) | (Milliseconds>=$data.deadline) | Not(OBJECT Get enabled(*; $data.options.objectName)))
 return
End if
$reply:=AXB_ListSubform("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$grid:=$data.state.descriptor
If (($grid.generation#$data.generation) | Not($grid.actions.select=True))
 return
End if
For each ($key; $data.action.value)
 If (Not(OB Is defined($data.state.positions; $key)))
  return
 End if
End for each
If ($data.inputSent=True)
 $native:=AXB_PollGuard.context.controlInputResult
 If (($native=Null) || ($native.action#$data.action.id) || ($native.serial#$data.serial))
  If ((Milliseconds>=$data.stepDeadline) & (AXB_PollGuard.context.controlInputReadAt>=$data.stepDeadline))
   return
  End if
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformSelect($1)); "data"; $data)
 End if
 If (Not($native.accepted=True))
  return
 End if
 // The private highlighted-set reader catches up after native painting.
 If ((AXB_KeyIndex($grid.selected; $data.target)>=0)#$data.targetSelected)
  If (Milliseconds>=$data.stepDeadline)
   return
  End if
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformSelect($1)); "data"; $data)
 End if
 $matches:=$grid.selected.length=$data.expectedSelection.length
 For each ($key; $data.expectedSelection)
  $matches:=$matches & (AXB_KeyIndex($grid.selected; $key)>=0)
 End for each
 If (Not($matches))
  $result.message:="Application changed the requested selection"
  return
 End if
 $data.inputSent:=False
End if
$matches:=$grid.selected.length=$data.action.value.length
$changed:=New collection
For each ($key; $data.action.value)
 If (AXB_KeyIndex($grid.selected; $key)<0)
  $changed.push($key)
  $matches:=False
 End if
End for each
If ($matches)
 return New object("status"; "completed"; "message"; "List subform selection confirmed")
End if
If (($grid.selectionMode="multiple") | (($grid.selectionMode="single") & ($data.action.value.length=0)))
 For each ($key; $grid.selected)
  If (AXB_KeyIndex($data.action.value; $key)<0)
   $changed.push($key)
  End if
 End for each
End if
If ($changed.length=0)
 return
End if
$target:=$changed[0]
If (AXB_KeyIndex($grid.visible; $target)<0)
 OBJECT SET SCROLL POSITION(*; $data.options.objectName; $data.state.positions[$target]; *)
 return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformSelect($1)); "data"; $data)
End if
// Prefer a read-only text field so selection need not enter a row editor.
// If all text fields are enterable, preserve their ordinary click behavior.
For ($pass; 0; 1)
For each ($column; $grid.columns)
 If (($pass=0) & $column.editable) | (($pass=1) & Not($column.editable))
  continue
 End if
 If ($column.selectionTarget & $column.enabled & ($grid.frames[$target]#Null) && ($grid.frames[$target][$column.id]#Null))
  $frame:=$grid.frames[$target][$column.id]
  $x:=$frame[0]+($frame[2]/2)
  $y:=$frame[1]+($frame[3]/2)
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  $data.serial:=$data.serial+1
  $data.target:=$target
  $data.targetSelected:=AXB_KeyIndex($data.action.value; $target)>=0
  $data.expectedSelection:=$grid.selected.copy()
  If ($grid.selectionMode="single")
   $data.expectedSelection:=$data.action.value.copy()
  Else
   $index:=AXB_KeyIndex($data.expectedSelection; $target)
   If ($index<0)
    $data.expectedSelection.push($target)
   Else
    $data.expectedSelection.remove($index)
   End if
  End if
  $data.inputSent:=True
  $data.stepDeadline:=Milliseconds+2000
  AXB_PollGuard.context.controlInput:=New object("action"; $data.action.id; "serial"; $data.serial; "point"; New collection($x; $y))
  return New object("status"; "pending"; "confirm"; Formula(AXB_ListSubformSelect($1)); "data"; $data)
 End if
End for each
End for
