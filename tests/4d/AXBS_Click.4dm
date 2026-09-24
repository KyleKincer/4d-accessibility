var $reply : Object
var $name : Text
Case of
 : (OBJECT Get name(Object current)="ClipWindow")
  SET WINDOW RECT(100; 100; 400; 400)
 : (OBJECT Get name(Object current)="RestoreWindow")
  SET WINDOW RECT(100; 100; 930; 650)
 : (OBJECT Get name(Object current)="Collapse")
  Form.collapsed:=Not(Form.collapsed)
  OBJECT SET COORDINATES(*; "Left"; 20; 20; Choose(Form.collapsed; 20; 390); 240)
 : (OBJECT Get name(Object current)="Reset")
  For each ($name; New collection("Left"; "Right"; "Panel"))
   OBJECT SET SCROLL POSITION(*; $name; 0; 0; *)
  End for each
 : (OBJECT Get name(Object current)="Hide")
  Form.hidden:=Not(Form.hidden)
  OBJECT SET VISIBLE(*; "Left"; Not(Form.hidden))
 : (OBJECT Get name(Object current)="Disable")
  Form.disabled:=Not(Form.disabled)
  OBJECT SET ENABLED(*; "Right"; Not(Form.disabled))
 : (OBJECT Get name(Object current)="Replace")
  $reply:=AXB_Form("invalidate"; New object("subform"; "Left"))
  Form.left:=New object("tag"; "Replacement")
  OBJECT SET SUBFORM(*; "Left"; "Child")
 : (OBJECT Get name(Object current)="Record")
  Form.record:=Generate UUID
End case
