// Capture in the owning form. Hierarchy addresses differ from physical columns.
// Hidden backing rows remain unsupported until their native caption is known.
#DECLARE($name : Text; $binding : Object) -> $result : Object
var $count; $depth; $breaks; $row; $level; $column; $left; $top; $right; $bottom; $bodyTop; $bodyBottom; $bodyLeft; $bodyRight; $height; $lastBottom; $type; $savedOK; $columnCount; $controlType : Integer
var $hierarchical; $single; $positive; $previousPositive; $fresh : Boolean
var $pointer; $hitPointer; $expectedPointer; $control : Pointer
var $snapshot; $definition; $group; $candidate : Object
var $leaf; $frame; $values; $labels; $groups; $bounds; $hierarchyTypes : Collection
var $value : Variant
var $label; $signature; $format : Text
var $hitColumn; $hitRow : Integer
var $x; $y : Real
ARRAY POINTER($hierarchy; 0)
ARRAY POINTER($confirmed; 0)
ARRAY TEXT($parts; 0)
$savedOK:=OK
$result:=New object("ok"; False; "message"; "Grouped geometry is unavailable")
If ((Value type($binding.hierarchy)#Is collection) || (Value type($binding.keyPointer)#Is pointer) || (Value type($binding.selectionPointer)#Is pointer) || Not(OB Is defined($binding; "controlPointer")) || (New collection(Is pointer; Is null).indexOf(Value type($binding.controlPointer))<0))
 OK:=$savedOK
 return
End if
// A nil pointer stored in a 4D object becomes Null. Normalize it into a
// typed local pointer; the fresh native binding must still match below.
$control:=$binding.controlPointer
LISTBOX GET HIERARCHY(*; $name; $hierarchical; $hierarchy)
$count:=$binding.count
$depth:=Size of array($hierarchy)
If (Not($hierarchical) | ($depth<1) | ($depth>10) | (LISTBOX Get number of rows(*; $name)#$count))
 OK:=$savedOK
 return
End if
If ((Value type($binding.keys)#Is collection) || ($binding.keys.length#$count))
 OK:=$savedOK
 return
End if
If (Not(Is nil pointer($control)))
 $pointer:=$control
 If ((New collection(Boolean array; LongInt array).indexOf(Type($pointer->))<0) || (Size of array($pointer->)#$count))
  OK:=$savedOK
  return
 End if
 $controlType:=Type($pointer->)
End if
$pointer:=$binding.keyPointer
If (Is nil pointer($pointer) || (New collection(Text array; Integer array; LongInt array).indexOf(Type($pointer->))<0) || (Type($pointer->)#$binding.keyType) || (Size of array($pointer->)#$count))
 OK:=$savedOK
 return
End if
$pointer:=$binding.selectionPointer
If (Is nil pointer($pointer) || (Type($pointer->)#Boolean array) || (Size of array($pointer->)#$count))
 OK:=$savedOK
 return
End if
$height:=LISTBOX Get rows height(*; $name; lk pixels)
$columnCount:=LISTBOX Get number of columns(*; $name)
LISTBOX GET OBJECTS(*; $name; $parts)
If ((Size of array($parts)<3) || Not(OBJECT Get visible(*; $parts{1})) || ($height<=0))
 OK:=$savedOK
 return
End if
If (OBJECT Get font(*; $parts{1})="%password")
 $result.message:="Protected grouped captions cannot be published"
 OK:=$savedOK
 return
End if
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
$bounds:=New collection($left; $top; $right; $bottom)
$single:=$depth=1
$breaks:=Choose($single; 1; $depth-1)
If ($binding.hierarchy#Null)
 If (($binding.hierarchy.length#$depth) | ($binding.coordinateOffset#Choose($single; 0; $depth-1)))
  OK:=$savedOK
  return
 End if
 For ($level; 1; $depth)
  $expectedPointer:=$binding.hierarchy[$level-1]
  If ($hierarchy{$level}#$expectedPointer)
   OK:=$savedOK
   return
  End if
 End for
End if
$snapshot:=New object("keys"; $binding.keys; "flags"; New collection; "levels"; New collection; "leafFrames"; New collection)
$hierarchyTypes:=New collection
For ($level; 1; $depth)
 $pointer:=$hierarchy{$level}
 If (Is nil pointer($pointer) || (New collection(Text array; Integer array; LongInt array; Real array; Date array; Time array; Boolean array; Picture array).indexOf(Type($pointer->))<0) || (Size of array($pointer->)#$count))
  OK:=$savedOK
  return
 End if
 $hierarchyTypes.push(Type($pointer->))
End for
For ($row; 1; $count)
 $type:=0
 If (Not(Is nil pointer($control)))
  $pointer:=$control
  $type:=Num($pointer->{$row})
 End if
 If ((Int($type)#$type) | ($type<0) | ($type>7) | (New collection(1; 3; 5; 7).indexOf($type)>=0))
  $result.message:="Hidden grouped backing rows require a native caption authority"
  OK:=$savedOK
  return
 End if
 $snapshot.flags.push($type)
End for
For ($level; 1; $breaks)
 $pointer:=$hierarchy{$level}
 If (Is nil pointer($pointer))
  OK:=$savedOK
  return
 End if
 $type:=Type($pointer->)
 If ((New collection(Text array; Date array).indexOf($type)<0) || (Size of array($pointer->)#$count))
  $result.message:="Grouped captions currently require text or date arrays matching the row count"
  OK:=$savedOK
  return
 End if
 If (OBJECT Get font($pointer->)="%password")
  $result.message:="Protected grouped captions cannot be published"
  OK:=$savedOK
  return
 End if
 $format:=OBJECT Get format($pointer->)
 If (($type=Text array) & ($format#""))
  $result.message:="Formatted grouped captions require a native caption authority"
  OK:=$savedOK
  return
 End if
 $definition:=New object("values"; New collection; "labels"; New collection; "frames"; New collection)
 $definition.format:=$format
 For ($row; 1; $count)
  $value:=$pointer->{$row}
  Case of
   : ($type=Date array)
    $label:=String($value; System date short)
   : ($type=Time array)
    $label:=String($value; System time short)
   Else
    $label:=String($value)
  End case
  $definition.labels.push($label)
  $definition.values.push(AXB_OutlineToken($value; $type))
  If (Not($single))
   LISTBOX GET CELL COORDINATES(*; $name; $level; $row; $left; $top; $right; $bottom)
   If (($right<=$left) | ($bottom<$top) | (($bottom>$top) & (($bottom-$top)#$height)))
    OK:=$savedOK
    return
   End if
   $definition.frames.push(New collection($left; $top; $right-$left; $bottom-$top))
  End if
 End for
 $snapshot.levels.push($definition)
End for
For ($row; 1; $count)
 LISTBOX GET CELL COORDINATES(*; $name; Choose($single; 1; $depth); $row; $left; $top; $right; $bottom)
 $leaf:=New collection($left; $top; $right-$left; $bottom-$top)
 If (($leaf[2]<=0) | ($leaf[3]<0) | (($leaf[3]>0) & ($leaf[3]#$height)))
  OK:=$savedOK
  return
 End if
 // Every physical leaf column must agree on the same native vertical bounds.
 For ($column; 2; $columnCount)
  LISTBOX GET CELL COORDINATES(*; $name; $column+Choose($single; 0; $depth-1); $row; $left; $top; $right; $bottom)
  If (($right<$left) | ($bottom<$top))
   OK:=$savedOK
   return
  End if
  If (($right>$left) & (($top#$leaf[1]) | (($bottom-$top)#$leaf[3])))
   $result.message:="Grouped leaf columns disagree about native row bounds"
   OK:=$savedOK
   return
  End if
 End for
 $snapshot.leafFrames.push($leaf)
End for
If ($single & ($count>0))
 // 4D ignores individual height arrays in hierarchical mode. Derive break
 // intervals only when every fresh leaf bound agrees with the global height.
 If (LISTBOX Get rows height(*; $name; lk pixels)#$height)
  OK:=$savedOK
  return
 End if
 OBJECT GET COORDINATES(*; $name; $bodyLeft; $bodyTop; $bodyRight; $bodyBottom)
 If (LISTBOX Get property(*; $name; lk display header)=lk yes)
  $bodyTop:=$bodyTop+LISTBOX Get headers height(*; $name; lk pixels)
 End if
 If (LISTBOX Get property(*; $name; lk display footer)=lk yes)
  $bodyBottom:=$bodyBottom-LISTBOX Get footers height(*; $name; lk pixels)
 End if
 $bodyRight:=$bodyRight-New collection(0; LISTBOX Get property(*; $name; lk ver scrollbar width)).max()
 $bodyBottom:=$bodyBottom-New collection(0; LISTBOX Get property(*; $name; lk hor scrollbar height)).max()
 If ($bodyRight<=$bodyLeft)
  OK:=$savedOK
  return
 End if
 $groups:=New collection
 $lastBottom:=-1000000000
 $definition:=$snapshot.levels[0]
 For ($row; 0; $count-1)
  $leaf:=$snapshot.leafFrames[$row]
  $positive:=$leaf[3]>0
  If ($positive & ($leaf[3]#$height))
   OK:=$savedOK
   return
  End if
  $fresh:=($row=0) | ($leaf[1]#$lastBottom)
  If ($fresh)
   If (($row>0) & (($leaf[1]-$lastBottom)#$height))
    $result.message:="One-pointer hierarchy has an unexplained native break interval"
    OK:=$savedOK
    return
   End if
   $frame:=New collection($bodyLeft; $leaf[1]-$height; $bodyRight-$bodyLeft; $height)
   $group:=New object("frame"; $frame; "position"; $row+1; "positive"; $positive)
   $groups.push($group)
  Else
   If ($positive#$previousPositive)
    $result.message:="One-pointer hierarchy mixes disclosed and collapsed members"
    OK:=$savedOK
    return
   End if
  End if
  $definition.frames.push($frame)
  $lastBottom:=$leaf[1]+$leaf[3]
  $previousPositive:=$positive
 End for
 // A point inside a break can alias the first leaf. Corroborate both edges
 // and the preceding native row, while never querying outside the body.
 $x:=($bodyLeft+$bodyRight)/2
 For each ($candidate; $groups)
  $frame:=$candidate.frame
  If (($frame[1]>$bodyTop) & (($frame[1]+$height)<=$bodyBottom))
   For each ($y; New collection($frame[1]+1; $frame[1]+$height-1))
    LISTBOX GET CELL POSITION(*; $name; $x; $y; $hitColumn; $hitRow; $hitPointer)
    If (($hitColumn#1) | ($hitRow#$candidate.position) | ($hitPointer#$hierarchy{1}))
     $result.message:="One-pointer break boundary does not match its native hierarchy address"
     $result.boundary:=New object("point"; New collection($x; $y); "hit"; New collection($hitColumn; $hitRow); "expectedRow"; $candidate.position; "pointerMatches"; $hitPointer=$hierarchy{1}; "frame"; $frame)
     OK:=$savedOK
     return
    End if
   End for each
   $y:=$frame[1]-1
   LISTBOX GET CELL POSITION(*; $name; $x; $y; $hitColumn; $hitRow; $hitPointer)
   If (($hitRow=$candidate.position) & ($hitPointer=$hierarchy{1}))
    $result.message:="One-pointer break begins above the derived interval"
    OK:=$savedOK
    return
   End if
  End if
 End for each
End if
LISTBOX GET HIERARCHY(*; $name; $hierarchical; $confirmed)
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
If (Not($hierarchical) | (Size of array($confirmed)#$depth) | (LISTBOX Get number of rows(*; $name)#$count) | (LISTBOX Get number of columns(*; $name)#$columnCount) | (LISTBOX Get rows height(*; $name; lk pixels)#$height) | ($left#$bounds[0]) | ($top#$bounds[1]) | ($right#$bounds[2]) | ($bottom#$bounds[3]))
 $result.message:="Grouped binding or geometry changed during capture"
 OK:=$savedOK
 return
End if
For ($level; 1; $depth)
 If ($confirmed{$level}#$hierarchy{$level})
  $result.message:="Grouped hierarchy pointers changed during capture"
  OK:=$savedOK
  return
 End if
 $pointer:=$confirmed{$level}
 If (Is nil pointer($pointer) || (Type($pointer->)#$hierarchyTypes[$level-1]) || (Size of array($pointer->)#$count))
  OK:=$savedOK
  return
 End if
 If ($level<=$breaks)
  If ((OBJECT Get font($pointer->)="%password") | (Compare strings(OBJECT Get format($pointer->); $snapshot.levels[$level-1].format; sk char codes)#0))
   OK:=$savedOK
   return
  End if
  For ($row; 1; $count)
   If (Compare strings(AXB_OutlineToken($pointer->{$row}; Type($pointer->)); $snapshot.levels[$level-1].values[$row-1]; sk char codes)#0)
    $result.message:="Grouped hierarchy values changed during capture"
    OK:=$savedOK
    return
   End if
  End for
 End if
End for
If (Value type($binding.keyObjectName)=Is text)
 $expectedPointer:=$binding.keyPointer
 If (OBJECT Get pointer(Object named; $binding.keyObjectName)#$expectedPointer)
  OK:=$savedOK
  return
 End if
End if
$expectedPointer:=$binding.selectionPointer
If ((OBJECT Get pointer(Object named; $name)#$expectedPointer) || (Type($expectedPointer->)#Boolean array) || (Size of array($expectedPointer->)#$count))
 OK:=$savedOK
 return
End if
$expectedPointer:=$control
If (LISTBOX Get array(*; $name; lk control array)#$expectedPointer)
 OK:=$savedOK
 return
End if
If (Not(Is nil pointer($expectedPointer)))
 $pointer:=$expectedPointer
 If ((Type($pointer->)#$controlType) || (Size of array($pointer->)#$count))
  OK:=$savedOK
  return
 End if
 For ($row; 1; $count)
  If (Num($pointer->{$row})#$snapshot.flags[$row-1])
   $result.message:="Grouped control flags changed during capture"
   OK:=$savedOK
   return
  End if
 End for
End if
If (Value type($binding.keyPointer)=Is pointer)
 $pointer:=$binding.keyPointer
 If (Is nil pointer($pointer) || (Type($pointer->)#$binding.keyType) || (Size of array($pointer->)#$count))
  OK:=$savedOK
  return
 End if
 For ($row; 1; $count)
  $value:=$pointer->{$row}
  $label:=Choose(Type($pointer->)=Text array; String($value); String($value; "&xml"))
  If (Compare strings($label; $binding.keys[$row-1]; sk char codes)#0)
   OK:=$savedOK
   return
  End if
 End for
End if
$result:=New object("ok"; True; "snapshot"; $snapshot; "hierarchy"; New collection; "single"; $single; "coordinateOffset"; Choose($single; 0; $depth-1))
For ($level; 1; $depth)
 $result.hierarchy.push($hierarchy{$level})
End for
OK:=$savedOK
