// Merge what the current form's definition stores ("axb") into $options: the form's
// own options where $options does not set them, its objects' metadata under
// $options.controls and its grids under $options.grids. Options from the
// application win key by key; $options itself is never changed.
#DECLARE($options : Object) -> $result : Object
var $stored; $controls; $grids; $grid; $merged; $columns : Object
var $explicit : Variant
var $name; $key; $column : Text
$result:=$options
If (($options=Null) || (Value type($options)#Is object))
 return
End if
For each ($key; New collection("controls"; "grids"))
 If (OB Is defined($options; $key) && ((Value type($options[$key])#Is object) || ($options[$key]=Null)))
  // Invalid application options are reported as they are.
  return
 End if
End for each
// A shallow copy: formulas, pointers and data in the options stay shared.
$result:=New object
For each ($name; $options)
 $result[$name]:=$options[$name]
End for each
$stored:=AXB_FormStored("options")
If ($stored#Null)
 For each ($key; $stored)
  If (Not(OB Is defined($result; $key)))
   $result[$key]:=$stored[$key]
  End if
 End for each
End if
$stored:=AXB_FormStored("controls")
If ($stored#Null)
 $controls:=New object
 For each ($name; $stored)
  $controls[$name]:=$stored[$name]
 End for each
 If ($options.controls#Null)
  For each ($name; $options.controls)
   $explicit:=$options.controls[$name]
   If (($controls[$name]=Null) || (Value type($explicit)#Is object) || ($explicit=Null))
    $controls[$name]:=$explicit
   Else
    $merged:=New object
    For each ($key; $controls[$name])
     $merged[$key]:=$controls[$name][$key]
    End for each
    For each ($key; $explicit)
     $merged[$key]:=$explicit[$key]
    End for each
    $controls[$name]:=$merged
   End if
  End for each
 End if
 $result.controls:=$controls
End if
$stored:=AXB_FormStored("grids")
If ($stored#Null)
 $grids:=New object
 If ($options.grids#Null)
  For each ($name; $options.grids)
   $grids[$name]:=$options.grids[$name]
  End for each
 End if
 For each ($name; $stored)
  $explicit:=$grids[$name]
  If ($explicit=Null)
   // A stored grid stands alone only when it is complete without formulas or
   // pointers: an AreaList grid needs its keys, so it only completes one the
   // application configures.
   If ((OB Is defined($stored[$name]; "kind")) && ($stored[$name].kind#"areaList"))
    $grids[$name]:=$stored[$name]
   End if
  Else
   If ((Value type($explicit)=Is object) && ($explicit#Null))
    $grid:=New object
    For each ($key; $stored[$name])
     $grid[$key]:=$stored[$name][$key]
    End for each
    For each ($key; $explicit)
     $grid[$key]:=$explicit[$key]
    End for each
    // Columns merge one by one, key by key.
    If ((Value type($stored[$name].columns)=Is object) && (Value type($explicit.columns)=Is object) && ($explicit.columns#Null))
     $columns:=New object
     For each ($column; $stored[$name].columns)
      $columns[$column]:=$stored[$name].columns[$column]
     End for each
     For each ($column; $explicit.columns)
      If ((Value type($columns[$column])=Is object) && (Value type($explicit.columns[$column])=Is object) && ($explicit.columns[$column]#Null))
       $merged:=New object
       For each ($key; $columns[$column])
        $merged[$key]:=$columns[$column][$key]
       End for each
       For each ($key; $explicit.columns[$column])
        $merged[$key]:=$explicit.columns[$column][$key]
       End for each
       $columns[$column]:=$merged
      Else
       $columns[$column]:=$explicit.columns[$column]
      End if
     End for each
     $grid.columns:=$columns
    End if
    $grids[$name]:=$grid
   End if
  End if
 End for each
 If (OB Is defined($result; "grids") | (OB Keys($grids).length>0))
  $result.grids:=$grids
 End if
End if
