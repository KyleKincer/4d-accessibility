#DECLARE($data : Object)
var $root : Object
$root:=AXB_FormContext
If ($root.receipt#Null)
 $data.lastReceipt:=$root.receipt
End if
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "runId"; $data.config.runId; "compiled"; Is compiled mode; "left"; New object("area"; $data.left.area; "selected"; $data.left.selected; "nodes"; $data.left.nodes; "nativeEvents"; $data.left.nativeEvents); "right"; New object("area"; $data.right.area; "selected"; $data.right.selected; "nodes"; $data.right.nodes; "nativeEvents"; $data.right.nativeEvents); "receipt"; $data.lastReceipt; "screenCenters"; $data.screenCenters; "humanEvents"; $data.humanEvents; "timerFirings"; $data.timerFirings; "oldLeftStopped"; ($data.oldLeft#Null) && $data.oldLeft.stopped)))
