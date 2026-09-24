var $reply : Object
Case of
 : (Form event code=On Load)
  Form.name:="Ada"
  Form.validName:="Ada"
  Form.secret:="synthetic-secret-never-publish"
  Form.notes:="First line\rSecond line"
  Form.summary:="Read-only summary"
  Form.amount:=1234.5
  Form.dueDate:=!2026-09-23!
  AXBF_Time:=?13:05:09?
  OBJECT SET FORMAT(*; "Amount"; "###,##0.00")
  OBJECT SET FORMAT(*; "DueDate"; Char(Internal date long))
  OBJECT SET FORMAT(*; "Appointment"; Char(HH MM SS))
  Form.allowed:=False
  Form.email:=1
  Form.phone:=0
  Form.saved:=0
  Form.events:=New collection
  ARRAY TEXT(AXBF_Choices; 3)
  AXBF_Choices{1}:="United States"
  AXBF_Choices{2}:="Canada"
  AXBF_Choices{3}:="United Kingdom"
  AXBF_Choices:=1
  OBJECT SET VISIBLE(*; "Hidden"; False)
  OBJECT SET ENABLED(*; "Disabled"; False)
  If (Not(Form.config.baseline) & Not(Form.config.dynamic))
   $reply:=AXB_Form("start"; New object("label"; "Contact details"))
   Form.start:=$reply
  End if
  SET TIMER(6)
 : (Form event code=On Timer)
  AXBF_State
 : (Form event code=On Unload)
  If (Not(Form.config.dynamic))
   $reply:=AXB_Form("stop"; New object)
  End if
End case
