var $result; $options : Object
Case of
 : (Form event code=On Load)
  ON ERR CALL("AXBG_Error")
  Form.scope:="invoice-a"
  Form.hooks:=0
  Form.rejectSelection:=False
  Form.timerTicks:=0
  Form.filtered:=0
  Form.changes:=0
  Form.edits:=0
  Form.note:="Original note"
  Form.linesReady:=True
  OBJECT SET VISIBLE(*; "RowID"; False)
  $options:=New object("label"; "Complete grid form"; "scope"; Formula(Form.scope); "onError"; Formula(AXBG_Failed($1)))
  $options.grids:=New object("Items"; New object("kind"; "array"; "keyColumn"; "RowID"; "label"; "Invoice lines"; "ready"; Formula(Form.linesReady); "onSelection"; Formula(AXBG_Selected)))
  $result:=AXB_Form("start"; $options)
  Form.startResult:=$result
  SET TIMER(6)
  AXBG_State
 : (Form event code=On Timer)
  Form.timerTicks:=Form.timerTicks+1
  AXBG_State
 : (Form event code=On Unload)
  $result:=AXB_Form("stop"; New object)
End case
