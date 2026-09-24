// Use ordinary editor navigation when HIGHLIGHT TEXT has no effect on a cell.
// Confirm each step before sending another key, preserving host key handlers.
#DECLARE($data : Object) -> $result : Object
var $node; $editor : Object
var $start; $end; $position; $units; $code; $key; $modifiers : Integer
$result:=New object("status"; "rejected"; "message"; "Editor selection interrupted by the application")
$node:=$data.node
$editor:=AXB_TextEditor($node; "read"; Null)
If ((Milliseconds>$data.deadline) | Not($editor.active))
 return
End if
If (OBJECT Get font(*; $node.objectName)="%password")
 return
End if
If (Compare strings($editor.text; $data.text; sk char codes)#0)
 return
End if
$start:=$editor.start
$end:=$editor.end
If ($data.awaitSelection=True)
 If (($start#$data.expectedStart) | ($end#$data.expectedEnd))
  return
 End if
End if
If (($start=$data.start) & ($end=$data.end))
 return AXB_TextAction($data.action; $node; $data.options)
End if
$modifiers:=0
If ($data.selecting=True)
 $position:=$end
 $key:=Right arrow key
 $modifiers:=Shift key mask
Else
 If ($start#$end)
  $key:=Left arrow key
  $end:=$start
 Else
  If ($start>$data.start)
   $position:=$start-1
   $key:=Left arrow key
  Else
   If ($start<$data.start)
    $position:=$start
    $key:=Right arrow key
   Else
    $data.selecting:=True
    $position:=$end
    $key:=Right arrow key
    $modifiers:=Shift key mask
   End if
  End if
 End if
End if
If ($position>0)
 $units:=1
 $code:=Character code(Substring($data.text; $position; 1))
 If ((($key=Left arrow key) & ($code>=56320) & ($code<=57343)) | (($key=Right arrow key) & ($code>=55296) & ($code<=56319)))
  $units:=2
 End if
 If ($key=Left arrow key)
  $start:=$start-$units
  $end:=$start
 Else
  $end:=$end+$units
  If (Not($data.selecting))
   $start:=$end
  End if
 End if
End if
If (($start<1) | ($end>(Length($data.text)+1)) | ($end<$start))
 return
End if
$data.expectedStart:=$start
$data.expectedEnd:=$end
$data.awaitSelection:=True
POST KEY($key; $modifiers; Current process)
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextSelect($1)); "data"; $data)
