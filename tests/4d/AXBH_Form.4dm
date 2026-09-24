var $reply : Object
Case of
 : (Form event code=On Load)
  Form.name:="Fixture tester"
  Form.validName:=Form.name
  Form.allowed:=True
  Form.count:=0
  Form.timerFirings:=0
  Form.message:="Ready"
  Form.revision:=0
  Form.lastState:=""
  Form.checks:=New collection
  $reply:=AXB_Host("info"; New object)
  Form.componentInfo:=$reply.componentInfo
  $reply:=AXB_Host("start"; New object("poll"; New object))
  Form.checks.push(New object("name"; "non-formula poll rejected"; "passed"; $reply.error="invalidPoll"))
  $reply:=AXB_Host("node"; New object("objectName"; "MissingControl"; "id"; "missing"; "role"; "button"; "label"; "Missing"; "value"; ""; "enabled"; True))
  Form.checks.push(New object("name"; "unknown control rejected"; "passed"; $reply.error="unknownControl"))
  $reply:=AXB_Host("start"; New object("poll"; Formula(AXBH_Poll)))
  If (Not($reply.ok=True))
   File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "error"; $reply.error)))
   CANCEL
  Else
   Form.session:=$reply.session
   $reply:=AXB_Host("exchange"; New object("session"; "stale"; "envelope"; New object))
   Form.checks.push(New object("name"; "foreign session rejected"; "passed"; $reply.error="inactiveSession"))
   SET TIMER(6)
  End if
 : (Form event code=On Timer)
  Form.timerFirings:=Form.timerFirings+1
  SET TIMER(0)
 : (Form event code=On Unload)
  $reply:=AXB_Host("stop"; New object)
End case
