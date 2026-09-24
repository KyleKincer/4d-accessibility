// Synthetic application validation. Accessibility invokes the native event.
var $0; $column; $row : Integer
var $item; $saved : Object
$0:=0
LISTBOX GET CELL POSITION(*; "Items"; $column; $row)
Form.widgetEvents.push(New object("event"; Form event code; "column"; $column; "row"; $row))
If (Form event code=On Before Data Entry)
 If (Form.widgetReject=True)
  $0:=-1
 End if
 If (Form.widgetRedirect=True)
  GOTO OBJECT(*; "Note")
 End if
 If (Form.widgetRebind=True)
  Form.scope:="replaced-in-entry"
 End if
 If (Form.widgetDisable=True)
  OBJECT SET ENTERABLE(*; "Approved"; False)
 End if
End if
If ((Form event code=On Data Change) & (Form.widgetAfterRedirect=True))
 GOTO OBJECT(*; "Note")
End if
If ((Form event code=On Data Change) & (Form.widgetAfterDisable=True))
 OBJECT SET ENTERABLE(*; "Approved"; False)
End if
If ((Form event code=On Data Change) & (Form.widgetRevert=True) & ($column=4))
 If (Form.rows=Null)
  aGridCheck{$row}:=Not(aGridCheck{$row})
 Else
  $item:=Form.current
  $item.approved:=Not($item.approved)
  If (OB Instance of($item; 4D.Entity))
   $saved:=$item.save()
   If (Not($saved.success))
    Form.failure:="Synthetic validation could not save its correction"
   End if
  End if
 End if
End if
