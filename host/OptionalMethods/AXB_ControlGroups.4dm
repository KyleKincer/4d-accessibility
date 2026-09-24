// Group controls only when containment has one unambiguous innermost box.
// Explicit group metadata resolves overlapping boxes or keeps a control at root.
#DECLARE($nodes : Collection; $options : Object) -> $diagnostics : Collection
var $node; $group; $other; $metadata; $chosen : Object
var $candidates; $groups : Collection
var $contains; $minimal; $explicit : Boolean
$diagnostics:=New collection
$groups:=$nodes.query("role = :1"; "group")
If (($groups.length=0) & ($options.controls=Null))
 return
End if
For each ($node; $nodes)
 $metadata:=Null
 If (($options.controls#Null) && (Value type($node.objectName)=Is text))
  $metadata:=$options.controls[$node.objectName]
 End if
 $explicit:=($metadata#Null) && OB Is defined($metadata; "group")
 $chosen:=Null
 $candidates:=New collection
 If (Not(OB Is defined($node; "parent")))
  For each ($group; $groups)
   If (($group.role="group") & ($group.id#$node.id))
    $contains:=($group.frame[0]<=$node.frame[0]) & ($group.frame[1]<=$node.frame[1]) & (($group.frame[0]+$group.frame[2])>=($node.frame[0]+$node.frame[2])) & (($group.frame[1]+$group.frame[3])>=($node.frame[1]+$node.frame[3]))
    // Strict size prevents coincident boxes from parenting each other.
    $contains:=$contains & (($group.frame[2]>$node.frame[2]) | ($group.frame[3]>$node.frame[3]))
    If ($explicit)
     If (Value type($metadata.group)=Is text)
      If ((Compare strings($metadata.group; $group.objectName; sk char codes)=0) & $contains)
       $candidates.push($group)
      End if
     End if
    Else
     If ($contains)
      $candidates.push($group)
     End if
    End if
   End if
  End for each
  For each ($group; $candidates)
   $minimal:=True
   For each ($other; $candidates)
    If ($other.id#$group.id)
     // The selected candidate must itself lie inside every other candidate.
     $minimal:=$minimal & ($other.frame[0]<=$group.frame[0]) & ($other.frame[1]<=$group.frame[1]) & (($other.frame[0]+$other.frame[2])>=($group.frame[0]+$group.frame[2])) & (($other.frame[1]+$other.frame[3])>=($group.frame[1]+$group.frame[3]))
     $minimal:=$minimal & (($other.frame[2]>$group.frame[2]) | ($other.frame[3]>$group.frame[3]))
    End if
   End for each
   If ($minimal)
    $chosen:=$group
   End if
  End for each
  If ($chosen#Null)
   $node.parent:=$chosen.id
  Else
   If (($explicit & ($metadata.group#"")) | (Not($explicit) & ($candidates.length>0)))
    $diagnostics.push(New object("object"; $node.objectName; "reason"; "ambiguousGroup"))
   End if
  End if
 End if
End for each
