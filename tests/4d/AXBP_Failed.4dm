#DECLARE($failure : Object)
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "failure"; $failure)))
