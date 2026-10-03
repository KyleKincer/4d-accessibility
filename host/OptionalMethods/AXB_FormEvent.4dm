// Observe actual form events. Resolve their evidence after the root has
// refreshed every child, so scrolling cannot select an old cached position.
#DECLARE($operation : Text) -> $result : Object
var $registry; $event; $node; $owner; $observed; $reply; $known; $record; $source; $selected; $selectedOwner : Object
var $matches; $candidates; $sources; $records; $contexts; $forwarded : Collection
var $property : Text
var $i : Integer
var $prefix; $replace : Boolean
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
  AXB_FormObserver("observe"; Null)
  return
 End if
 If ((Form event code#On Getting Focus) & (Form event code#On Losing Focus))
  return
 End if
 AXB_FormObserver("observe"; Null)
End if
$registry:=AXB_FormRoots[String(Current form window)]
If ($registry#Null)
 $observed:=$registry.observedFocus
End if
If ($operation="resolve")
 If ($registry=Null)
  return
 End if
 If (($observed=Null) || ($observed.id#Null) || ($observed.uncertain=True))
  return
 End if
 If ($observed.ambiguous=True)
  $observed.uncertain:=True
  return
 End if
 // A child focus event can also reach its parent form method. Resolve
 // all contexts from that event cycle, preferring a verified descendant.
 $sources:=$observed.sources
 $forwarded:=New collection
 For each ($source; $sources)
  $contexts:=New collection
  $matches:=New collection
  For each ($owner; OB Values($registry.formContexts))
   If ((Compare strings($owner.formName; $source.formName; sk char codes)=0) && (New collection($registry.bindings[$owner.bindingKey]).indexOf($source.data)=0))
    $contexts.push($owner)
    If (($owner.origin[0]=$source.origin[0]) & ($owner.origin[1]=$source.origin[1]))
     $matches.push($owner)
    End if
   End if
  End for each
  If ($contexts.length=1)
   $matches:=$contexts
  End if
  If ($matches.length#1)
   $observed.uncertain:=True
   return
  End if
  $reply:=$matches[0]
  $registry.focusObserverBindings[$reply.bindingKey]:=True
  $candidates:=New collection
  $matches:=New collection
  For each ($node; $registry.controls)
   $owner:=$registry.controlContexts[$node.id]
   If (($owner#Null) && (Compare strings($node.objectName; $source.name; sk char codes)=0))
    If ((Compare strings($owner.formName; $source.formName; sk char codes)=0) && (New collection($registry.bindings[$owner.bindingKey]).indexOf($source.data)=0))
     If ($node.visible && $node.enabled)
      $candidates.push($node)
      If (($owner.origin[0]=$source.origin[0]) & ($owner.origin[1]=$source.origin[1]))
       $matches.push($node)
      End if
     End if
    End if
   End if
  End for each
  // A unique data binding does not need geometry. Shared data does.
  If ($candidates.length=1)
   $matches:=$candidates
  End if
  If ($matches.length=1)
   $owner:=$registry.controlContexts[$matches[0].id]
   For each ($known; $source.known)
     If (($known.bindingKey#$owner.bindingKey) & ($known.origin[0]=$source.origin[0]) & ($known.origin[1]=$source.origin[1]))
      // Another shared instance occupied this point in the preceding tree.
      // Without a fresh position before the event, ownership is uncertain.
      $matches:=New collection
      break
     End if
   End for each
  End if
  If ($matches.length=1)
   $node:=$matches[0]
   $owner:=$registry.controlContexts[$node.id]
   If ($selected=Null)
    $selected:=$node
    $selectedOwner:=$owner
   Else
    If ($selected.id#$node.id)
     $prefix:=True
     For ($i; 0; New collection($owner.path.length; $selectedOwner.path.length).min()-1)
      $prefix:=$prefix & (Compare strings($owner.path[$i]; $selectedOwner.path[$i]; sk char codes)=0)
     End for
     If (Not($prefix) | ($owner.path.length=$selectedOwner.path.length))
      $observed.uncertain:=True
      return
     End if
     If ($owner.path.length>$selectedOwner.path.length)
      $selected:=$node
      $selectedOwner:=$owner
     End if
    End if
   End if
  Else
   If ($candidates.length>0)
    $observed.uncertain:=True
    return
   End if
   $forwarded.push($reply)
  End if
 End for each
 If ($selected#Null)
  // A forwarded ancestor without a local field is harmless only when its
  // current physical form is verified and belongs to the selected chain.
  For each ($owner; $forwarded)
   $prefix:=$owner.path.length<$selectedOwner.path.length
   For ($i; 0; $owner.path.length-1)
    $prefix:=$prefix && (Compare strings($owner.path[$i]; $selectedOwner.path[$i]; sk char codes)=0)
   End for
   If (Not($prefix))
    $observed.uncertain:=True
    return
   End if
  End for each
  // Use all native object/column names, including unsupported controls.
  // An unobserved descendant could have forwarded this same-named event.
  For each ($owner; OB Values($registry.formContexts))
   If (($owner.enabled#False) && ($owner.path.length>$selectedOwner.path.length))
    $prefix:=True
    For ($i; 0; $selectedOwner.path.length-1)
     $prefix:=$prefix & (Compare strings($owner.path[$i]; $selectedOwner.path[$i]; sk char codes)=0)
    End for
    If ($prefix && Not($registry.focusObserverBindings[$owner.bindingKey]=True))
     If (($owner.focusNames=Null) || ($owner.focusNames.indexOf($observed.name)>=0))
      $observed.uncertain:=True
      return
     End if
    End if
   End if
  End for each
  $registry.observedFocus:=New object("id"; $selected.id; "name"; $observed.name)
 Else
  If ($forwarded.length>0)
   $observed.uncertain:=True
  Else
   OB REMOVE($registry; "observedFocus")
  End if
 End if
 return
End if
// A loss clears the observation even if the old child moved meanwhile.
// Keeping an uncertain old owner is worse than reporting ambiguous focus.
If (Form event code=On Losing Focus)
 If ($registry#Null)
  OB REMOVE($registry; "observedFocus")
 End if
 If (AXB_Areas#Null)
  For each ($record; OB Values(AXB_Areas))
   If (($record.window=Current form window) & (New collection("initializing"; "queued").indexOf($record.state)>=0))
    OB REMOVE($record; "focusObservation")
   End if
  End for each
 End if
 return
End if
$event:=Form event
If (Compare strings($event.objectName; OBJECT Get name(Object with focus); sk char codes)#0)
 return
End if
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$source:=New object("name"; $event.objectName; "formName"; Current form name; "origin"; New collection($x; $y); "data"; Form; "known"; New collection)
$records:=New collection
If ($registry#Null)
 If ($registry.controls#Null)
  For each ($node; $registry.controls)
   $owner:=$registry.controlContexts[$node.id]
   If (($owner#Null) && ($registry.formContexts[$owner.bindingKey]#Null) && (Compare strings($node.objectName; $event.objectName; sk char codes)=0) && (Compare strings($owner.formName; Current form name; sk char codes)=0) && (New collection($registry.bindings[$owner.bindingKey]).indexOf(Form)=0))
    $source.known.push(New object("bindingKey"; $owner.bindingKey; "origin"; $owner.origin))
   End if
  End for each
 End if
 $property:="observedFocus"
 $records.push($registry)
Else
 // On Load can focus an editor before the area's deferred root startup.
 // Retain only real events within an already reserved area lifetime.
 $property:="focusObservation"
 If (AXB_Areas#Null)
  For each ($record; OB Values(AXB_Areas))
   If (($record.window=Current form window) & (New collection("initializing"; "queued").indexOf($record.state)>=0))
    $records.push($record)
   End if
  End for each
 End if
End if
For each ($record; $records)
 $observed:=$record[$property]
 If (($observed=Null) || ($observed.id#Null) || ($observed.uncertain=True) || (Compare strings($observed.name; $source.name; sk char codes)#0))
  $observed:=New object("name"; $source.name; "sources"; New collection)
 End if
 $replace:=False
 For ($i; 0; $observed.sources.length-1)
  $known:=$observed.sources[$i]
  If ((Compare strings($known.formName; $source.formName; sk char codes)=0) && (New collection($known.data).indexOf($source.data)=0) && ($known.origin[0]=$source.origin[0]) && ($known.origin[1]=$source.origin[1]))
   $observed.sources[$i]:=$source
   $replace:=True
   break
  End if
 End for
 If (Not($replace))
  // Discovery allows at most eight nested children. More than nine distinct
  // form contexts cannot identify one ancestor chain, even during a yield.
  If ($observed.sources.length<9)
   $observed.sources.push($source)
  Else
   $observed.ambiguous:=True
  End if
 End if
 $record[$property]:=$observed
End for each
