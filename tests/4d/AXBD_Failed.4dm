#DECLARE($failure : Object)
If ($failure.phase="prepare")
 File("/RESOURCES/prepare-failure.json").setText(JSON Stringify($failure))
 return
End if
If ($failure.phase="start")
 Form.startFailure:=$failure.error
 return
End if
File("/RESOURCES/callback-failure.json").setText(JSON Stringify(New object("phase"; "failed"; "failure"; $failure)))
