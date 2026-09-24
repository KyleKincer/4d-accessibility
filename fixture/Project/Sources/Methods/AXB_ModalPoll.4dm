var $node; $snapshot; $reply : Object
$node:=AXB_ControlNode("CloseModal"; "close-modal"; "button"; "Close modal"; ""; True)
$snapshot:=New object("version"; 1; "revision"; 1; "label"; "Accessible modal"; "enabled"; True; "nodes"; New collection($node))
$reply:=JSON Parse(AXB Exchange(Current form window; Form.session; JSON Stringify(New object("snapshot"; $snapshot))))
If (Value type($reply.action)=Is object)
 If (($reply.action.node="close-modal") & ($reply.action.operation="press") & ($reply.action.session=Form.session))
  CANCEL
 End if
End if
