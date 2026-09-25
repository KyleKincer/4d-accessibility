// Build provider configuration without attaching to application data.
#DECLARE($options : Object) -> $result : Object
var $view; $metadata : Object
var $key; $name : Text
$result:=New object("ok"; False; "error"; "invalidOptions")
If (($options=Null) | (Value type($options)#Is object))
 return
End if
For each ($key; New collection("describe"; "apply"; "onError"))
 If (OB Is defined($options; $key))
  $result.error:="invalid"+Uppercase(Substring($key; 1; 1))+Substring($key; 2)
  If (($options[$key]=Null) | (Value type($options[$key])#Is object))
   return
  End if
  If (Not(OB Instance of($options[$key]; 4D.Function)))
   return
  End if
 End if
End for each
$result.error:="invalidLabel"
If ((Value type($options.label)#Is text) | ($options.label=""))
 return
End if
If (Length($options.label)>512)
 return
End if
For each ($key; New collection("controls"; "children"; "grids"))
 If (OB Is defined($options; $key))
  If (($options[$key]=Null) | (Value type($options[$key])#Is object))
   $result.error:="invalid"+Uppercase(Substring($key; 1; 1))+Substring($key; 2)
   return
  End if
 End if
End for each
If ($options.controls#Null)
 For each ($name; $options.controls)
  If ((Value type($options.controls[$name])#Is object) || ($options.controls[$name]=Null))
   return New object("ok"; False; "error"; "invalidControlMetadata")
  End if
  $metadata:=$options.controls[$name]
  If (OB Is defined($metadata; "layer"))
   If (New collection(Is real; Is integer; Is longint).indexOf(Value type($metadata.layer))<0)
    return New object("ok"; False; "error"; "invalidControlLayer")
   End if
   If (($metadata.layer#Int($metadata.layer)) | (Abs($metadata.layer)>32767))
    return New object("ok"; False; "error"; "invalidControlLayer")
   End if
  End if
  If (OB Is defined($metadata; "adjust"))
   If (($metadata.adjust=Null) || (Value type($metadata.adjust)#Is object))
    return New object("ok"; False; "error"; "invalidControlAdjustment")
   End if
   If (Not(OB Instance of($metadata.adjust; 4D.Function)))
    return New object("ok"; False; "error"; "invalidControlAdjustment")
   End if
  End if
 End for each
End if
If (OB Is defined($options; "grids"))
 If (Not(AXB_GridOptions($options.grids)))
  $result.error:="invalidGrids"
  return
 End if
End if
$view:=New object("instance"; Generate UUID; "scope"; ""; "label"; $options.label; "options"; $options; "automatic"; Not(OB Is defined($options; "describe")); "children"; New object)
$view.bindingKey:=$view.instance
If (Not($view.automatic))
 $view.describe:=$options.describe
End if
If (OB Is defined($options; "apply"))
 $view.apply:=$options.apply
End if
$result:=New object("ok"; True; "view"; $view)
