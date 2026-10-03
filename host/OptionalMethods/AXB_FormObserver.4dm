// Track observer participation outside application data. Pending load notes
// belong to a reserved area, then to one discovered physical view lifetime.
#DECLARE($operation : Text; $view : Object) -> $result : Collection
var $registry; $record; $note; $owner : Object
var $records; $notes : Collection
var $key : Text
var $x; $y; $i : Integer
$result:=New collection
$registry:=AXB_FormRoots[String(Current form window)]
Case of
 : ($operation="snapshot")
  If (($registry=Null) || ($registry.formContexts=Null))
   return
  End if
  For each ($key; $registry.formContexts)
   $owner:=$registry.formContexts[$key]
   If ($registry.focusObserverBindings[$key]=True)
    If (($view=Null) || ($owner.path.indexOf($view.excludeSubform)<0))
     // Carry participation only to this same form path and data identity.
     // A new form at the old position cannot consume this stronger note.
     $result.push(New object("formName"; $owner.formName; "origin"; $owner.origin; "path"; $owner.path; "data"; $registry.bindings[$key]))
    End if
   End if
  End for each
 : ($operation="transfer")
  If ($registry=Null)
   return
  End if
  If ($view.focusObservers#Null)
   If ($registry.focusObservers=Null)
    $registry.focusObservers:=New collection
   End if
   $registry.focusObservers:=$registry.focusObservers.concat($view.focusObservers)
   If (($registry.observedFocus#Null) && ($registry.observedFocus.sources#Null))
    // Recheck the same evidence now that participation is known.
    OB REMOVE($registry.observedFocus; "uncertain")
   End if
  End if
  If (($registry.observedFocus=Null) && ($view.focusObservation#Null))
   If (Compare strings($view.focusObservation.name; OBJECT Get name(Object with focus); sk char codes)=0)
    $registry.observedFocus:=$view.focusObservation
   End if
  End if
 : ($operation="forget")
  If ($registry#Null)
   OB REMOVE($registry; "focusObservers")
  End if
  If (AXB_Areas#Null)
   For each ($record; OB Values(AXB_Areas))
    If ($record.window=Current form window)
     OB REMOVE($record; "focusObservers")
    End if
   End for each
  End if
 : ($operation="bind")
  If ($registry.focusObserverBindings=Null)
   $registry.focusObserverBindings:=New object
  End if
  If ($registry.focusObserverBindings[$view.bindingKey]=True)
   return
  End if
  If ($registry.focusObservers=Null)
   $registry.focusObservers:=New collection
  End if
  $notes:=$registry.focusObservers
  For ($i; 0; $notes.length-1)
   $note:=$notes[$i]
   If (Compare strings($note.formName; $view.formName; sk char codes)=0)
    If ($note.path#Null)
     If ((Compare strings(JSON Stringify($note.path); JSON Stringify($view.path); sk char codes)#0) || (New collection($note.data).indexOf($view.data)#0))
      continue
     End if
    Else
     If (($note.origin[0]#$view.origin[0]) | ($note.origin[1]#$view.origin[1]))
      continue
     End if
    End if
    $registry.focusObserverBindings[$view.bindingKey]:=True
    $notes.remove($i)
    break
   End if
  End for
 : ($operation="observe")
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  If (($registry#Null) && ($registry.formContexts#Null))
   For each ($key; $registry.formContexts)
    $owner:=$registry.formContexts[$key]
    If ((Compare strings($owner.formName; Current form name; sk char codes)=0) && (New collection($registry.bindings[$key]).indexOf(Form)=0) && ($owner.origin[0]=$x) && ($owner.origin[1]=$y))
     $registry.focusObserverBindings[$key]:=True
     return
    End if
   End for each
  End if
  If (Form event code#On Load)
   return
  End if
  $records:=New collection
  If ($registry#Null)
   $records.push($registry)
  Else
   If (AXB_Areas#Null)
    For each ($record; OB Values(AXB_Areas))
     If (($record.window=Current form window) & (New collection("initializing"; "queued").indexOf($record.state)>=0))
      $records.push($record)
     End if
    End for each
   End if
  End if
  For each ($record; $records)
   If ($record.focusObservers=Null)
    $record.focusObservers:=New collection
   End if
   // Data can be rebound by On Load before discovery. Do not retain it here.
   // Bound notes are consumed once; invalidation discards unmatched notes.
   If ($record.focusObservers.length<4096)
    $record.focusObservers.push(New object("formName"; Current form name; "origin"; New collection($x; $y)))
   End if
  End for each
End case
