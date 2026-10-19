// Register a view for a form's data object in this window, replacing any other; Null removes it.
// With no data, remove every view registered for the window, as when its root form stops.
#DECLARE($data : Object; $view : Object; $window : Integer)
var $index : Integer
If (AXB_FormViews=Null)
 AXB_FormViews:=New collection
End if
For ($index; AXB_FormViews.length-1; 0; -1)
 If (Choose($data=Null; AXB_FormViews[$index].window=$window; New collection(AXB_FormViews[$index].data).indexOf($data)=0))
  AXB_FormViews.remove($index)
 End if
End for
If (($data#Null) & ($view#Null))
 AXB_FormViews.push(New object("data"; $data; "view"; $view; "window"; Current form window))
End if
