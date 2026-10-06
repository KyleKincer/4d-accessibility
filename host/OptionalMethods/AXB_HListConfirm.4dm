// Select or disclose a hierarchical list item through 4D's own keyboard handling,
// then confirm the list's resulting state. A key needs no item geometry, so a
// partly scrolled list, item icons or fonts cannot redirect it to another item;
// 4D scrolls the item into view and runs the list's normal events.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid : Object
var $rows : Collection
var $index : Integer
var $name; $neighbor : Text
$result:=New object("status"; "rejected"; "message"; "Hierarchical list changed before completion")
$name:=$data.options.objectName
If ((Current form window#Frontmost window) | (Milliseconds>=$data.deadline) | Not(OBJECT Get enabled(*; $name)))
 return
End if
$reply:=AXB_HList("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True) || Not(OB Is defined($data.state.positions; $data.target)))
 return
End if
$grid:=$data.state.descriptor
If ($data.kind="reveal")
 If (AXB_KeyIndex($grid.visible; $data.target)>=0)
  return New object("status"; "completed"; "message"; "List item revealed")
 End if
 return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
End if
If (($data.kind="disclose") && ($grid.outline[$data.target].expanded=$data.expanded))
 return New object("status"; "completed"; "message"; Choose($data.expanded; "List item expanded"; "List item collapsed"))
End if
$data.selected:=AXB_KeyIndex($grid.selected; $data.target)>=0
If (($data.kind="select") && $data.selected)
 return New object("status"; "completed"; "message"; "List item selected")
End if
If ($data.keySent=True)
 // Wait for 4D to apply the key; a disclosure continues once its item is selected.
 If (($data.kind="disclose") && $data.selected && Not($data.toggleSent=True))
  $data.keySent:=False
 Else
  return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
 End if
End if
// This runs in the list's own form, so its focused object is the one 4D reports.
If (Compare strings(OBJECT Get name(Object with focus); $name; sk char codes)#0)
 If ($data.focusRequested=True)
  return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
 End if
 // Entering the list runs its On Getting Focus, as clicking into it would.
 $data.focusRequested:=True
 GOTO OBJECT(*; $name)
 return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
End if
If ($data.selected)
 // Right toggles the selected item in 4D's list, firing On Expand or On Collapse.
 $data.toggleSent:=True
 $data.keySent:=True
 POST KEY(Right arrow key; 0; Current process)
 return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
End if
// Select the visible neighbor without an event, then move to the item with one
// arrow key, exactly as a keyboard user would.
$rows:=$grid.rows
$index:=$rows.indexOf($data.target)
If ($rows.length<2)
 $result.message:="A single list item has no keyboard neighbor"
 return
End if
$neighbor:=Choose($index>0; $rows[$index-1]; $rows[1])
SELECT LIST ITEMS BY REFERENCE($data.state.list; $data.state.positions[$neighbor])
$data.keySent:=True
POST KEY(Choose($index>0; Down arrow key; Up arrow key); 0; Current process)
return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
