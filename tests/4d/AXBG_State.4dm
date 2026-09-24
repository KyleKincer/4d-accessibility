var $selection : Collection
var $state : Object
var $row; $far : Integer
var $edited : Text
$edited:=""
If (Is editing text)
 $edited:=Get edited text
End if
$far:=Find in array(aGridKey; "line-0600")
$selection:=New collection
For ($row; 1; Size of array(aGridKey))
 If (aGridSelected{$row})
  $selection.push(aGridKey{$row})
 End if
End for
$state:=New object("phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "start"; Form.startResult; "bridgeError"; Form.axbError; "failure"; Form.failure; "selected"; $selection; "hooks"; Form.hooks; "hookSelection"; Form.hookSelection; "timerTicks"; Form.timerTicks; "note"; Form.note; "first"; aGridKey{1}; "rows"; Size of array(aGridKey); "receipt"; Form.axbForm.receipt; "edited"; $edited; "focus"; OBJECT Get name(Object with focus); "farValue"; aGridName{$far}; "changes"; Form.changes; "edits"; Form.edits; "filtered"; Form.filtered)
$state.diagnostics:=AXB_Form("diagnostics"; New object)
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
