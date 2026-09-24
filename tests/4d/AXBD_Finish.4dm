#DECLARE($data : Object)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.config.runId; "closed"; $data.closed; "stoppedBeforeUnload"; $data.stoppedBeforeUnload; "returnedBeforeClose"; $data.returnedBeforeClose; "calls"; $data.calls; "humanEvents"; $data.humanEvents; "closeCleanupCalls"; $data.closeCleanupCalls; "dialogOK"; $data.dialogOK; "loadCount"; $data.loadCount; "reopenStarted"; $data.reopenStarted)))
QUIT 4D
