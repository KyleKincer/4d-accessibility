var $reply; $state : Object
Case of
 : (Form event code=On Load)
  AXBC_RootStart:=AXB_Form("start"; New object("label"; "Shared-data root"))
  SET TIMER(6)
 : (Form event code=On Clicked)
  Form.rootRemembered:=Form.shared.name
 : (Form event code=On Timer)
  $state:=New object("runId"; AXBC_Config.runId; "start"; AXBC_RootStart; "name"; Form.shared.name; "remembered"; Form.rootRemembered; "failure"; Form.axbFailure)
  File("/RESOURCES/shared-root.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
