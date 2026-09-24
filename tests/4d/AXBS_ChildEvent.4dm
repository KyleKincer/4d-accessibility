Case of
 : ((OBJECT Get name(Object current)="Wide") & (Form event code=On Clicked))
  Form.wideClicks:=Form.wideClicks+1
 : ((OBJECT Get name(Object current)="Remember") & (Form event code=On Clicked))
  Form.clicks:=Form.clicks+1
  Form.remembered:=Form.last
 : ((OBJECT Get name(Object current)="Last") & (Form event code=On Data Change))
  Form.edits:=Form.edits+1
End case
