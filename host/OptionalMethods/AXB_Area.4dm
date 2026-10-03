// Fixed area lifecycle entry point. Root startup is queued after application load.
// A form-owned dynamic pointer distinguishes repeated/shared child instances.
#DECLARE($operation : Text; $id : Text; $name : Text) -> $result : Object
var $record; $context; $options; $reply; $guard; $item; $failure : Object
var $label; $configuration : Text
var $registered : Boolean
ARRAY TEXT($methods; 0)
$result:=New object("ok"; True)
If ($operation="diagnostics")
 $result.areas:=New collection
 If (AXB_Areas=Null)
  return
 End if
 For each ($item; OB Values(AXB_Areas))
  If ($item.window=Current form window)
   $registered:=False
   $failure:=$item.failure
   If ($item.context#Null)
    $registered:=$item.context.active=True
    If ($item.context.failure#Null)
     $failure:=$item.context.failure
    End if
   End if
   If ($failure#Null)
    $failure:=OB Copy($failure)
   End if
   $result.areas.push(New object("state"; Choose(($item.state="active") && Not($registered); "stopped"; $item.state); "configured"; $item.configured=True; "configuration"; $item.configuration; "registered"; $registered; "failure"; $failure))
  End if
 End for each
 return
End if
If (($operation="reserve") | ($operation="attach"))
 If ((Current form window=0) | (($name#"__AXB_Bridge") & (Position("__AXB_Bridge."; $name)#1)))
  return New object("ok"; False; "error"; "invalidAreaContext")
 End if
 If (AXB_Areas=Null)
  AXB_Areas:=New object
 End if
 $record:=AXB_Areas[$id]
 If ($record=Null)
  $record:=New object("window"; Current form window; "name"; $name; "state"; "initializing"; "configuration"; Substring($name; Length("__AXB_Bridge.")+1))
  AXB_Areas[$id]:=$record
 End if
 If (($operation="reserve") | ($record.state#"initializing"))
  return
 End if
 $record.pointer:=OBJECT Get pointer(Object named; $name)
 $record.state:="queued"
 CALL FORM($record.window; Formula(AXB_Area("start"; $1; $2)); $id; $name)
 return
End if
$record:=AXB_Areas[$id]
If ($record=Null)
 return
End if
If ($operation="stop")
 // Remove first: a callback can close a dialog or create a replacement.
 OB REMOVE(AXB_Areas; $id)
 If ($record.context#Null)
  AXB_FormStop($record.context)
 End if
 return
End if
If (($operation#"start") | ($record.state#"queued"))
 return
End if
// CALL FORM has restored the root. An identically named child area must not
// register or retire that root, even when it shares data and lies at (0,0).
If (($record.window#Current form window) | ($record.pointer=Null))
 $record.state:="ignored"
 OB REMOVE($record; "focusObservation")
 OB REMOVE($record; "focusObservers")
 return
End if
If ($record.pointer#OBJECT Get pointer(Object named; $record.name))
 $record.state:="child"
 OB REMOVE($record; "focusObservation")
 OB REMOVE($record; "focusObservers")
 return
End if
$context:=AXB_FormContext
If ($context#Null)
 $record.state:="existingRegistration"
 AXB_FormObserver("transfer"; $record)
 OB REMOVE($record; "focusObservation")
 OB REMOVE($record; "focusObservers")
 return
End if
$guard:=New object("previousHandler"; Method called on error(ek local); "previousGuard"; AXB_AreaGuard; "record"; $record)
AXB_AreaGuard:=$guard
ON ERR CALL("AXB_AreaError"; ek local)
$configuration:=$record.configuration
If ($configuration="")
 $configuration:=Current form name
End if
$record.configuration:=$configuration
$label:=Get window title(Current form window)
If ($label="")
 $label:=$configuration
End if
If ($label="")
 $label:="Application form"
End if
$options:=New object("label"; $label)
METHOD GET NAMES($methods; "AXB_Configure")
If (Find in array($methods; "AXB_Configure")>0)
 EXECUTE METHOD("AXB_Configure"; $options; $configuration)
 $record.configured:=True
End if
If ($options=Null)
 // A central callback with no case for this form returns Null. Treat that as
 // no configuration rather than failing every unconfigured form.
 $options:=New object("label"; $label)
Else
 If (Value type($options)=Is object)
  If (Not(OB Is defined($options; "label")))
   $options:=OB Copy($options)
   $options.label:=$label
  End if
 End if
End if
If (($options#Null) && (Value type($options)=Is object) && Not(OB Is defined($options; "automationKey")) && ($configuration#""))
 $options:=OB Copy($options)
 $options.automationKey:=$configuration
End if
$record.options:=$options
If (($options#Null) && ($options.enabled=False))
 $record.state:="disabled"
Else
 $reply:=AXB_Host("info"; New object)
 If (Not($reply.ok=True))
  $result:=$reply
 Else
  If (($reply.componentInfo.capturedStop#1) | (Position("; areaLifecycle 1;"; $reply.nativeStatus)=0))
   $result:=New object("ok"; False; "error"; "areaLifecycleUnavailable")
  Else
   $record.starting:=True
   $result:=AXB_Form("start"; $options)
   $record.starting:=False
   $record.context:=AXB_FormContext
   If ($record.context#Null)
    $record.context.areaID:=$id
    AXB_FormObserver("transfer"; $record)
   End if
  End if
 End if
 If ($result.ok=True)
  $record.state:="active"
 Else
  $record.state:="failed"
  $record.failure:=$result
  If ($result.error#"dependencyUnavailable")
   $record.failureReported:=True
   AXB_DynamicFailure($result; $options; "start")
  End if
 End if
End if
OB REMOVE($record; "focusObservation")
OB REMOVE($record; "focusObservers")
ON ERR CALL($guard.previousHandler; ek local)
AXB_AreaGuard:=$guard.previousGuard
