#DECLARE($data : Object) -> $result : Object
var $character; $current : Text
var $code; $nextCode : Integer
var $protected : Boolean
var $editor; $native : Object
$result:=New object("status"; "rejected"; "message"; "Text entry interrupted by the application")
If (Milliseconds>$data.deadline)
 return
End if
$protected:=OBJECT Get font(*; $data.objectName)="%password"
If (($data.options#Null) && ($data.options.controls#Null))
 If ($data.options.controls[$data.objectName]#Null)
  $protected:=$protected | ($data.options.controls[$data.objectName].protected=True)
 End if
End if
// Do not read an editor whose protection changed during a host event.
If ($protected#$data.protected)
 return
End if
$editor:=AXB_TextEditor($data.editorNode; "read"; Null)
If (Not($editor.active))
 return
End if
// Native delivery is asynchronous. An unchanged editor is not evidence of
// rejection until the exact input has finished on the native event thread.
If ($data.awaitNative=True)
 $native:=AXB_PollGuard.context.editorInputResult
 If (($native=Null) || ($native.action#$data.actionID) || ($native.serial#$data.nativeSerial))
  $result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextStep($1)); "data"; $data)
  return
 End if
 If (Not($native.accepted=True))
  $result.message:="Editor changed before native input delivery"
  return
 End if
End if
$data.awaitNative:=False
If (($data.insert=True) & $data.first)
 // A long update is one real input-method insertion. 4D runs its ordinary
 // keystroke and validation hooks with that string, as for bulk user input.
 // Wait until the editor has applied HIGHLIGHT TEXT before dispatching it.
 If (($editor.start#$data.selection[0]) | ($editor.end#$data.selection[1]))
  If (Milliseconds<$data.selectionDeadline)
   $result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextStep($1)); "data"; $data)
  End if
  return
 End if
 AXB_PollGuard.context.editorInput:=New object("action"; $data.actionID; "serial"; 1; "mode"; "insert"; "text"; Substring($data.text; 1; $data.insertLength); "selection"; New collection($editor.start-1; $editor.end-$editor.start))
 $data.awaitNative:=True
 $data.nativeSerial:=1
 $data.expected:=$data.prefix+Substring($data.text; 1; $data.insertLength)+$data.suffix
 $data.next:=$data.insertLength+1
 $data.first:=False
 $result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextStep($1)); "data"; $data)
 return
End if
If (Not($data.first) & Not($data.protected))
 $current:=$editor.text
 If (Compare strings($current; $data.expected; sk char codes)#0)
  $result.message:="Application changed or rejected the text entry"
  return
 End if
End if
If (($data.next>Length($data.text)) & Not($data.first))
 $result:=New object("status"; "completed"; "message"; "Text entered in the editor; normal validation runs when editing ends")
 If ($data.protected)
  $result.message:="Protected text entry dispatched; contents are not read back"
 End if
 return
End if
If (Length($data.text)=0)
 POST KEY(8; 0; Current process)
 $data.expected:=$data.prefix+$data.suffix
 $data.next:=1
Else
 $character:=Substring($data.text; $data.next; 1)
 $code:=Character code($character)
 // Keep a UTF-16 surrogate pair together as one Unicode character.
 If (($code>=55296) & ($code<=56319) & ($data.next<Length($data.text)))
  $nextCode:=Character code(Substring($data.text; $data.next+1; 1))
  If (($nextCode>=56320) & ($nextCode<=57343))
   $character:=$character+Substring($data.text; $data.next+1; 1)
  End if
 End if
 If (Length($character)=2)
  AXB_PollGuard.context.editorInput:=New object("action"; $data.actionID; "serial"; $data.next; "text"; $character)
  $data.awaitNative:=True
  $data.nativeSerial:=$data.next
 Else
  POST KEY($code; 0; Current process)
 End if
 $data.next:=$data.next+Length($character)
 $data.expected:=$data.prefix+Substring($data.text; 1; $data.next-1)+$data.suffix
End if
$data.first:=False
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextStep($1)); "data"; $data)
