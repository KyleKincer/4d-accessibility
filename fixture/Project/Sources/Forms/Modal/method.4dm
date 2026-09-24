Case of
 : (Form event code=On Load)
  AXB_Start(Formula(AXB_ModalPoll))
  Form.session:=Form.axb.token.session
 : (Form event code=On Unload)
  AXB_Stop
End case
