// Existing application behavior; the bridge neither calls nor duplicates it.
Case of
 : (Form event code=On Before Keystroke)
  If (Keystroke="!")
   FILTER KEYSTROKE("")
   Form.filtered:=Form.filtered+1
  End if
 : (Form event code=On Data Change)
  Form.changes:=Form.changes+1
 : (Form event code=On After Edit)
  Form.edits:=Form.edits+1
End case
