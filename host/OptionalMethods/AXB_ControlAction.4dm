// Use native events or an explicitly configured shared application controller.
#DECLARE($action : Object; $options : Object) -> $result : Object
var $description; $node; $target; $metadata : Object
var $ignored; $value : Variant
var $valueType : Integer
var $left; $top; $right; $bottom; $x; $y : Integer
$result:=New object("status"; "rejected"; "message"; "Control is unavailable")
$description:=AXB_Discover($options)
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
 : (($action.operation="press") & (New collection("button"; "checkbox"; "radio"; "popup").indexOf($target.role)>=0))
  OBJECT GET COORDINATES(*; $target.objectName; $left; $top; $right; $bottom)
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
  // Do not click through an overlapping control. A custom adapter can provide
  // an unambiguous semantic operation for an intentionally layered control.
  For each ($node; $description.nodes)
   If (($node.id#$target.id) & (New collection("text"; "group").indexOf($node.role)<0))
    If (($x>=$node.frame[0]) & ($x<($node.frame[0]+$node.frame[2])) & ($y>=$node.frame[1]) & ($y<($node.frame[1]+$node.frame[3])))
     $result.message:="Control is overlapped"
     return
    End if
   End if
  End for each
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  POST CLICK($x; $y; Current process)
 Else
  $result.message:="Operation is unavailable"
  return
End case
$result:=New object("status"; "pending"; "confirm"; Formula(AXB_ControlConfirm($1)); "data"; New object("objectName"; $target.objectName; "operation"; $action.operation; "role"; $target.role; "previousValue"; $target.value))
