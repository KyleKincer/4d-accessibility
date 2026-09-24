var $nodes : Collection
var $definition; $reply; $snapshot; $envelope; $action; $result : Object
var $state : Text
$nodes:=New collection
For each ($definition; New collection(\
 New object("objectName"; "Name"; "id"; "name"; "role"; "textfield"; "label"; "Fixture name"; "value"; Form.name; "enabled"; True); \
 New object("objectName"; "Allowed"; "id"; "allowed"; "role"; "checkbox"; "label"; "Allow submit"; "value"; Form.allowed; "enabled"; True); \
 New object("objectName"; "Submit"; "id"; "submit"; "role"; "button"; "label"; "Submit"; "value"; ""; "enabled"; Form.allowed); \
 New object("objectName"; "Hide"; "id"; "hide"; "role"; "button"; "label"; "Toggle name visibility"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Restart"; "id"; "restart"; "role"; "button"; "label"; "Restart bridge"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Close"; "id"; "close"; "role"; "button"; "label"; "Close fixture"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Status"; "id"; "status"; "role"; "text"; "label"; "Result"; "value"; Form.message; "enabled"; True)))
 $reply:=AXB_Host("node"; $definition)
 If (Not($reply.ok=True))
  Form.message:="Node failed: "+$reply.error
  $reply:=AXB_Host("stop"; New object)
  return
 End if
 $nodes.push($reply.node)
End for each
$snapshot:=New object("version"; 1; "label"; "Optional host fixture"; "enabled"; Current form window=Frontmost window; "nodes"; $nodes)
$state:=JSON Stringify($snapshot)
If ($state#Form.lastState)
 Form.revision:=Form.revision+1
 Form.lastState:=$state
End if
$snapshot.revision:=Form.revision
$envelope:=New object("snapshot"; $snapshot)
If (Value type(Form.receipt)=Is object)
 $envelope.receipt:=Form.receipt
End if
$reply:=AXB_Host("exchange"; New object("session"; Form.session; "envelope"; $envelope))
If (Not($reply.ok=True))
 File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "error"; $reply.error)))
 $reply:=AXB_Host("stop"; New object)
 return
End if
OB REMOVE(Form; "receipt")
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "dynamic"; Form.dynamic; "componentInfo"; Form.componentInfo; "timerFirings"; Form.timerFirings; "checks"; Form.checks)))
If (Value type($reply.action)=Is object)
 $action:=$reply.action
 $result:=New object("status"; "rejected"; "message"; "Stale action")
 If (($action.session=Form.session) & ($action.revision=Form.revision) & (Current form window=Frontmost window))
  $result:=AXBH_Apply($action.node; $action.operation; $action.value)
 End if
 // Restart/close invalidates the previous session, so never attach its receipt
 // to the replacement. Other operations are acknowledged on the next snapshot.
 If ($action.session=Form.session)
  $result.id:=$action.id
  Form.receipt:=$result
 End if
End if
