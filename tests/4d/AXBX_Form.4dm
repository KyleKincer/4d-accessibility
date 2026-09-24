var $reply : Object
Case of
 : (Form event code=On Load)
  Form.message:="Ready"
  Form.pageText:="Second page"
  Form.timerFirings:=0
  $reply:=AXB_Form("start"; New object("label"; "Composite example"; "describe"; Formula(AXBX_Describe); "apply"; Formula(AXBX_Apply($1)); "onError"; Formula(AXBX_Failed($1))))
  If (Not($reply.ok=True))
   Form.message:=$reply.error
  End if
  SET TIMER(6)
 : (Form event code=On Timer)
  SET TIMER(0)
  If (Form.recovering=True)
   Form.panel.inner.injectError:=False
   Form.recovering:=False
   $reply:=AXB_Form("start"; New object("label"; "Composite example"; "describe"; Formula(AXBX_Describe); "apply"; Formula(AXBX_Apply($1)); "onError"; Formula(AXBX_Failed($1))))
  Else
   Form.timerFirings:=Form.timerFirings+1
  End if
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
