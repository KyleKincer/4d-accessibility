// Drive the existing editor. Never assign its backing variable or invoke a
// second validation implementation. One Unicode character is posted per step
// so a handler moving focus cannot send the rest of the text to another field.
#DECLARE($action : Object; $node : Object; $options : Object) -> $result : Object
var $data; $editor : Object
var $text; $before; $insert : Text
var $start; $end; $i; $code : Integer
$result:=New object("status"; "rejected"; "message"; "Text operation is unavailable")
If ($node.protected & ($action.operation#"setValue"))
 return
End if
If ($action.operation#"setSelection")
 If (Value type($action.value)#Is text)
  return
 End if
 $insert:=$action.value
 // A value is text, not navigation or a keyboard shortcut. Newlines are valid
 // only in multiline fields. Normalize line endings to 4D's Return character.
 $insert:=Replace string($insert; Char(13)+Char(10); Char(13))
 $insert:=Replace string($insert; Char(10); Char(13))
 For ($i; 1; Length($insert))
  $code:=Character code(Substring($insert; $i; 1))
  If ((($code<32) & Not(($code=13) & $node.multiline)) | ($code=127) | (($code>=63232) & ($code<=63487)))
   $result.message:="Text contains a navigation or control character"
   return
  End if
 End for
End if
$editor:=AXB_TextEditor($node; "read"; Null)
If (Not($editor.active))
 If ($node.gridCell#Null)
  return
 End if
 GOTO OBJECT(*; $node.objectName)
 // 4D can announce focus before it installs the editor. Wait for the next
 // event cycle rather than reading or selecting the previous editor's text.
 $result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextReady($1)); "data"; New object("action"; $action; "node"; $node; "options"; $options; "deadline"; Milliseconds+1000))
 return
End if
If (Not($node.protected))
 $before:=$editor.text
End if
Case of
 : ($action.operation="setValue")
  $start:=1
  $end:=Length($before)+1
  If ($node.protected)
   $end:=2147483647
  End if
 : ($action.operation="replaceSelection")
  $start:=$editor.start
  $end:=$editor.end
 : ($action.operation="setSelection")
  If ((Value type($action.value)#Is collection) || ($action.value.length#2))
   return
  End if
  $start:=$action.value[0]+1
  $end:=$start+$action.value[1]
End case
If (($start<1) | ($end<$start) | (Not($node.protected) & ($end>(Length($before)+1))))
 $result.message:="Text selection is out of range"
 return
End if
If (Not($node.protected))
 For each ($i; New collection($start; $end))
  If (($i>0) & ($i<=Length($before)))
   $code:=Character code(Substring($before; $i; 1))
   If (($code>=56320) & ($code<=57343))
    $result.message:="Text selection splits a Unicode character"
    return
   End if
  End if
 End for each
End if
$editor:=AXB_TextEditor($node; "select"; New collection($start; $end))
If (Not($editor.active))
 return
End if
If ($node.gridCell#Null)
 $i:=$editor.start
 $code:=$editor.end
 If (($i#$start) | ($code#$end))
  $data:=New object("action"; $action; "node"; $node; "options"; $options; "text"; $before; "start"; $start; "end"; $end; "deadline"; Milliseconds+120000; "selecting"; False)
  return AXB_TextSelect($data)
 End if
End if
If (($action.operation#"setSelection") & (Length($insert)=0) & ($start=$end))
 $result:=New object("status"; "completed"; "message"; "Editor text is unchanged")
 return
End if
If ($action.operation="setSelection")
 $i:=$editor.start
 $code:=$editor.end
 If (($i=$start) & ($code=$end))
  $result:=New object("status"; "completed"; "message"; "Editor selection confirmed")
 End if
 return
End if
$data:=New object("objectName"; $node.objectName; "protected"; $node.protected; "text"; $insert; "next"; 1; "prefix"; Substring($before; 1; $start-1); "suffix"; Substring($before; $end); "deadline"; Milliseconds+120000; "first"; True)
$data.editorNode:=$node
$data.insert:=(Length($insert)>4096) & ($node.gridCell=Null) & Not($node.protected) & (AXB_PollGuard.context.nativeInsertion=True)
If ($data.insert)
 $data.insertLength:=Length($insert)
 // The native 4D input-method client drops trailing Returns. Preserve those
 // through the ordinary guarded key path after inserting the long prefix.
 While (($data.insertLength>0) && (Substring($insert; $data.insertLength; 1)=Char(13)))
  $data.insertLength:=$data.insertLength-1
 End while
 $data.insert:=$data.insertLength>4096
 $data.selection:=New collection($start; $end)
 $data.selectionDeadline:=Milliseconds+1500
End if
$data.actionID:=$action.id
$data.gridCell:=$node.gridCell
$data.options:=$options
$result:=AXB_TextStep($data)
