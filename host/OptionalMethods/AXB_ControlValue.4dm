// Convert a scalar using the control's display format. Callers must check
// protection before obtaining the value. Never stringify arbitrary objects.
#DECLARE($value : Variant; $format : Text) -> $text : Text
var $type; $separator : Integer
$text:=""
$type:=Value type($value)
Case of
 : ($type=Is text)
  $text:=$value
 : (New collection(Is real; Is integer; Is longint).indexOf($type)>=0)
  If (Length($format)=0)
   $text:=String($value)
  Else
   $text:=String($value; $format)
  End if
 : (($type=Is date) | ($type=Is time))
  Case of
   : (Length($format)=0)
    $text:=String($value)
   : (Length($format)=1)
    $text:=String($value; Character code($format))
   Else
    $text:=String($value; $format)
  End case
 : ($type=Is Boolean)
  $separator:=Position(";"; $format)
  If ($separator>0)
   If ($value)
    $text:=Substring($format; 1; $separator-1)
   Else
    $text:=Substring($format; $separator+1)
   End if
  Else
   $text:=String($value)
  End if
End case
