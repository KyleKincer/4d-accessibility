var $reply : Object
var $x; $y : Integer
var $name : Text
$name:=OBJECT Get name(Object current)
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
AXBC_Events.push(New object("object"; $name; "event"; Form event code; "origin"; New collection($x; $y)))
Case of
 : ($name="Replace")
  $reply:=AXB_Form("invalidate"; New object("subform"; "Left"))
  Form.invalidated:=$reply
  OBJECT SET SUBFORM(*; "Left"; "Child")
 : ($name="Hide")
  Form.hidden:=Not(Form.hidden)
  OBJECT SET VISIBLE(*; "Left"; Not(Form.hidden))
 : ($name="Disable")
  Form.disabled:=Not(Form.disabled)
  OBJECT SET ENABLED(*; "Right"; Not(Form.disabled))
 : ($name="Record")
  Form.record:=Generate UUID
 : ($name="Remember")
  If (Form=Null)
   AXBC_UnboundClicks:=AXBC_UnboundClicks+1
  Else
   Form.clicked:=Form.clicked+1
  End if
End case
