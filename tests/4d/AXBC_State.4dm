var $state; $part : Object
var $name : Text
$state:=New object("runId"; AXBC_Config.runId; "phase"; "ready"; "start"; Form.start; "compiled"; Is compiled mode; "ticks"; Form.ticks; "events"; AXBC_Events; "failure"; Form.axbFailure; "invalidated"; Form.invalidated; "children"; New object)
$state.nativeFocus:=JSON Parse(AXB Native focus(Current form window))
$state.rootFocus:=OBJECT Get name(Object with focus)
$state.diagnostics:=AXB_Form("diagnostics"; New object)
For each ($name; New collection("Left"; "Right"; "Scalar"; "Unbound"))
 EXECUTE METHOD IN SUBFORM($name; "AXBC_Read"; $part)
 $state.children[$name]:=$part
End for each
EXECUTE METHOD IN SUBFORM("Panel"; "AXBC_Nested"; $part)
$state.children.Nested:=$part
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
