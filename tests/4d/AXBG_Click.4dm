Case of
 : (OBJECT Get name(Object current)="Reject selection")
  Form.rejectSelection:=Not(Form.rejectSelection)
 : (OBJECT Get name(Object current)="Toggle ready")
  Form.linesReady:=Not(Form.linesReady)
 : (OBJECT Get name(Object current)="Toggle valid keys")
  If (Form.originalSecondKey=Null)
   Form.originalSecondKey:=aGridKey{2}
   aGridKey{2}:=aGridKey{1}
  Else
   aGridKey{2}:=Form.originalSecondKey
   OB REMOVE(Form; "originalSecondKey")
  End if
 : (OBJECT Get name(Object current)="Sort")
  LISTBOX SORT COLUMNS(*; "Items"; 1; <)
 : (OBJECT Get name(Object current)="Bottom")
  OBJECT SET SCROLL POSITION(*; "Items"; 594; 3; *)
 : (OBJECT Get name(Object current)="Top")
  OBJECT SET SCROLL POSITION(*; "Items"; 1; 1; *)
 : (OBJECT Get name(Object current)="Scope")
  Form.scope:=Generate UUID
 : (OBJECT Get name(Object current)="Remove")
  LISTBOX DELETE ROWS(*; "Items"; 1; 1)
End case
AXBG_State
