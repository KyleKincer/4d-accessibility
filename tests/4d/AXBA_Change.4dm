#DECLARE($name : Text)
Case of
 : ($name="sort")
  SORT ARRAY(aLeftLineKey; aLeftItem; aLeftDescription; <)
  AL_SetAreaLongProperty(Form.left.area; ALP_Area_UpdateData; 0)
 : ($name="hide")
  OBJECT SET VISIBLE(*; "Left"; Not(OBJECT Get visible(*; "Left")))
 : ($name="disable")
  OBJECT SET ENABLED(*; "Right"; Not(OBJECT Get enabled(*; "Right")))
 : ($name="replace")
  EXECUTE METHOD IN SUBFORM("Left"; "AXBA_Stop")
  Form.oldLeft:=Form.left
  Form.left:=New object("side"; "Left"; "recordID"; "left-replacement"; "loadedRecordID"; "left-replacement"; "gridReady"; True)
  OBJECT SET VALUE("Left"; Form.left)
  OBJECT SET SUBFORM(*; "Left"; "AlternateLines")
 : ($name="identity")
  aLeftLineKey{1}:="Case"
  aLeftLineKey{2}:="case"
  aLeftLineKey{3}:="café"
  aLeftLineKey{4}:="cafe"
  AL_SetAreaLongProperty(Form.left.area; ALP_Area_UpdateData; 0)
  AL_SetRowLongProperty(Form.left.area; 1; ALP_Row_Reveal; 0; 1)
 : ($name="reload")
  Form.left.gridReady:=False
  Form.left.recordID:="next-invoice"
 : ($name="loaded")
  Form.left.loadedRecordID:=Form.left.recordID
  Form.left.gridReady:=True
 : ($name="badkey")
  If (Form.savedKey=Null)
   Form.savedKey:=aLeftLineKey{200}
   aLeftLineKey{200}:=aLeftLineKey{1}
  Else
   aLeftLineKey{200}:=Form.savedKey
   OB REMOVE(Form; "savedKey")
  End if
  AL_SetAreaLongProperty(Form.left.area; ALP_Area_UpdateData; 0)
End case
