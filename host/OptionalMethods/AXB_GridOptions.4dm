// Validate application configuration before creating a session or invoking a
// provider. Formulas are evaluated later, in the configured form instance.
#DECLARE($grids : Object) -> $valid : Boolean
var $name; $property; $column : Text
var $options; $metadata : Object
$valid:=False
If (($grids=Null) | (Value type($grids)#Is object))
 return
End if
For each ($name; $grids)
 If (Value type($grids[$name])#Is object)
  return
 End if
 $options:=$grids[$name]
 If (($name="") | ($options=Null) | (Value type($options)#Is object))
  return
 End if
 If (OB Is defined($options; "label"))
  If ((Value type($options.label)#Is text) || ($options.label="") || (Length($options.label)>512))
   return
  End if
 End if
 If (New collection("array"; "areaList"; "collection"; "entity").indexOf($options.kind)<0)
  return
 End if
 If ($options.kind="array")
  If ((Value type($options.keyColumn)#Is text) || ($options.keyColumn=""))
   return
  End if
 Else
  If ($options.kind="areaList")
   If (Value type($options.keys)#Is pointer)
    return
   End if
   If (OB Is defined($options; "keyColumn"))
    If ((Value type($options.keyColumn)#Is real) || ($options.keyColumn<1) || (Int($options.keyColumn)#$options.keyColumn))
     return
    End if
   End if
  Else
   If (($options.kind="collection") | OB Is defined($options; "keyProperty"))
    If ((Value type($options.keyProperty)#Is text) || ($options.keyProperty=""))
     return
    End if
   End if
  End if
 End if
 If (OB Is defined($options; "columns"))
  If (($options.columns=Null) | (Value type($options.columns)#Is object))
   return
  End if
  For each ($column; $options.columns)
   If (($column="") | (Length($column)>255))
    return
   End if
   If ($options.kind="areaList")
    If ((Num($column)<1) | (String(Int(Num($column)))#$column))
     return
    End if
   End if
   $metadata:=$options.columns[$column]
   If (($metadata=Null) | (Value type($metadata)#Is object))
    return
   End if
   If (OB Is defined($metadata; "label"))
    If ((Value type($metadata.label)#Is text) || ($metadata.label="") || (Length($metadata.label)>512))
     return
    End if
   End if
   If (OB Is defined($metadata; "decorative"))
    If (Value type($metadata.decorative)#Is Boolean)
     return
    End if
   End if
   If (OB Is defined($metadata; "value"))
    If (($metadata.decorative=True) | ($metadata.value=Null) || (Value type($metadata.value)#Is object) || Not(OB Instance of($metadata.value; 4D.Function)))
     return
    End if
   End if
  End for each
 End if
 If (OB Is defined($options; "meta") & (New collection("collection"; "entity").indexOf($options.kind)<0))
  return
 End if
 For each ($property; New collection("ready"; "onSelection"; "selection"; "meta"))
  If (OB Is defined($options; $property))
   If (($property="ready") & (Value type($options[$property])=Is Boolean))
    continue
   End if
   If (($options[$property]=Null) || (Value type($options[$property])#Is object) || Not(OB Instance of($options[$property]; 4D.Function)))
    return
   End if
  End if
 End for each
End for each
$valid:=True
