#DECLARE($data : Object)
var $root : Object
If (File("/RESOURCES/prepare-failure.json").exists)
 $data.prepareFailure:=JSON Parse(File("/RESOURCES/prepare-failure.json").getText()).error
End if
If ($data.kind="child")
 return
End if
$root:=AXB_FormContext
If ($root#Null)
 If ($root.receipt#Null)
  $data.lastReceipt:=$root.receipt
 End if
End if
If ($data.kind="parent")
 File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "runId"; $data.config.runId; "compiled"; Is compiled mode; "originalLoad"; $data.originalLoad; "bridgeAbsentDuringLoad"; $data.bridgeAbsentDuringLoad; "timerFirings"; $data.timerFirings; "receipt"; $data.lastReceipt; "screenCenters"; $data.screenCenters; "leftName"; $data.left.name; "leftCalls"; $data.left.calls; "rightName"; $data.right.name; "rightCalls"; $data.right.calls; "rightTimers"; $data.right.timerFirings; "rightOriginalLoad"; $data.right.originalLoad; "rightError"; $data.right.axbError; "oldLeftUnloaded"; $data.oldLeftUnloaded; "oldLeftCleanupName"; $data.oldLeft.cleanupSawName; "oldRightStopped"; ($data.oldRight#Null) && (AXB_FormView($data.oldRight)=Null); "humanReplacements"; $data.humanReplacements; "leftPrepared"; $data.leftPrepared; "rightPrepared"; $data.rightPrepared)))
 return
End if
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "runId"; $data.config.runId; "compiled"; Is compiled mode; "name"; $data.name; "message"; $data.message; "calls"; $data.calls; "humanEvents"; $data.humanEvents; "timerFirings"; $data.timerFirings; "originalLoad"; $data.originalLoad; "bridgeAbsentDuringLoad"; $data.bridgeAbsentDuringLoad; "bridgeError"; $data.axbError; "startFailure"; $data.startFailure; "prepareFailure"; $data.prepareFailure; "returnedBeforeClose"; $data.returnedBeforeClose; "bridgeUnprepared"; ($data.axbDynamic=Null) & (AXB_FormView($data)=Null) & (AXB_FormContext=Null); "receipt"; $data.lastReceipt; "screenCenters"; $data.screenCenters)))
