// The form owns this binding independently of its replaceable application data.
var $context; $reply : Object
var $pointer : Pointer
var $metadata : Text
var $forward; $sameData : Boolean
If (Form event code=On Load)
 If ((Form#Null) && (New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
  $context:=Form.axbDynamic
 End if
 If ($context#Null)
  If ($context.options#Null)
   $context.data:=Form
   Form.axbDynamic:=New object("closed"; False)
   $pointer:=OBJECT Get pointer(Object named; "__AXB_DynamicContext")
   If (Not(Is nil pointer($pointer)))
    $pointer->:=$context
   Else
    $context:=Null
   End if
  Else
   $context:=Null
  End if
 End if
Else
 $pointer:=OBJECT Get pointer(Object named; "__AXB_DynamicContext")
 If (Not(Is nil pointer($pointer)))
  $context:=$pointer->
 End if
End if
If ($context=Null)
 // A caller supplied different data than it prepared. Keep the original
 // application method usable, but do not create an unowned bridge session.
 If ((Form#Null) && (New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
  Form.axbError:="missingDynamicContext"
 End if
 $metadata:=OBJECT Get placeholder(*; "__AXB_DynamicContext")
 If ($metadata="")
  return
 End if
 $context:=JSON Parse($metadata)
 $forward:=$context.method#""
 If (Form event code=On Load)
  $forward:=$forward & $context.onLoad
 End if
 If (Form event code=On Unload)
  $forward:=$forward & $context.onUnload
 End if
 If ($forward)
  EXECUTE METHOD($context.method)
 End if
 return
End if
$sameData:=New collection($context.data).indexOf(Form)=0
If (Not($sameData))
 // Detach the old registration, but keep forwarding the original form method
 // in the current application context. Rebinding is an explicit new lifetime.
 AXB_DynamicStop($context.data; $context.provider)
 If ((Form#Null) && (New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
  Form.axbError:="dynamicDataReplaced"
 End if
End if
$forward:=$context.method#""
Case of
 : (Form event code=On Load)
  $forward:=$forward & $context.onLoad
 : (Form event code=On Unload)
  AXB_DynamicClose
  $forward:=$forward & $context.onUnload
End case
If ($forward)
 EXECUTE METHOD($context.method)
End if
// Application initialization can itself replace a bound subform data object.
$sameData:=New collection($context.data).indexOf(Form)=0
If ((Form event code=On Load) & Not($sameData))
 AXB_DynamicStop($context.data; $context.provider)
 If ((Form#Null) && (New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
  Form.axbError:="dynamicDataReplaced"
 End if
End if
If ((Form event code=On Load) & $sameData & Not($context.closed))
 $reply:=AXB_Form($context.operation; $context.options)
 If (($reply.ok=True) & ($context.operation="start"))
  $context.provider:=AXB_FormContext
 End if
 $context.data.axbDynamic.startResult:=$reply
 If (Not($reply.ok=True))
  If ((Form#Null) && (New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form)))
   Form.axbError:=$reply.error
  End if
  AXB_DynamicFailure($reply; $context.options; "start")
 End if
End if
