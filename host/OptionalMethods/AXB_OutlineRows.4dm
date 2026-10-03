// Infer only disclosed rows from captured public geometry. Pixel coordinates
// group one snapshot; exact membership and parent identity own persistent keys.
#DECLARE($snapshot : Object; $previous : Object) -> $result : Object
var $nodes; $node; $geometry; $known; $registry; $entry; $outline; $positions; $definition : Object
var $ordered; $members; $rows; $layout; $frames; $leafFrame : Collection
var $row; $level; $count; $depth; $lastBottom; $eligible : Integer
var $key; $parent; $token; $geometryKey; $signature; $digest; $identity; $value; $label; $kind : Text
var $positive; $ancestor; $fresh; $childDisclosed : Boolean
$result:=New object("ok"; False; "message"; "Grouped geometry is unavailable")
If (($snapshot=Null) | ($snapshot.keys=Null) | ($snapshot.levels=Null) | ($snapshot.leafFrames=Null) | ($snapshot.flags=Null))
 return
End if
$count:=$snapshot.keys.length
$depth:=$snapshot.levels.length
If (($depth<1) | ($depth>9) | ($snapshot.leafFrames.length#$count) | ($snapshot.flags.length#$count))
 return
End if
For each ($definition; $snapshot.levels)
 If (($definition.frames.length#$count) | ($definition.values.length#$count) | ($definition.labels.length#$count))
  return
 End if
End for each
$nodes:=New object
$geometry:=New object
$known:=New object
$ordered:=New collection
$eligible:=0
For ($row; 0; $count-1)
 $key:=$snapshot.keys[$row]
 If ((Value type($key)#Is text) || ($key="") || (Length($key)>254) || OB Is defined($known; $key))
  $result.message:="Grouped rows require unique nonempty stable keys"
  return
 End if
 $known[$key]:=True
 If (($snapshot.flags[$row]<0) | ($snapshot.flags[$row]>7))
  return
 End if
 If (New collection(1; 3; 5; 7).indexOf($snapshot.flags[$row])>=0)
  continue
 End if
 $eligible:=$eligible+1
 $parent:=""
 $ancestor:=True
 For ($level; 0; $depth-1)
  $definition:=$snapshot.levels[$level]
  $frames:=$definition.frames[$row]
  If (($frames.length#4) || ($frames[2]<=0) || ($frames[3]<0))
   return
  End if
  $positive:=($frames[2]>0) & ($frames[3]>0)
  If ($positive & Not($ancestor))
   $result.message:="Disclosed child has no disclosed parent"
   return
  End if
  If (Not($positive))
   If ($level=0)
    $result.message:="Eligible backing row has no disclosed root"
    return
   End if
   $ancestor:=False
   continue
  End if
  $value:=$definition.values[$row]
  $label:=$definition.labels[$row]
  If ((Value type($value)#Is text) | (Value type($label)#Is text) | (Length($label)>512))
   return
  End if
  If ($level<($depth-1))
   $childDisclosed:=$snapshot.levels[$level+1].frames[$row][3]>0
  Else
   $childDisclosed:=$snapshot.leafFrames[$row][3]>0
  End if
  $geometryKey:=JSON Stringify(New collection($parent; $level; $frames))
  If (Not(OB Is defined($geometry; $geometryKey)))
   // Short transient tokens prevent repeated JSON escaping at deep levels.
   $token:="t:"+String($ordered.length)
   $geometry[$geometryKey]:=$token
   $node:=New object("parent"; $parent; "level"; $level; "kind"; "group"; "frame"; $frames; "value"; $value; "label"; $label; "expanded"; False; "childDisclosed"; $childDisclosed; "members"; New collection; "position"; $row+1; "lastEligible"; $eligible)
   $nodes[$token]:=$node
   $ordered.push($token)
   If ($parent#"")
    $nodes[$parent].expanded:=True
   End if
  Else
   $token:=$geometry[$geometryKey]
   $node:=$nodes[$token]
   If (($node.lastEligible#($eligible-1)) | (Compare strings($node.value; $value; sk char codes)#0) | (Compare strings($node.label; $label; sk char codes)#0))
    $result.message:="Noncontiguous or ambiguously labelled native group"
    return
   End if
   $node.lastEligible:=$eligible
   If ($node.childDisclosed#$childDisclosed)
    $result.message:="Native group has inconsistent immediate disclosure"
    return
   End if
  End if
  $node.members.push($key)
  $parent:=$token
 End for
 $leafFrame:=$snapshot.leafFrames[$row]
 If (($leafFrame.length#4) || ($leafFrame[2]<=0) || ($leafFrame[3]<0))
  return
 End if
 If (($leafFrame[2]>0) & ($leafFrame[3]>0))
  If (Not($ancestor))
   $result.message:="Disclosed leaf has no disclosed parent"
   return
  End if
  $nodes[$parent].expanded:=True
  $token:="l:"+$key
  $nodes[$token]:=New object("kind"; "leaf"; "parent"; $parent; "level"; $depth; "frame"; $leafFrame; "position"; $row+1)
  $ordered.push($token)
 End if
End for
$registry:=New object
$outline:=New object
$positions:=New object
$rows:=New collection
$layout:=New collection
$lastBottom:=-1000000000
For each ($token; $ordered)
 $node:=$nodes[$token]
 $parent:=""
 If ($node.parent#"")
  $parent:=$nodes[$node.parent].id
  If ($parent="")
   return
  End if
 End if
 $kind:=$node.kind
 If ($kind="group")
  $members:=$node.members.orderByMethod(Formula(Compare strings($1.value; $1.value2; sk char codes)<0))
  $signature:=JSON Stringify(New collection($parent; $node.level; $node.value; $members))
  $digest:=Generate digest($signature; SHA256 digest)
  $entry:=Null
  If (($previous#Null) && ($previous.registry#Null))
   $entry:=$previous.registry[$digest]
  End if
  $fresh:=($entry=Null)
  If (Not($fresh))
   $fresh:=Compare strings($entry.signature; $signature; sk char codes)#0
  End if
  If ($fresh)
   $identity:="g:"+Generate UUID
  Else
   $identity:=$entry.id
  End if
  $registry[$digest]:=New object("id"; $identity; "signature"; $signature)
  $definition:=New object("parent"; $parent; "level"; $node.level; "kind"; "group"; "label"; $node.label; "expanded"; $node.expanded; "frame"; $node.frame)
 Else
  $identity:=$token
  $definition:=New object("parent"; $parent; "level"; $node.level; "kind"; "leaf")
 End if
 If (($node.frame[1]<$lastBottom) | OB Is defined($outline; $identity))
  $result.message:="Disclosed native rows overlap or have ambiguous identity"
  return
 End if
 $node.id:=$identity
 $lastBottom:=$node.frame[1]+$node.frame[3]
 $rows.push($identity)
 $outline[$identity]:=$definition
 $positions[$identity]:=$node.position
 $layout.push(New collection($node.frame[1]; $node.frame[3]))
End for each
$result:=New object("ok"; True; "rows"; $rows; "outline"; $outline; "positions"; $positions; "layout"; $layout; "registry"; $registry; "requiresGeneration"; False)
If (($previous#Null) && ($previous.outline#Null))
 For each ($key; $outline)
  If (($previous.outline[$key]#Null) && (Compare strings($previous.outline[$key].parent; $outline[$key].parent; sk char codes)#0))
   $result.requiresGeneration:=True
  End if
 End for each
End if
