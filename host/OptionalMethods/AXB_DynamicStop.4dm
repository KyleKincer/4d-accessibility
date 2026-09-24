// Stop the captured window lifetime even if another form shares its data.
#DECLARE($data : Object; $owner : Object)
var $current : Object
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
If ((New collection(4D.Object).indexOf(OB Class($data))=0) && Not(OB Is shared($data)) && ($data.axbView#Null) && Not($data.axbView.root=True))
 OB REMOVE($data; "axbView")
End if
