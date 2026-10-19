// Retire only this captured window lifetime, including after data rebinding.
#DECLARE($context : Object)
var $registry; $data; $reply : Object
var $window : Integer
If ($context=Null)
 return
End if
$context.active:=False
$window:=$context.window
If ($window=0)
 $window:=Current form window
End if
$registry:=AXB_FormRoots[String($window)]
If (($registry=Null) || (New collection($registry.context).indexOf($context)#0))
 return
End if
$data:=$registry.data
$reply:=AXB_Host("stop"; New object("window"; $window; "session"; $context.session))
OB REMOVE(AXB_FormRoots; String($window))
// A child registered in this window keeps its view: a restarted root describes it again.
If (New collection(AXB_FormView($data)).indexOf($context.view)=0)
 AXB_FormViewSet($data; Null)
End if
If (Not($context.aliases=True))
 return
End if
// Earlier versions kept these aliases on the form's data.
If ($data.axb.token.session=$context.session)
 OB REMOVE($data; "axb")
End if
If (New collection($data.axbForm).indexOf($context)=0)
 OB REMOVE($data; "axbForm")
End if
If (New collection($data.axbView).indexOf($context.view)=0)
 OB REMOVE($data; "axbView")
End if
