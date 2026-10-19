// Stop the captured window lifetime even if another form shares its data.
#DECLARE($data : Object; $owner : Object)
var $current; $view : Object
If ($data=Null)
 return
End if
If ($owner#Null)
 AXB_FormStop($owner)
Else
 If (New collection($data).indexOf(Form)=0)
  $current:=AXB_FormContext
  If ($current#Null)
   AXB_FormStop($current)
  End if
 End if
End if
$view:=AXB_FormView($data)
If (($view#Null) && Not($view.root=True))
 AXB_FormViewSet($data; Null)
End if
