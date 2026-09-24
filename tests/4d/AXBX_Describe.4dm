#DECLARE -> $description : Object
$description:=AXB_Controls(New collection(\
 New object("objectName"; "Fault"; "id"; "fault"; "role"; "button"; "label"; "Fail nested adapter"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Hide"; "id"; "hide"; "role"; "button"; "label"; "Toggle shipping"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Replace"; "id"; "replace"; "role"; "button"; "label"; "Replace shipping"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Scope"; "id"; "scope"; "role"; "button"; "label"; "Next record"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Page"; "id"; "page"; "role"; "button"; "label"; "Change page"; "value"; ""; "enabled"; True); \
 New object("objectName"; "PageOnly"; "id"; "pageonly"; "role"; "text"; "label"; "Second page"; "value"; Form.pageText; "enabled"; True); \
 New object("objectName"; "Status"; "id"; "rootstatus"; "role"; "text"; "label"; "Result"; "value"; Form.message; "enabled"; True)))
$description.scope:=String(Form.record)
$description.subforms:=New collection("Left"; "Right"; "Panel")
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "timerFirings"; Form.timerFirings; "bridgeError"; Form.axbError; "left"; Form.left.name; "right"; Form.right.name; "nested"; Form.panel.inner.name)))
