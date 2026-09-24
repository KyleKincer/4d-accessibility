var $row : Integer
Form.hooks:=Form.hooks+1
Form.hookSelection:=New collection
For ($row; 1; Size of array(aGridKey))
 If (aGridSelected{$row})
  Form.hookSelection.push(aGridKey{$row})
 End if
End for
If (Form.rejectSelection=True)
 LISTBOX SELECT ROW(*; "Items"; 0; lk remove from selection)
End if
AXBG_State
