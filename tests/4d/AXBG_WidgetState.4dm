#DECLARE() -> $result : Object
var $command; $item : Object
var $key; $name : Text
var $column; $row : Integer
// The repeated peer is read for assertions, but commands belong to the main
// fixture form. Do not let a write between the two timer reads change peers.
If (Not(Form.widgetReadOnly=True) && File("/RESOURCES/widget-command.json").exists)
 $command:=JSON Parse(File("/RESOURCES/widget-command.json").getText())
 File("/RESOURCES/widget-command.json").delete()
 If ($command.action="configure")
  Form.widgetReject:=$command.reject=True
  Form.widgetRedirect:=$command.redirect=True
  Form.widgetRebind:=$command.rebind=True
  Form.widgetDisable:=$command.disable=True
  Form.widgetRevert:=$command.revert=True
  Form.widgetAfterRedirect:=$command.afterRedirect=True
  Form.widgetAfterDisable:=$command.afterDisable=True
  OBJECT SET ENTERABLE(*; "Approved"; True)
  If ($command.layout#Null)
   LISTBOX SET PROPERTY(*; "Items"; lk cell horizontal padding; $command.layout.padding)
   For each ($name; New collection("Approved"; "Mixed"))
    OBJECT SET HORIZONTAL ALIGNMENT(*; $name; $command.layout.alignment)
    LISTBOX SET PROPERTY(*; $name; lk cell horizontal padding; $command.layout.columnPadding)
   End for each
  End if
 End if
 Form.widgetSequence:=$command.sequence
End if
LISTBOX GET CELL POSITION(*; "Items"; $column; $row)
$result:=New object("sequence"; Form.widgetSequence; "events"; Form.widgetEvents; "column"; $column; "row"; $row; "rows"; New collection)
$result.columns:=New object("Approved"; New object("display"; LISTBOX Get property(*; "Approved"; lk display type); "format"; OBJECT Get format(*; "Approved")); "Decision"; New object("display"; LISTBOX Get property(*; "Decision"; lk display type); "format"; OBJECT Get format(*; "Decision")); "Mixed"; New object("display"; LISTBOX Get property(*; "Mixed"; lk display type); "format"; OBJECT Get format(*; "Mixed")))
If (Form.rows=Null)
 For ($row; 1; Size of array(aGridKey))
  $result.rows.push(New object("key"; aGridKey{$row}; "approved"; aGridCheck{$row}; "decision"; aGridPopup{$row}; "mixed"; aGridMixed{$row}))
 End for
Else
 For each ($item; Form.rows)
  $key:=$item.displayKey
  If ($key="")
   $key:=$item.id
  End if
  $result.rows.push(New object("key"; $key; "approved"; $item.approved; "decision"; $item.decision; "mixed"; $item.mixed))
 End for each
End if
