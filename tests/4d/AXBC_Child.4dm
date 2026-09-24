// Ordinary application initialization. There are no bridge hooks in children.
If ((Value type(Form)#Is object) | (Form=Null))
 return
End if
If (Form event code=On Load)
 If (Form.name=Null)
  Form.name:="Implicit"
  Form.clicked:=0
 End if
End if
