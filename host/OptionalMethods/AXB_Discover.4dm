// Discover ordinary live controls in their owning form. Never evaluate source
// expressions, read masked values, or copy application object/collection data.
#DECLARE($options : Object) -> $result : Object
var $name; $role; $label; $font : Text
var $indicator : Integer
var $minimum; $maximum : Real
var $minimumDate; $maximumDate : Date
var $description : Variant
var $parts; $labels : Collection
var $valueType : Integer
var $type; $i; $j; $left; $top; $right; $bottom; $distance; $best; $start; $end : Integer
var $node; $other; $metadata; $popup : Object
var $value : Variant
var $protected : Boolean
ARRAY TEXT($names; 0)
ARRAY TEXT($entry; 0)
ARRAY POINTER($pointers; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; True; "nodes"; New collection; "subforms"; New collection; "unsupported"; New collection)
FORM GET OBJECTS($names; $pointers; $pages; Form current page+Form inherited)
FORM GET ENTRY ORDER($entry; *)
For ($i; 1; Size of array($names))
 $name:=$names{$i}
 If (OBJECT Get visible(*; $name))
  $type:=OBJECT Get type(*; $name)
  $role:=""
  $label:=""
  $value:=""
  $protected:=False
  $metadata:=Null
  If (($options#Null) && ($options.controls#Null))
   $metadata:=$options.controls[$name]
  End if
  Case of
   : (New collection(Object type push button; Object type 3D button; Object type picture button; Object type highlight button; Object type invisible button).indexOf($type)>=0)
    $role:="button"
    $label:=OBJECT Get title(*; $name)
   : (New collection(Object type checkbox; Object type 3D checkbox).indexOf($type)>=0)
    $role:="checkbox"
    $label:=OBJECT Get title(*; $name)
    $value:=OBJECT Get value($name)
    If (Value type($value)#Is Boolean)
     If (OBJECT Get three states checkbox(*; $name) & (Num($value)=2))
      $value:=2
     Else
      $value:=Num($value)#0
     End if
    End if
   : (New collection(Object type radio button; Object type 3D radio button; Object type picture radio button).indexOf($type)>=0)
    $role:="radio"
    $label:=OBJECT Get title(*; $name)
    $value:=Num(OBJECT Get value($name))#0
   : ($type=Object type static text)
    $label:=OBJECT Get title(*; $name)
    // Empty dynamic captions contribute no content until the host fills them.
    // An explicit semantic name can still retain an intentionally empty node.
    If (($label#"") || (($metadata#Null) && (Value type($metadata.label)=Is text) && ($metadata.label#"")))
     $role:="text"
    End if
    $value:=$label
   : (($type=Object type text input) | ($type=Object type combobox))
    $role:="textfield"
    $font:=OBJECT Get font(*; $name)
    $protected:=($font="%password")
    If ($metadata#Null)
     $protected:=$protected | ($metadata.protected=True)
    End if
    If (Not($protected))
     $value:=OBJECT Get value($name)
     If ($type=Object type combobox)
      // An array combo's editable value is element zero, not its index.
      If ($pointers{$i}#Null)
       If (New collection(Text array; Real array; LongInt array; Integer array; Date array; Time array).indexOf(Type($pointers{$i}->))>=0)
        $value:=$pointers{$i}->{0}
       End if
      End if
      If ((Value type($value)=Is object) && ($value#Null))
       $value:=$value.currentValue
      End if
     End if
     $value:=AXB_ControlValue($value; OBJECT Get format(*; $name))
    End if
   : (($type=Object type popup dropdown list) | ($type=Object type hierarchical popup menu))
    $role:="popup"
    $popup:=AXB_PopupValue($name; $pointers{$i})
    $value:=$popup.value
    If (Not($popup.ok))
     $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "popupValueTypePending"))
    End if
   : ($type=Object type groupbox)
    $role:="group"
    $label:=OBJECT Get title(*; $name)
   : (New collection(Object type static picture; Object type picture input).indexOf($type)>=0)
    If (Not(($metadata#Null) && ($metadata.decorative=True)))
     $role:="image"
     $label:=OBJECT Get help tip(*; $name)
     If (($type=Object type picture input) && OBJECT Get enterable(*; $name))
      $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "pictureEditingPending"))
     End if
    End if
   : ($type=Object type ruler)
    $parts:=Split string(OBJECT Get format(*; $name); ";")
    $role:="slider"
    If (($parts.length>=7) && (Num($parts[6])=1))
     $role:="stepper"
    End if
    $value:=OBJECT Get value($name)
    $valueType:=Value type($value)
    If (($valueType=Is date) & ($role="slider"))
     // 4D's date ruler ignores its numeric range when operated by keyboard.
     // Expose its actual unbounded date adjustment, as with a date stepper.
     $role:="stepper"
    End if
    If (New collection(Is real; Is integer; Is longint; Is date; Is time).indexOf($valueType)<0)
     $role:=""
     $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "adjustableValueTypePending"))
    End if
    $label:=OBJECT Get help tip(*; $name)
   : ($type=Object type progress indicator)
    $indicator:=OBJECT Get indicator type(*; $name)
    $value:=OBJECT Get value($name)
    $valueType:=Value type($value)
    If (($indicator#Progress bar) | Not(OBJECT Get enterable(*; $name)))
     If (New collection(Is real; Is integer; Is longint; Is date; Is time).indexOf($valueType)>=0)
      $role:="progress"
      $label:=OBJECT Get help tip(*; $name)
     Else
      $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "progressValueTypePending"))
     End if
    Else
     If (New collection(Is real; Is integer; Is longint; Is date; Is time).indexOf($valueType)>=0)
      $role:="slider"
      $label:=OBJECT Get help tip(*; $name)
      $parts:=Split string(OBJECT Get format(*; $name); ";")
     Else
      $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "adjustableValueTypePending"))
     End if
    End if
   : ($type=Object type subform)
    $result.subforms.push($name)
   Else
    If (New collection(Object type line; Object type rectangle; Object type rounded rectangle; Object type oval).indexOf($type)<0)
     $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "providerPending"))
    End if
  End case
  If (($label="") && (New collection("button"; "checkbox"; "radio"; "popup").indexOf($role)>=0))
   // Icon and invisible buttons often already have a localized help tip.
   // Prefer a real caption; explicit accessibility metadata still wins below.
   $label:=OBJECT Get help tip(*; $name)
   If (Length($label)>512)
    $end:=512
    If (AXB_TextIndex($label; $end; False)<0)
     $end:=$end-1
    End if
    $label:=Substring($label; 1; $end)
   End if
  End if
  If ($role#"")
   OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
   If (($right>$left) & ($bottom>$top))
    $node:=New object("id"; "control."+Substring(Generate digest($name; SHA256 digest); 1; 32); "objectName"; $name; "role"; $role; "label"; $label; "value"; $value; "enabled"; OBJECT Get enabled(*; $name); "visible"; True; "frame"; New collection($left; $top; $right-$left; $bottom-$top))
    // The root resolves focus after collecting every instance. 4D reports the
    // same global editor name inside all repeated child execution contexts.
    $node.focused:=False
    $node.focusable:=Find in array($entry; $name)>0
    $node.protected:=$protected
    $node.editable:=False
    If ($role="textfield")
     $node.combo:=$type=Object type combobox
     $node.multiline:=Not($node.combo) && (OBJECT Get multiline(*; $name)=Multiline Yes)
     $node.placeholder:=OBJECT Get placeholder(*; $name)
     $node.editable:=OBJECT Get enterable(*; $name)
    End if
    If (New collection("group"; "image"; "progress").indexOf($role)>=0)
     $node.focusable:=False
    End if
    If (New collection("slider"; "stepper").indexOf($role)>=0)
     $node.adjustable:=OBJECT Get enterable(*; $name)
     $node.adjustment:="keyboard"
     If (($type=Object type ruler) && ($parts.length>=7) && (Num($parts[6])=1))
      $node.adjustment:="pointer"
     End if
     If ($type=Object type progress indicator)
      // 4D's local mouse path can retain the last track position after a
      // programmatic reset. Use the application's shared value controller.
      $node.adjustable:=False
      If (($metadata#Null) && OB Is defined($metadata; "adjust"))
       $node.adjustment:="callback"
       $node.adjustable:=OBJECT Get enterable(*; $name)
      Else
       If (OBJECT Get enterable(*; $name))
        $result.unsupported.push(New object("object"; $name; "type"; $type; "reason"; "adjustmentCallbackRequired"))
       End if
      End if
     End if
     If (($metadata#Null) && OB Is defined($metadata; "adjust"))
      $node.adjustment:="callback"
     End if
     $node.vertical:=($bottom-$top)>($right-$left)
     $node.step:=Choose($parts.length>=4; Num($parts[3]); 1)
     If ($node.step<=0)
      $node.step:=1
     End if
     If ($valueType=Is date)
      $node.value:=String($value)
     Else
      $node.value:=Num($value)
      OBJECT GET MINIMUM VALUE(*; $name; $minimum)
      OBJECT GET MAXIMUM VALUE(*; $name; $maximum)
      $node.min:=$minimum
      $node.max:=$maximum
      // VoiceOver otherwise describes bounded numeric steppers as percentages.
      $node.valueDescription:=String($value)
     End if
    End if
    If ($role="progress")
     $node.vertical:=($bottom-$top)>($right-$left)
     $node.indeterminate:=$indicator#Progress bar
     If ($node.indeterminate)
      $node.valueDescription:=Choose($value#0; "In progress"; "Idle")
      $node.value:=Null
     Else
      If ($valueType#Is date)
       OBJECT GET MINIMUM VALUE(*; $name; $minimum)
       OBJECT GET MAXIMUM VALUE(*; $name; $maximum)
       $node.min:=$minimum
       $node.max:=$maximum
       $node.value:=Num($value)
       If ($valueType=Is time)
        $node.valueDescription:=String($value)
       End if
      End if
     End if
    End if
    If (($valueType=Is date) && (($role="slider") | (($role="progress") && Not($node.indeterminate))))
     OBJECT GET MINIMUM VALUE(*; $name; $minimumDate)
     OBJECT GET MAXIMUM VALUE(*; $name; $maximumDate)
     // Numeric positions are days from the actual lower bound. Assistive
     // technology reads the formatted date, not the internal day offset.
     $node.value:=$value-$minimumDate
     $node.min:=0
     $node.max:=$maximumDate-$minimumDate
     $node.valueDescription:=String($value)
    End if
    If (($metadata#Null) && OB Is defined($metadata; "description"))
     $description:=$metadata.description
     If ((Value type($description)=Is object) && ($description#Null))
      If (OB Instance of($description; 4D.Function))
       $description:=$description.call()
      End if
     End if
     If (Value type($description)#Is text)
      $result.ok:=False
      $result.error:="invalidControlDescription"
      return
     End if
     If ($role="image")
      $node.value:=$description
     Else
      $node.valueDescription:=$description
     End if
    End if
    If (($metadata#Null) && (Value type($metadata.label)=Is text))
     $node.label:=$metadata.label
     $node.explicitLabel:=True
    End if
    $result.nodes.push($node)
   End if
  End if
 End if
End for
// Infer only a close, vertically aligned static label to the left. Ambiguous
// names remain diagnosable and can be supplied once in declarative metadata.
$labels:=New collection
For each ($node; $result.nodes)
 If (($node.role="text") && Match regex("(?s).*[[:alnum:]].*"; $node.label))
  $labels.push($node)
 End if
End for each
For each ($node; $result.nodes)
 If ($node.label="")
  $best:=101
  For each ($other; $labels)
   If (Abs($other.frame[1]-$node.frame[1])<=4)
    $distance:=$node.frame[0]-($other.frame[0]+$other.frame[2])
    If (($distance>=0) & ($distance<$best))
     $best:=$distance
     $node.label:=$other.label
     $node.labelledBy:=$other.id
    End if
   End if
  End for each
  If (($node.label="") && ($node.role="image") && ($node.value#""))
   $node.label:=$node.value
   $node.value:=""
  End if
  If ($node.label="")
   $node.label:=$node.objectName
   $node.missingLabel:=True
  End if
 End if
End for each
