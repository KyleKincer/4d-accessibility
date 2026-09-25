// Find a point in the revealed control which no equal/higher layer covers.
// Layers are explicit host metadata; FORM GET OBJECTS does not return z-order.
#DECLARE($target : Object; $description : Object; $options : Object; $bounds : Collection) -> $point : Collection
var $regions; $next; $rect; $best : Collection
var $nodes; $names : Collection
var $node; $metadata; $known; $issue : Object
var $name : Text
var $coverLeft; $coverTop; $coverRight; $coverBottom : Integer
var $layer; $otherLayer; $left; $top; $right; $bottom; $area; $bestArea : Real
$point:=New collection
$nodes:=$description.nodes.copy()
$known:=New object
For each ($node; $nodes)
 $known[$node.objectName]:=True
End for each
$names:=$description.subforms.copy()
For each ($issue; $description.unsupported)
 $names.push($issue.object)
End for each
// A grid, subform or opaque vendor control still intercepts native mouse input,
// even if it has a separate provider or no accessibility provider yet.
For each ($name; $names)
 If (Not(OB Is defined($known; $name)))
  $known[$name]:=True
  OBJECT GET COORDINATES(*; $name; $coverLeft; $coverTop; $coverRight; $coverBottom)
  If (($coverRight>$coverLeft) & ($coverBottom>$coverTop))
   $nodes.push(New object("id"; "obstacle."+$name; "objectName"; $name; "role"; "opaque"; \
    "frame"; New collection($coverLeft; $coverTop; $coverRight-$coverLeft; $coverBottom-$coverTop)))
  End if
 End if
End for each
$layer:=0
If (($options#Null) && ($options.controls#Null) && ($options.controls[$target.objectName]#Null))
 $metadata:=$options.controls[$target.objectName]
 If ($metadata.layer#Null)
  $layer:=$metadata.layer
 End if
End if
$regions:=New collection($bounds)
For each ($node; $nodes)
 If (($node.id#$target.id) & (New collection("text"; "group").indexOf($node.role)<0))
  $otherLayer:=0
  If (($options#Null) && ($options.controls#Null) && ($options.controls[$node.objectName]#Null))
   $metadata:=$options.controls[$node.objectName]
   If ($metadata.layer#Null)
    $otherLayer:=$metadata.layer
   End if
  End if
  If ($otherLayer>=$layer)
   $next:=New collection
   For each ($rect; $regions)
    $left:=New collection($rect[0]; $node.frame[0]).max()
    $top:=New collection($rect[1]; $node.frame[1]).max()
    $right:=New collection($rect[2]; $node.frame[0]+$node.frame[2]).min()
    $bottom:=New collection($rect[3]; $node.frame[1]+$node.frame[3]).min()
    If (($right<=$left) | ($bottom<=$top))
     $next.push($rect)
    Else
     If ($top>$rect[1])
      $next.push(New collection($rect[0]; $rect[1]; $rect[2]; $top))
     End if
     If ($bottom<$rect[3])
      $next.push(New collection($rect[0]; $bottom; $rect[2]; $rect[3]))
     End if
     If ($left>$rect[0])
      $next.push(New collection($rect[0]; $top; $left; $bottom))
     End if
     If ($right<$rect[2])
      $next.push(New collection($right; $top; $rect[2]; $bottom))
     End if
    End if
   End for each
   $regions:=$next
   If (($regions.length=0) | ($regions.length>4096))
    return
   End if
  End if
 End if
End for each
$bestArea:=0
For each ($rect; $regions)
 // Keep the click away from an overlapping edge and from fractional slivers.
 If (($rect[2]-$rect[0]>=2) & ($rect[3]-$rect[1]>=2))
  $area:=($rect[2]-$rect[0])*($rect[3]-$rect[1])
  If ($area>$bestArea)
   $best:=$rect
   $bestArea:=$area
  End if
 End if
End for each
If ($best#Null)
 $point:=New collection(($best[0]+$best[2])/2; ($best[1]+$best[3])/2)
End if
