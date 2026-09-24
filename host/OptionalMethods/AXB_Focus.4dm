// Resolve one live control across the entire form, including repeated names.
// Native caret geometry comes from the public input-client API, on the UI
// thread through the SDK. No accessibility getter calls back into 4D.
#DECLARE() -> $result : Object
var $registry; $native; $node; $definition : Object
var $name; $row; $column : Text
var $matches; $bindings; $names; $frame : Collection
var $x; $y : Real
var $inside; $editing; $gridMatch : Boolean
var $pointer; $candidate : Pointer
$result:=New object
$registry:=AXB_FormRoots[String(Current form window)]
If (($registry=Null) || ($registry.controls=Null))
 return
End if
$native:=AXB_Host("focus"; New object)
If (Not($native.ok=True))
 return
End if
$name:=OBJECT Get name(Object with focus)
$editing:=Is editing text
$pointer:=OBJECT Get pointer(Object with focus)
$matches:=New collection
$bindings:=New collection
$names:=New collection
$gridMatch:=False
For each ($node; $registry.controls)
 If ($node.visible & $node.enabled)
  If (Compare strings($name; $node.objectName; sk char codes)=0)
   $names.push(New object("node"; $node))
   $gridMatch:=$gridMatch | ($node.grid#Null)
  End if
  If ($node.grid#Null)
   For each ($definition; $node.grid.columns)
    $gridMatch:=$gridMatch | (Compare strings($name; $definition.id; sk char codes)=0)
   End for each
  End if
 End if
 // Plugin editors can report exact cell identity through their public API,
 // even when 4D's native input client exposes no usable caret rectangle.
 If (($node.editor#Null) && $node.visible && $node.enabled && ($name=$node.objectName))
  If (Value type($registry.controlPointers[$node.id])=Is pointer)
   $candidate:=$registry.controlPointers[$node.id]
   If ($candidate=$pointer)
    $matches.push(New object("node"; $node; "cell"; OB Copy($node.editor)))
   End if
  End if
  continue
 End if
 If (($node.grid#Null) && $node.visible && $node.enabled && $editing && ($native.caret#Null))
  $x:=$native.caret[0]-$registry.origin[0]
  $y:=$native.caret[1]+($native.caret[3]/2)-$registry.origin[1]
  For each ($row; $node.grid.frames)
   For each ($column; $node.grid.frames[$row])
    If (($name=$column) | ($name=$node.objectName))
     $frame:=$node.grid.frames[$row][$column]
     If (($native.caret[3]>0) & ($x>=$frame[0]) & ($x<=($frame[0]+$frame[2])) & ($y>=$frame[1]) & ($y<($frame[1]+$frame[3])))
      $matches.push(New object("node"; $node; "cell"; New object("row"; $row; "column"; $column)))
     End if
    End if
   End for each
  End for each
  continue
 End if
 If ((Compare strings($name; $node.objectName; sk char codes)=0) & $node.visible & $node.enabled)
  If ($editing & ($node.role="textfield") & Not(Is nil pointer($pointer)))
   If (Value type($registry.controlPointers[$node.id])=Is pointer)
    $candidate:=$registry.controlPointers[$node.id]
    If ($candidate=$pointer)
     $bindings.push(New object("node"; $node))
    End if
   End if
  End if
  $inside:=True
  If ($editing)
   $inside:=False
   If (($native.caret#Null) && ($native.caret[3]>0))
    $x:=$native.caret[0]-$registry.origin[0]
    $y:=$native.caret[1]+($native.caret[3]/2)-$registry.origin[1]
    $inside:=($x>=$node.frame[0]) & ($x<=($node.frame[0]+$node.frame[2])) & ($y>=$node.frame[1]) & ($y<($node.frame[1]+$node.frame[3]))
    // Scrolling a label into view must not erase the keyboard focus of an
    // editor that moved outside the viewport. Its real caret still identifies
    // the full logical control frame; hidden controls remain excluded above.
   End if
  Else
   // 4D returns the focused binding globally. Dynamic variables are unique
   // per instance; shared explicit bindings still require a unique match.
   If (Not(Is nil pointer($pointer)))
    If (Value type($registry.controlPointers[$node.id])=Is pointer)
     $candidate:=$registry.controlPointers[$node.id]
     $inside:=$candidate=$pointer
    End if
    // Checkbox/popup cells keep the listbox's object name but 4D reports
    // their column's binding. Compare the exact live column in this instance.
    If (($node.cellFocus#Null) && (Value type($registry.cellPointers[$node.id])=Is pointer))
     $candidate:=$registry.cellPointers[$node.id]
     $inside:=$inside | ($candidate=$pointer)
    End if
   Else
    // Collection/entity checkbox columns have no binding pointer. On 20.8
    // the public native input client reports a zero-height rectangle at the
    // owning listbox origin. Match that exact origin across all live grids;
    // their previous cell positions alone survive a focus transfer.
    If (($node.grid#Null) && ($native.caret#Null) && ($native.caret[3]=0))
     $x:=$native.caret[0]-$registry.origin[0]
     $y:=$native.caret[1]-$registry.origin[1]
     $inside:=($x=$node.frame[0]) & ($y=$node.frame[1])
    End if
   End if
  End if
  If ($inside)
   $matches.push(New object("node"; $node))
  End if
 End if
End for each
// A long multiline editor can report an unscrolled offscreen caret through
// the public native API. An exact, unique live binding still identifies it.
// Shared bindings remain ambiguous and must use the geometry path above.
If (($matches.length=0) & Not($gridMatch))
 If ($bindings.length=1)
  $matches:=$bindings
 Else
  // Object-property expressions have no pointer. A globally unique object
  // name is still exact; repeated names and grid column names remain guarded.
  If ($editing & ($names.length=1))
   If ($names[0].node.role="textfield")
    $matches:=$names
   End if
  End if
 End if
End if
// A real form focus event can disambiguate shared bindings and native input
// clients that retain the previous editor's rectangle. Never use a requested
// focus target as evidence. Scoped IDs retire on replacement and record change.
If (($registry.observedFocus#Null) && ($registry.observedFocus.id#Null))
 For each ($node; $registry.controls)
  If (($node.id=$registry.observedFocus.id) && (Compare strings($node.objectName; $name; sk char codes)=0) && $node.visible && $node.enabled)
   $matches:=New collection(New object("node"; $node))
   break
  End if
 End for each
End if
If ($matches.length=1)
 $result:=$matches[0]
 If (Not($editing) & ($result.node.cellFocus#Null))
  $result.cell:=OB Copy($result.node.cellFocus)
 End if
 $result.native:=$native
 $result.editing:=$editing | ($result.node.editor#Null)
Else
 If ($names.length>1)
  $result.error:="ambiguousFocus"
  $result.object:=$name
 End if
End if
