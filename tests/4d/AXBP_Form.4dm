var $options; $child; $result : Object
Case of
 : (Form event code=On Load)
  $options:=New object("label"; "Complete AreaList form"; "onError"; Formula(AXBP_Failed($1)); "children"; New object)
  $child:=New object("label"; "Left invoice"; "scope"; Formula(Form.scope))
  $child.grids:=New object("Items"; New object("kind"; "areaList"; "label"; "Left lines"; "keys"; ->aLeftKey; "ready"; Formula(Form.ready); "onSelection"; Formula(AXBP_Selected)))
  $child.grids.Items.columns:=New object("5"; New object("label"; "Readiness"; "value"; Formula(Form.side+" ready")); "6"; New object("decorative"; True))
  $options.children.Left:=$child
  $child:=New object("label"; "Right invoice"; "scope"; Formula(Form.scope))
  $child.grids:=New object("Items"; New object("kind"; "areaList"; "label"; "Right lines"; "keys"; ->aRightKey; "keyColumn"; 7; "ready"; Formula(Form.ready); "onSelection"; Formula(AXBP_Selected)))
  $child.grids.Items.columns:=New object("5"; New object("label"; "Readiness"; "value"; Formula(Form.side+" ready")); "6"; New object("decorative"; True))
  $options.children.Right:=$child
  $result:=AXB_Form("start"; $options)
  Form.startResult:=$result
  SET TIMER(6)
  AXBP_State
 : (Form event code=On Timer)
  Form.timerTicks:=Form.timerTicks+1
  AXBP_State
 : (Form event code=On Unload)
  $result:=AXB_Form("stop"; New object)
End case
