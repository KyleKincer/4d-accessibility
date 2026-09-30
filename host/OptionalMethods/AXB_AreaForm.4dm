// Add area-owned lifecycle to generated JSON without wrapping its method or
// changing events, application data, or the caller's original definition.
#DECLARE($form : Object; $configuration : Text) -> $result : Object
var $prepared; $page; $object : Object
var $name; $areaName : Text
var $number; $found : Integer
$result:=New object("ok"; False; "error"; "invalidAreaForm"; "form"; $form)
$areaName:="__AXB_Bridge"
If ($configuration#"")
 If (Not(Match regex("^[A-Za-z][A-Za-z0-9_-]{0,63}$"; $configuration)))
  return New object("ok"; False; "error"; "invalidAreaConfiguration"; "form"; $form)
 End if
 $areaName:=$areaName+"."+$configuration
End if
If (($form#Null) && ($form.destination#Null) && (New collection(""; "detailScreen").indexOf($form.destination)<0))
 return New object("ok"; False; "error"; "unsupportedAreaDestination"; "form"; $form)
End if
// Named inheritance must be installed once in its shared base by the source
// installer. This helper cannot safely inspect an external base definition.
If (($form#Null) && ($form.inheritedForm#Null) && (New collection(""; " ").indexOf($form.inheritedForm)<0))
 return New object("ok"; False; "error"; "inheritedAreaForm"; "form"; $form)
End if
If (($form=Null) || ($form.pages=Null) || (Value type($form.pages)#Is collection) || ($form.pages.length=0))
 return
End if
For ($number; 0; $form.pages.length-1)
 $page:=$form.pages[$number]
 If ($page#Null)
  If ((Value type($page)#Is object) || (($page.objects#Null) && (Value type($page.objects)#Is object)))
   return
  End if
  If ($page.objects#Null)
   For each ($name; $page.objects)
    $object:=$page.objects[$name]
    If (($object=Null) || (Value type($object)#Is object))
     return
    End if
    If ((($name="__AXB_Bridge") | (Position("__AXB_Bridge."; $name)=1)) | ($object.pluginAreaKind="%AXB Area"))
     // Accept the same installer-owned area on page zero, once only.
     If (($number#0) | ($name#$areaName) | ($object.pluginAreaKind#"%AXB Area") | ($object.type#"plugin") | ($object.dataSource#"") | ($object.left#0) | ($object.top#0) | ($object.width#1) | ($object.height#1) | ($object.enterable#False) | ($object.focusable#False) | ($object.printable#False) | (OB Keys($object).length#10))
      return New object("ok"; False; "error"; "conflictingLifecycleArea"; "form"; $form)
     End if
     $found:=$found+1
    End if
   End for each
  End if
 End if
End for
If ($found>1)
 return New object("ok"; False; "error"; "conflictingLifecycleArea"; "form"; $form)
End if
$prepared:=OB Copy($form)
If ($prepared.pages[0]=Null)
 $prepared.pages[0]:=New object
End if
If ($prepared.pages[0].objects=Null)
 $prepared.pages[0].objects:=New object
End if
If ($found=0)
 $prepared.pages[0].objects[$areaName]:=New object("type"; "plugin"; "pluginAreaKind"; "%AXB Area"; "dataSource"; ""; "left"; 0; "top"; 0; "width"; 1; "height"; 1; "enterable"; False; "focusable"; False; "printable"; False)
End if
$result:=New object("ok"; True; "form"; $prepared)
