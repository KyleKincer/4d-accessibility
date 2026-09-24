// Fixed bridge operations for optional hosts. No method name or source is executed
// from a request. The start formula is registered only by trusted application code.
#DECLARE($operation : Text; $request : Object) -> $result : Object
var $status : Text
var $token : Object
ARRAY TEXT($objects; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; False; "error"; "unsupportedOperation")
If (New collection("info"; "start"; "stop"; "node"; "exchange"; "focus").indexOf($operation)<0)
 return
End if
If ((Value type($request)#Is object) | ($request=Null))
 $result.error:="invalidRequest"
 return
End if
$status:=AXB Status
If ((Position("Accessibility Bridge "; $status)#1) | (Position("; protocol 1;"; $status)=0) | (Position("; sessions 2;"; $status)=0))
 $result.error:="incompatibleNativePlugin"
 return
End if
If ($operation="info")
 $result:=New object("ok"; True; "hostAPI"; 1; "nativeStatus"; $status)
 return
End if
If (Current form window=0)
 $result.error:="noFormContext"
 return
End if
If ($operation="focus")
 If (Position("; focus 1;"; $status)>0)
  $result:=JSON Parse(AXB Native focus(Current form window))
 End if
 return
End if
If ((Value type(Form)#Is object) | (Form=Null))
 $result.error:="noFormContext"
 return
End if
Case of
 : ($operation="start")
  If (Value type($request.poll)#Is object)
   $result.error:="invalidPoll"
   return
  End if
  If (Not(OB Instance of($request.poll; 4D.Function)))
   $result.error:="invalidPoll"
   return
  End if
  $token:=AXB_Start($request.poll)
  If (Not($token.active=True))
   $result:=New object("ok"; False; "error"; $token.error)
   return
  End if
  $result:=New object("ok"; True; "session"; $token.session; "token"; $token)
 : ($operation="stop")
  If (OB Is defined($request; "session"))
   If ($request.session#AXB_CoreWindows[String(Current form window)].token.session)
    $result.error:="inactiveSession"
    return
   End if
  End if
  AXB_Stop
  $result:=New object("ok"; True)
 : ($operation="node")
  If ((Value type($request.objectName)#Is text) | (Value type($request.id)#Is text) | (Value type($request.role)#Is text) | (Value type($request.label)#Is text) | (Value type($request.enabled)#Is Boolean))
   $result.error:="invalidNode"
   return
  End if
  FORM GET OBJECTS($objects; $variables; $pages; Form current page+Form inherited)
  If (Find in array($objects; $request.objectName)<1)
   $result.error:="unknownControl"
   return
  End if
  $result:=New object("ok"; True; "node"; AXB_ControlNode($request.objectName; $request.id; $request.role; $request.label; $request.value; $request.enabled))
 : ($operation="exchange")
  $result.error:="inactiveSession"
  If (AXB_CoreWindows[String(Current form window)]=Null)
   return
  End if
  $token:=AXB_CoreWindows[String(Current form window)].token
  If (Not($token.active) | ($token.session#$request.session) | ($token.window#Current form window) | ($token.owner#Current process))
   return
  End if
  If ((Value type($request.envelope)#Is object) | ($request.envelope=Null))
   $result.error:="invalidEnvelope"
   return
  End if
  $result:=JSON Parse(AXB Exchange(Current form window; $token.session; JSON Stringify($request.envelope)))
End case
