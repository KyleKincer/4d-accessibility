// The view registered in this process for a form's data object, or Null. The registry holds it,
// not the data: the application may copy, serialize or store its form's data.
#DECLARE($data : Object) -> $view : Object
var $entry : Object
$view:=Null
If ((AXB_FormViews=Null) | ($data=Null))
 return
End if
For each ($entry; AXB_FormViews)
 If (New collection($entry.data).indexOf($data)=0)
  $view:=$entry.view
  break
 End if
End for each
