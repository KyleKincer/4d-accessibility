#DECLARE($data : Object) -> $result : Object
$result:=New object("status"; "rejected"; "message"; "Application did not enter the requested text editor")
If (Not(AXB_ControlFocus($data.node.objectName)))
 return
End if
If (Is editing text)
 // Focus can run host handlers which change editability or masking.
 $result:=AXB_ControlAction($data.action; $data.options)
Else
 If (Milliseconds<$data.deadline)
  $result:=New object("status"; "pending"; "confirm"; Formula(AXB_TextReady($1)); "data"; $data)
 End if
End if
