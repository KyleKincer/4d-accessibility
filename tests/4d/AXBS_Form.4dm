var $reply; $left; $right; $panel; $scroll : Object
var $name : Text
var $x; $y : Integer
Case of
 : (Form event code=On Load)
  Form.record:="first"
  Form.hidden:=False
  Form.disabled:=False
  Form.collapsed:=False
  Form.timerCalls:=0
  $reply:=AXB_Form("start"; New object("label"; "Scrollable forms"; "scope"; Formula(Form.record)))
  Form.start:=$reply
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.timerCalls:=Form.timerCalls+1
  EXECUTE METHOD IN SUBFORM("Left"; "AXBS_Read"; $left)
  EXECUTE METHOD IN SUBFORM("Right"; "AXBS_Read"; $right)
  EXECUTE METHOD IN SUBFORM("Panel"; "AXBS_PanelRead"; $panel)
  $scroll:=New object
  For each ($name; New collection("Left"; "Right"; "Panel"))
   OBJECT GET SCROLL POSITION(*; $name; $y; $x)
   $scroll[$name]:=New collection($x; $y)
  End for each
  If (Form.axbForm.receipt#Null)
   Form.lastReceipt:=Form.axbForm.receipt
  End if
  File("/RESOURCES/state.json").setText(JSON Stringify(New object("runId"; Form.runId; "start"; Form.start; "left"; $left; "right"; $right; "panel"; $panel; "scroll"; $scroll; "timerCalls"; Form.timerCalls; "receipt"; Form.lastReceipt; "error"; Form.axbError)))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
