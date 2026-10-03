Case of
 : (Form event code=On Load)
  SET TIMER(6)
 : (Form event code=On Timer)
  var $state : Object
  $state:=New object("runId"; Form.runId; "compiled"; Is compiled mode; "name"; Form.name; "clicks"; Form.clicks; "events"; Form.events; "webReady"; Form.webReady; "webURL"; Form.webURL; "webError"; Form.webError; "focus"; OBJECT Get name(Object with focus))
  $state.areas:=AXB_Area("diagnostics"; ""; "")
  $state.diagnostics:=AXB_Form("diagnostics"; New object)
  $state.info:=AXB_Host("info"; New object)
  File("/RESOURCES/state.json").setText(JSON Stringify($state))
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
End case
