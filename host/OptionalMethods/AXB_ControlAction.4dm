// Use native events or an explicitly configured shared application controller.
#DECLARE($action : Object; $options : Object; $tabState : Object; $paintOffset : Collection) -> $result : Object
var $description; $node; $target; $metadata : Object
var $ignored; $value : Variant
var $valueType : Integer
var $left; $top; $right; $bottom; $x; $y : Integer
var $point : Collection
$result:=New object("status"; "rejected"; "message"; "Control is unavailable")
$description:=AXB_Discover($options; $tabState; $paintOffset)
For each ($node; $description.nodes)
 If (Compare strings($node.id; $action.node; sk char codes)=0)
  $target:=$node
 End if
End for each
If (($target=Null) || Not($target.visible & $target.enabled))
 return
End if
If (Current form window#Frontmost window)
 return
End if
Case of
 : ((New collection("setValue"; "replaceSelection"; "setSelection").indexOf($action.operation)>=0) & ($target.role="textfield") & $target.editable)
  $result:=AXB_TextAction($action; $target; $options)
  return
 : ((New collection("increment"; "decrement"; "setValue").indexOf($action.operation)>=0) && ($target.role="splitter") && $target.adjustable)
  // 4D's dragging tracker follows the physical pointer, which posted events do
  // not move. Assigning the offset runs the same splitter handling: the same
  // limits and the same attached objects, without the drag's On Clicked.
  // VoiceOver writes the position it wants; increments move by one step.
  Case of
   : ($action.operation="increment")
    $value:=$target.step
   : ($action.operation="decrement")
    $value:=-$target.step
   Else
    $value:=Round(Num($action.value)-$target.value; 0)
  End case
  If ($value=0)
   return New object("status"; "completed"; "message"; "Splitter already at that position")
  End if
  OBJECT SET VALUE($target.objectName; $value)
  $result:=New object("status"; "pending"; "confirm"; Formula(AXB_SplitterConfirm($1)); "data"; New object("objectName"; $target.objectName; "operation"; Choose($value>0; "increment"; "decrement"); "vertical"; $target.vertical; "previousValue"; $target.value; "actionID"; $action.id; "deadline"; Milliseconds+2000))
  return
 : ((New collection("increment"; "decrement").indexOf($action.operation)>=0) && (New collection("slider"; "stepper").indexOf($target.role)>=0) && $target.adjustable)
  $value:=OBJECT Get value($target.objectName)
  $valueType:=Value type($value)
  If ($valueType=Is date)
   $value:=$value-!1904-01-01!
  Else
   $value:=Num($value)
  End if
  // Object properties normalize integer/time types. Retain the original type
  // separately so an unchanged typed binding cannot appear to have changed.
  $result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; New object("objectName"; $target.objectName; "operation"; $action.operation; "role"; $target.role; "previousValue"; $value; "previousType"; $valueType; "options"; $options; "actionID"; $action.id; "deadline"; Milliseconds+2000))
  If ($target.adjustment="callback")
   $metadata:=$options.controls[$target.objectName]
   If (($metadata=Null) || ($metadata.adjust=Null) || (Value type($metadata.adjust)#Is object))
    return New object("status"; "rejected"; "message"; "Adjustment callback is unavailable")
   End if
   If (Not(OB Instance of($metadata.adjust; 4D.Function)))
    return New object("status"; "rejected"; "message"; "Adjustment callback is unavailable")
   End if
   $ignored:=$metadata.adjust.call(Null; New object("objectName"; $target.objectName; "operation"; $action.operation; "delta"; Choose($action.operation="increment"; $target.step; -$target.step)))
   return
  End if
  If ($target.adjustment="pointer")
   AXB_PollGuard.context.controlInput:=New object("action"; $action.id)
   $result.data.awaitNative:=True
  Else
   If (Not($target.focusable))
    $result:=New object("status"; "rejected"; "message"; "Slider cannot receive keyboard input")
    return
   End if
   GOTO OBJECT(*; $target.objectName)
   $result.confirm:=Formula(AXB_ControlKey($1))
  End if
  return
 : ($action.operation="focus")
  // The request was accepted against the published focusable control. After
  // scrolling a child, 4D can temporarily omit its button from entry order
  // even though GOTO OBJECT still focuses it. Let the native command enforce
  // focusability, then confirm the actual focused instance on the next poll.
  GOTO OBJECT(*; $target.objectName)
 : ((New collection("showMenu"; "confirm"; "dismissMenu").indexOf($action.operation)>=0) & ($target.combo=True) & $target.focusable)
  If (Not(AXB_ControlFocus($target.objectName)))
   If ($action.operation#"showMenu")
    return
   End if
   GOTO OBJECT(*; $target.objectName)
  End if
  $result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlKey($1)); "data"; New object("objectName"; $target.objectName; "operation"; $action.operation; "role"; $target.role; "deadline"; Milliseconds+1500))
  return
 : (($action.operation="press") & (New collection("checkbox"; "radio").indexOf($target.role)>=0) & $target.focusable & Not(($target.role="checkbox") && OBJECT Get three states checkbox(*; $target.objectName)))
  // 4D 20.8 Space toggles only two states even on a three-state checkbox.
  // Mixed controls use the guarded native click below to preserve its cycle.
  GOTO OBJECT(*; $target.objectName)
  $result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlKey($1)); "data"; New object("objectName"; $target.objectName; "operation"; "press"; "role"; $target.role; "previousValue"; $target.value))
  return
 : (($action.operation="choose") & ($target.choices#Null))
  // 4D's picture popup palette is a menu of one unlabeled picture. The plugin
  // opens it with the control's own click and selects the cell as releasing
  // over it does, so 4D sets the value and runs the control's On Clicked.
  If ((Value type($action.value)#Is real) || ($action.value#Int($action.value)) || ($action.value<1) || ($action.value>$target.choices.length))
   return
  End if
  OBJECT GET COORDINATES(*; $target.objectName; $left; $top; $right; $bottom)
  $point:=AXB_ControlPoint($target; $description; $options; New collection($left; $top; $right; $bottom))
  If ($point.length#2)
   $result.message:="Control is overlapped"
   return
  End if
  $x:=$point[0]
  $y:=$point[1]
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  AXB_PollGuard.context.controlInput:=New object("action"; $action.id; "point"; New collection($x; $y); "choice"; $action.value)
  return New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; New object("nativeButton"; True; "actionID"; $action.id; "objectName"; $target.objectName; "choice"; $action.value; "deadline"; Milliseconds+2000))
 : (($action.operation="press") & (New collection("button"; "checkbox"; "radio"; "popup"; "tab").indexOf($target.role)>=0))
  // A tab or a button-grid cell is one part of its object; press its own frame.
  If (($target.role="tab") | ($target.cell#Null))
   $left:=$target.frame[0]
   $top:=$target.frame[1]
   $right:=$left+$target.frame[2]
   $bottom:=$top+$target.frame[3]
  Else
   OBJECT GET COORDINATES(*; $target.objectName; $left; $top; $right; $bottom)
  End if
  If ($action.viewport#Null)
   // Use the portion revealed through every ancestor, including the window.
   // A wide control's center can remain outside a small page-subform viewport.
   CONVERT COORDINATES($left; $top; XY Current form; XY Current window)
   CONVERT COORDINATES($right; $bottom; XY Current form; XY Current window)
   $right:=New collection($right; $action.viewport[0]+$action.viewport[2]).min()
   $bottom:=New collection($bottom; $action.viewport[1]+$action.viewport[3]).min()
   $left:=New collection($left; $action.viewport[0]).max()
   $top:=New collection($top; $action.viewport[1]).max()
   If (($right<=$left) | ($bottom<=$top))
    return
   End if
   CONVERT COORDINATES($left; $top; XY Current window; XY Current form)
   CONVERT COORDINATES($right; $bottom; XY Current window; XY Current form)
  End if
  $x:=($left+$right)/2
  $y:=($top+$bottom)/2
  If (New collection("checkbox"; "radio").indexOf($target.role)>=0)
   // Their clickable indicator is at the leading edge. A wide form rectangle
   // can extend beyond the caption's actual native hit area.
   $x:=$target.frame[0]+New collection(8; $target.frame[2]/2).min()
   If (($x<$left) | ($x>=$right))
    $result.message:="Control indicator is outside the viewport"
    return
   End if
  End if
  If (New collection("button"; "tab").indexOf($target.role)>=0)
   $point:=AXB_ControlPoint($target; $description; $options; New collection($left; $top; $right; $bottom))
  Else
   // Checkboxes/radios must still hit their indicator, not a free caption.
   $point:=AXB_ControlPoint($target; $description; $options; New collection($x-1; $y-1; $x+1; $y+1))
  End if
  If ($point.length#2)
   $result.message:="Control is overlapped"
   return
  End if
  $x:=$point[0]
  $y:=$point[1]
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  If (New collection("button"; "tab").indexOf($target.role)>=0)
   // Reuse guarded native delivery so nested dialogs receive a complete
   // mouse-down/up pair in their actual AppKit window.
   AXB_PollGuard.context.controlInput:=New object("action"; $action.id; "point"; New collection($x; $y))
   return New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; New object("nativeButton"; True; "actionID"; $action.id; "deadline"; Milliseconds+2000))
  End if
  POST CLICK($x; $y; Current process)
 Else
  $result.message:="Operation is unavailable"
  return
End case
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; New object("objectName"; $target.objectName; "operation"; $action.operation; "role"; $target.role; "previousValue"; $target.value))
