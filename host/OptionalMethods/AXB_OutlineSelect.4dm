// Select one leaf of a grouped list box from the keyboard. The nearest leaf above
// it (or below) is selected without an event, then the arrow keys move to it
// through any group rows between, exactly as a user's keys do: the list box
// runs On Selection Change at each row and scrolls the leaf into view.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid; $outline : Object
var $rows : Collection
var $name; $key; $target : Text
var $index; $neighbor; $steps; $i : Integer
$result:=New object("status"; "rejected"; "message"; "Grouped grid changed before selection")
$name:=$data.options.objectName
If ((Current form window#Frontmost window) | Not(OBJECT Get enabled(*; $name)))
 return
End if
If ($data.start=True)
 // Resolve the request against the published state: one leaf, which it adds.
 $grid:=$data.state.descriptor
 If (Not($grid.actions.select=True) || (Value type($data.action.value)#Is collection))
  return
 End if
 $target:=""
 For each ($key; $data.action.value)
  If (Not(OB Is defined($data.state.positions; $key)) || ($grid.outline[$key]=Null) || ($grid.outline[$key].kind#"leaf"))
   return
  End if
  If (AXB_KeyIndex($grid.selected; $key)<0)
   If ($target#"")
    $result.message:="Select one grouped row at a time"
    return
   End if
   $target:=$key
  End if
 End for each
 If ($target="")
  If ($data.action.value.length=$grid.selected.length)
   return New object("status"; "completed"; "message"; "Grouped row already selected")
  End if
  $result.message:="A grouped row cannot be deselected through accessibility"
  return
 End if
 return New object("status"; "pending"; "confirm"; Formula(AXB_OutlineSelect($1)); "data"; New object("state"; $data.state; "options"; $data.options; "action"; $data.action; \
  "generation"; $grid.generation; "target"; $target; "deadline"; Milliseconds+4000))
End if
If (Milliseconds>=$data.deadline)
 return
End if
$reply:=AXB_GridListbox("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$grid:=$data.state.descriptor
If (($grid.generation#$data.generation) || Not(OB Is defined($data.state.positions; $data.target)))
 return
End if
If (($grid.selected.length=1) && ($grid.selected[0]=$data.target))
 return New object("status"; "completed"; "message"; "Grouped row selected")
End if
If ($data.keySent=True)
 return New object("status"; "pending"; "confirm"; Formula(AXB_OutlineSelect($1)); "data"; $data)
End if
// The keys go to the list box only once it has focus, as clicking into it would give.
If (Compare strings(OBJECT Get name(Object with focus); $name; sk char codes)#0)
 If (Not($data.focusRequested=True))
  $data.focusRequested:=True
  GOTO OBJECT(*; $name)
 End if
 return New object("status"; "pending"; "confirm"; Formula(AXB_OutlineSelect($1)); "data"; $data)
End if
$rows:=$grid.rows
$index:=$rows.indexOf($data.target)
$neighbor:=-1
For ($i; $index-1; 0; -1)
 If ($grid.outline[$rows[$i]].kind="leaf")
  $neighbor:=$i
  break
 End if
End for
If ($neighbor<0)
 For ($i; $index+1; $rows.length-1)
  If ($grid.outline[$rows[$i]].kind="leaf")
   $neighbor:=$i
   break
  End if
 End for
End if
If (($index<0) | ($neighbor<0))
 $result.message:="A single grouped row has no keyboard neighbor"
 return
End if
LISTBOX SELECT ROW(*; $name; $data.state.positions[$rows[$neighbor]]; lk replace selection)
$steps:=Abs($index-$neighbor)
For ($i; 1; $steps)
 POST KEY(Choose($neighbor<$index; Down arrow key; Up arrow key); 0; Current process)
End for
$data.keySent:=True
return New object("status"; "pending"; "confirm"; Formula(AXB_OutlineSelect($1)); "data"; $data)
