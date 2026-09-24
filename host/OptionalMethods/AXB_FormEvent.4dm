// Observe actual form events. Resolve their evidence after the root has
// refreshed every child, so scrolling cannot select an old cached position.
#DECLARE($operation : Text) -> $result : Object
var $registry; $event; $node; $owner; $observed; $reply; $known : Object
var $matches; $candidates : Collection
var $x; $y : Integer
ARRAY LONGINT($events; 2)
$result:=New object("ok"; True)
If ($operation#"resolve")
 If (Form event code=On Load)
  $reply:=AXB_Host("info"; New object)
  If (Not($reply.ok=True))
   return $reply
  End if
  $events{1}:=On Getting Focus
  $events{2}:=On Losing Focus
  OBJECT SET EVENTS(*; ""; $events; Enable events others unchanged)
  return
 End if
 If ((Form event code#On Getting Focus) & (Form event code#On Losing Focus))
  return
 End if
End if
$registry:=AXB_FormRoots[String(Current form window)]
If ($registry=Null)
 return
End if
$observed:=$registry.observedFocus
If ($operation="resolve")
 If (($observed=Null) || ($observed.id#Null))
  return
 End if
 $candidates:=New collection
 $matches:=New collection
 For each ($node; $registry.controls)
  $owner:=$registry.controlContexts[$node.id]
  If (($owner#Null) && (Compare strings($node.objectName; $observed.name; sk char codes)=0) && $node.visible && $node.enabled)
   If ((Compare strings($owner.formName; $observed.formName; sk char codes)=0) && (New collection($registry.bindings[$owner.bindingKey]).indexOf($observed.data)=0))
    $candidates.push($node)
    If (($owner.origin[0]=$observed.origin[0]) & ($owner.origin[1]=$observed.origin[1]))
     $matches.push($node)
    End if
   End if
  End if
 End for each
 // A unique data binding does not need geometry. Shared data does.
 If ($candidates.length=1)
  $matches:=$candidates
 Else
  If ($matches.length=1)
   For each ($known; $observed.known)
    If (($known.id#$matches[0].id) & ($known.origin[0]=$observed.origin[0]) & ($known.origin[1]=$observed.origin[1]))
     // Another shared instance occupied this point in the preceding tree.
     // Without a fresh position before the event, ownership is uncertain.
     $matches:=New collection
     break
    End if
   End for each
  End if
 End if
 If ($matches.length=1)
  $registry.observedFocus:=New object("id"; $matches[0].id; "name"; $observed.name)
 Else
  OB REMOVE($registry; "observedFocus")
 End if
 return
End if
// A loss clears the observation even if the old child moved meanwhile.
// Keeping an uncertain old owner is worse than reporting ambiguous focus.
OB REMOVE($registry; "observedFocus")
If (Form event code=On Losing Focus)
 return
End if
$event:=Form event
If (Compare strings($event.objectName; OBJECT Get name(Object with focus); sk char codes)#0)
 return
End if
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$observed:=New object("name"; $event.objectName; "formName"; Current form name; "origin"; New collection($x; $y); "data"; Form; "known"; New collection)
For each ($node; $registry.controls)
 $owner:=$registry.controlContexts[$node.id]
 If (($owner#Null) && (Compare strings($node.objectName; $event.objectName; sk char codes)=0) && (Compare strings($owner.formName; Current form name; sk char codes)=0) && (New collection($registry.bindings[$owner.bindingKey]).indexOf(Form)=0))
  $observed.known.push(New object("id"; $node.id; "origin"; $owner.origin))
 End if
End for each
$registry.observedFocus:=$observed
