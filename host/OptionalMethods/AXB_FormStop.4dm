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
If (Not($context.aliases=True))
 return
End if
If ($data.axb.token.session=$context.session)
 OB REMOVE($data; "axb")
End if
If (New collection($data.axbForm).indexOf($context)=0)
 OB REMOVE($data; "axbForm")
End if
If (New collection($data.axbView).indexOf($context.view)=0)
 OB REMOVE($data; "axbView")
End if
