// Register a view for a form's data object in this process, replacing any other; Null removes it.
// Views registered in windows this process no longer has are dropped at the same time.
#DECLARE($data : Object; $view : Object)
var $index : Integer
If (AXB_FormViews=Null)
 AXB_FormViews:=New collection
End if
For ($index; AXB_FormViews.length-1; 0; -1)
 If ((New collection(AXB_FormViews[$index].data).indexOf($data)=0) | (Window process(AXB_FormViews[$index].window)#Current process))
  AXB_FormViews.remove($index)
 End if
End for
If (($data#Null) & ($view#Null))
 AXB_FormViews.push(New object("data"; $data; "view"; $view; "window"; Current form window))
End if
