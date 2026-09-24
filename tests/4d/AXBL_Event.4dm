If (Form event code=On Selection Change)
 Form.nativeEvents:=Form.nativeEvents+1
 AXBL_Selection(Lowercase(OBJECT Get name(Object current)))
End if
