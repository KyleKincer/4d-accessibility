#DECLARE($kind : Text)
var $keys : Collection
var $i : Integer
var $missing : Text
If (Form.failConfirm=True)
 $missing:=File("/RESOURCES/intentional-missing-confirmation-test-file").getText()
End if
$keys:=New collection
If ($kind="array")
 For ($i; 1; Size of array(aListSelected))
  If (aListSelected{$i})
   $keys.push(aListID{$i})
  End if
 End for
Else
 $keys:=Form.selected.extract("id")
End if
If (Form.hooks[$kind]=Null)
 Form.hooks[$kind]:=New object("calls"; 0)
End if
Form.hooks[$kind].calls:=Form.hooks[$kind].calls+1
Form.hooks[$kind].keys:=$keys
If (Form.rejectSelection=True)
 Form.rejectSelection:=False
 If ($kind="array")
  LISTBOX SELECT ROW(*; "Array"; 0; lk remove from selection)
 Else
  LISTBOX SELECT ROW(*; "Collection"; 0; lk remove from selection)
 End if
End if
If (Form.scopeOnSelection=True)
 Form.scopeOnSelection:=False
 Form.scope:=Generate UUID
End if
