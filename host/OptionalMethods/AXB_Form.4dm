// Application-facing lifecycle. Application formulas stay in their owning host.
#DECLARE($operation : Text; $options : Object) -> $result : Object
var $reply; $view; $context; $registry : Object
var $x; $y : Integer
var $aliases : Boolean
$result:=New object("ok"; False; "error"; "unsupportedOperation")
If (New collection("start"; "register"; "stop"; "invalidate"; "diagnostics"; "event").indexOf($operation)<0)
 return
End if
If (Current form window=0)
 $result.error:="noFormContext"
 return
End if
If ($operation="event")
 return AXB_FormEvent
End if
If ($operation="diagnostics")
 $context:=AXB_FormContext
 If ($context=Null)
  return New object("ok"; False; "error"; "unregisteredWindow")
 End if
 If ($context.diagnostics=Null)
  return New object("ok"; True; "ready"; False; "revision"; 0; "nodeCount"; 0; "issues"; New collection)
 End if
 // Return only copied coverage metadata from the last published tree.
 // Reading this report never runs callbacks or exposes model/editor values.
 return OB Copy($context.diagnostics)
End if
If ($operation="invalidate")
 If (($options=Null) || (Value type($options)#Is object))
  $result.error:="invalidChildOptions"
  return
 End if
 If ((Value type($options.subform)#Is text) || (Length($options.subform)=0))
  $result.error:="invalidChildOptions"
  return
 End if
 $result:=AXB_Invalidate($options.subform)
 return
End if
If ((Value type(Form)#Is object) | (Form=Null))
 $result.error:="noFormContext"
 return
End if
// The window registry owns root state. Compatibility properties are limited
// to plain, local objects; entities, class instances and shared objects keep
// their existing schema and locking rules.
$aliases:=(New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form))
If ($operation="stop")
 $context:=AXB_FormContext
 If ($context#Null)
  AXB_FormStop($context)
 Else
  // A registered child must not clear a root's compatibility alias when it
  // intentionally shares that root's data object.
  If ($aliases)
   $registry:=AXB_FormRoots[String(Current form window)]
   If (($registry=Null) || (New collection($registry.context.view).indexOf(Form.axbView)#0))
    OB REMOVE(Form; "axbView")
   End if
  End if
 End if
 $result:=New object("ok"; True)
 return
End if
If (($operation="register") & Not($aliases))
 $result.error:="unsupportedRegistrationData"
 return
End if
$result:=AXB_ViewCreate($options)
If (Not($result.ok=True))
 return
End if
$view:=$result.view
$result:=AXB_Host("info"; New object)
If (Not($result.ok=True))
 return
End if
If ($result.componentInfo.formOwnership#1)
 $result:=New object("ok"; False; "error"; "formOwnershipUnavailable")
 return
End if
If (Not($aliases) & ($result.componentInfo.rootDataOwnership#1))
 $result:=New object("ok"; False; "error"; "rootDataOwnershipUnavailable")
 return
End if
If (($result.componentInfo.sessionAllocation#1) | (Position("; sessions 2;"; $result.nativeStatus)=0))
 $result:=New object("ok"; False; "error"; "sessionLifecycleUnavailable")
 return
End if
If ($view.automatic)
 If (Position("; scrolling 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "scrollableControlsUnavailable")
  return
 End if
 If (Position("; adjustables 2;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "adjustableControlsUnavailable")
  return
 End if
 If (Position("; checkboxes 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "checkboxStatesUnavailable")
  return
 End if
 If (Position("; combos 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "comboControlsUnavailable")
  return
 End if
 If (Position("; input 2;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "nativeInputConfirmationUnavailable")
  return
 End if
 If (Position("; semantics 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "controlSemanticsUnavailable")
  return
 End if
 If (Position("; gridHeaders 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "gridHeadersUnavailable")
  return
 End if
 If (Position("; gridControls 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "gridControlsUnavailable")
  return
 End if
 If (Position("; cellFocus 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "cellFocusUnavailable")
  return
 End if
 If (Position("; rowStates 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "gridRowStatesUnavailable")
  return
 End if
 If (Position("; grids 1;"; $result.nativeStatus)=0)
  $result:=New object("ok"; False; "error"; "logicalGridsUnavailable")
  return
 End if
 If (($result.componentInfo.automaticControls#1) | ($result.componentInfo.nativeFocus#1) | (Position("; controls 1;"; $result.nativeStatus)=0) | (Position("; focus 1;"; $result.nativeStatus)=0))
  $result:=New object("ok"; False; "error"; "automaticControlsUnavailable")
  return
 End if
End if
$reply:=AXB_Form("stop"; New object)
If ($aliases)
 OB REMOVE(Form; "axbError")
 OB REMOVE(Form; "axbFailure")
 Form.axbView:=$view
End if
If ($operation="start")
 $view.root:=True
 $context:=New object("active"; True; "revision"; 0; "state"; ""; "label"; $options.label; "view"; $view)
 $context.nativeInsertion:=Position("; input 2;"; $result.nativeStatus)>0
 $context.aliases:=$aliases
 If ($aliases)
  Form.axbForm:=$context
 End if
 If (OB Is defined($options; "onError"))
  $context.onError:=$options.onError
 End if
 If (AXB_FormRoots=Null)
  AXB_FormRoots:=New object
 End if
 CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
 AXB_FormRoots[String(Current form window)]:=New object("context"; $context; "data"; Form; "formName"; Current form name; "origin"; New collection($x; $y); "bindings"; New object)
 $result:=AXB_Host("start"; New object("poll"; Formula(AXB_FormPoll)))
 If ($result.ok=True)
  $context.session:=$result.session
  $context.token:=$result.token
  OB REMOVE($result; "token")
 Else
  AXB_FormStop($context)
 End if
Else
 $result:=New object("ok"; True; "instance"; $view.instance)
End if
