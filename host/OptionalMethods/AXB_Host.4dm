// Optional host entry point. All component method names are fixed literals.
// Requests come from application adapters, never directly from an AX client.
#DECLARE($operation : Text; $request : Object) -> $result : Object
var $info : Object
var $native; $component : Boolean
ARRAY LONGINT($numbers; 0)
ARRAY TEXT($names; 0)
ARRAY TEXT($components; 0)
$result:=New object("ok"; False; "error"; "unsupportedOperation")
If (New collection("info"; "start"; "stop"; "node"; "exchange"; "focus").indexOf($operation)<0)
 return
End if
If ((Value type($request)#Is object) | ($request=Null))
 $result.error:="invalidRequest"
 return
End if
PLUGIN LIST($numbers; $names)
COMPONENT LIST($components)
$native:=Find in array($numbers; 31071)>0
$component:=Find in array($components; "AccessibilityBridge")>0
If (Not($native & $component))
 $result:=New object("ok"; False; "error"; "dependencyUnavailable"; "native"; $native; "component"; $component)
 return
End if
// Older components expose ComponentInfo but not the optional host API.
// Check that contract before attempting to call its new entry point.
EXECUTE METHOD("AXB_ComponentInfo"; $info)
If ($info=Null)
 $result.error:="incompatibleComponent"
 return
End if
If (($info.protocol#1) | ($info.hostAPI#1) | Not($info.compiled=True))
 $result.error:="incompatibleComponent"
 return
End if
EXECUTE METHOD("AXB_Dispatch"; $result; $operation; $request)
If ($operation="info")
 $result.componentInfo:=$info
End if
