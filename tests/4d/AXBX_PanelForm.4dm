var $reply : Object
Case of
 : (Form event code=On Load)
  $reply:=AXB_Form("register"; New object("label"; "Panel"; "describe"; Formula(AXBX_PanelDescribe)))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
