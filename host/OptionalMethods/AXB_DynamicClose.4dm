// End a generated instance in its own form context. Safe to call twice.
// Application cleanup remains in its own shared close method.
var $pointer : Pointer
var $context : Object
$pointer:=OBJECT Get pointer(Object named; "__AXB_DynamicContext")
If (Not(Is nil pointer($pointer)))
 $context:=$pointer->
End if
If ($context#Null)
 AXB_DynamicStop($context.data; $context.provider)
 $context.closed:=True
 If ($context.data.axbDynamic#Null)
  $context.data.axbDynamic.closed:=True
 End if
Else
 If ((Form=Null) || (New collection(4D.Object).indexOf(OB Class(Form))#0) || OB Is shared(Form))
  return
 End if
 AXB_DynamicStop(Form; Null)
 If (Form.axbDynamic#Null)
  // A pending preparation can share data with an unregistered old child.
  // Closing that old child must not cancel the new preparation.
  If (Form.axbDynamic.options=Null)
   Form.axbDynamic.closed:=True
  End if
 End if
End if
