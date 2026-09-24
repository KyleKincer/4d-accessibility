// Read only the displayed choice. Never serialize the backing object or change
// selection/expansion to obtain a label. Array pointers stay in the host.
#DECLARE($name : Text; $pointer : Pointer) -> $result : Object
var $value : Variant
var $list; $index; $reference; $sublist : Integer
var $text : Text
var $expanded : Boolean
$result:=New object("ok"; True; "value"; "")
If ($pointer#Null)
 If (New collection(Text array; Real array; LongInt array; Integer array; Date array; Time array).indexOf(Type($pointer->))>=0)
  $index:=$pointer->
  If (($index>0) & ($index<=Size of array($pointer->)))
   $result.value:=AXB_ControlValue($pointer->{$index}; OBJECT Get format(*; $name))
  End if
  return
 End if
End if
$value:=OBJECT Get value($name)
If ((Value type($value)=Is object) && ($value#Null))
 // 4D maintains currentValue, including an index=-1 placeholder. Other
 // properties can hold application data and must remain private.
 $value:=$value.currentValue
 If (New collection(Is text; Is real; Is integer; Is longint; Is date; Is time; Is undefined; Is null).indexOf(Value type($value))<0)
  $result.ok:=False
 Else
  $result.value:=AXB_ControlValue($value; OBJECT Get format(*; $name))
 End if
 return
End if
Case of
 : (Value type($value)=Is text)
  $result.value:=$value
 : ((Value type($value)=Is date) | (Value type($value)=Is time))
  $result.value:=AXB_ControlValue($value; OBJECT Get format(*; $name))
 : (New collection(Is real; Is integer; Is longint).indexOf(Value type($value))>=0)
  $list:=OBJECT Get list reference(*; $name; Choice list)
  If ($list#0)
   // A choice list saved as reference displays only its first level. Walk
   // that level without List item position, which can expand shared lists.
   $index:=1
   While ($index<=Count list items($list))
    GET LIST ITEM($list; $index; $reference; $text; $sublist; $expanded)
    If ($reference=$value)
     $result.value:=$text
     return
    End if
    $index:=$index+1
    If (($sublist#0) & $expanded)
     $index:=$index+Count list items($sublist)
    End if
   End while
   // No matching choice is an empty selection, not a spoken reference ID.
  Else
   If ((OBJECT Get type(*; $name)=Object type hierarchical popup menu) && Is a list($value))
    GET LIST ITEM($value; *; $reference; $text)
    $result.value:=$text
   Else
    $result.ok:=False
   End if
  End if
 : ((Value type($value)=Is undefined) | (Value type($value)=Is null))
  // Empty object-backed menus have no current value.
 Else
  $result.ok:=False
End case
