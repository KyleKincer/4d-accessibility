// A declared higher layer can cover a button without changing 4D's visible flag.
// Keep the original controls; omit only a button fully covered by one such control.
#DECLARE($nodes : Collection; $options : Object) -> $result : Collection
var $layers : Object
var $node; $other; $metadata : Object
var $name : Text
var $layer; $otherLayer : Real
var $covered : Boolean
$result:=$nodes
If (($options=Null) || ($options.controls=Null))
 return
End if
$layers:=New object
For each ($name; $options.controls)
 $metadata:=$options.controls[$name]
 If (($metadata.layer#Null) && ($metadata.layer#0))
  $layers[$name]:=$metadata.layer
 End if
End for each
If (OB Keys($layers).length=0)
 return
End if
$result:=New collection
For each ($node; $nodes)
 $covered:=False
 If ($node.role="button")
  $layer:=0
  If (OB Is defined($layers; $node.objectName))
   $layer:=$layers[$node.objectName]
  End if
  For each ($other; $nodes)
   If (($other.id#$node.id) & (New collection("text"; "group").indexOf($other.role)<0))
    $otherLayer:=0
    If (OB Is defined($layers; $other.objectName))
     $otherLayer:=$layers[$other.objectName]
    End if
    If (($otherLayer>$layer) & ($other.frame[0]<=$node.frame[0]) & ($other.frame[1]<=$node.frame[1]) & \
     (($other.frame[0]+$other.frame[2])>=($node.frame[0]+$node.frame[2])) & (($other.frame[1]+$other.frame[3])>=($node.frame[1]+$node.frame[3])))
     $covered:=True
     break
    End if
   End if
  End for each
 End if
 If (Not($covered))
  $result.push($node)
 End if
End for each
