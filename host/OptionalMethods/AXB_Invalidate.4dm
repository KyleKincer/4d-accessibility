// Call before replacing a child, including same-name/same-data replacement.
// Root-owned state lets this work inside an automatically discovered parent.
#DECLARE($subform : Text) -> $result : Object
var $context; $view; $child; $registry : Object
var $pending : Collection
var $key : Text
var $x; $y; $count : Integer
$result:=New object("ok"; False; "error"; "unregisteredWindow")
If (AXB_FormRoots=Null)
 return
End if
$registry:=AXB_FormRoots[String(Current form window)]
If ($registry=Null)
 return
End if
$context:=$registry.context
OB REMOVE($registry; "observedFocus")
If (($context=Null) || Not($context.active))
 return
End if
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$pending:=New collection($context.view)
While ($pending.length>0)
 $view:=$pending.pop()
 If ((New collection($registry.bindings[$view.bindingKey]).indexOf(Form)=0) & ($view.formName=Current form name))
  If (($view.origin#Null) && ($view.origin[0]=$x) && ($view.origin[1]=$y))
   If ($view.children[$subform]#Null)
    OB REMOVE($view.children; $subform)
   End if
   $count:=$count+1
  End if
 End if
 For each ($key; $view.children)
  $child:=$view.children[$key]
  $pending.push($child)
 End for each
End while
If ($count=0)
 // Layout may have changed since discovery. Retire the whole tree rather
 // than allow an old request to reach a replacement with identical values.
 $context.view.instance:=Generate UUID
 $context.view.children:=New object
End if
$result:=New object("ok"; True; "matchedParents"; $count)
