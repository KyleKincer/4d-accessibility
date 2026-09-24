// Test-only failure evidence. Never log formulas, credentials, or form values.
var $report : Object
$report:=New object("phase"; "failed"; "error"; Error; "method"; Error method; "line"; Error line; "compiled"; Is compiled mode)
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($report; *))
QUIT 4D
ABORT
