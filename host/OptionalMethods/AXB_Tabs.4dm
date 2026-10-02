// Describe displayed tab choices without selecting, expanding or evaluating
// application data. Actual segment boxes come from the native draw observer.
#DECLARE($name : Text; $pointer : Pointer; $options : Object; $state : Object; $paintOffset : Collection) -> $result : Object
var $value : Variant
var $items; $nodes : Collection
var $group; $node; $layout; $segment; $metadata; $previous : Object
var $i; $index; $list; $position; $reference; $sublist; $end : Integer
var $left; $top; $right; $bottom; $originX; $originY : Integer
var $label; $signature; $id; $text : Text
var $expanded : Boolean
$result:=New object("ok"; False; "error"; "tabSourceTypePending"; "nodes"; New collection)
$items:=New collection
$index:=-1
If (($pointer#Null) && (Type($pointer->)=Text array))
 For ($i; 1; Size of array($pointer->))
  $items.push(New object("label"; $pointer->{$i}; "key"; String($i)))
 End for
 $index:=$pointer->-1
Else
 $value:=OBJECT Get value($name)
 If ((Value type($value)=Is object) && ($value#Null))
  If ((Value type($value.values)#Is collection) || ($value.values=Null))
   return
  End if
  For ($i; 0; $value.values.length-1)
   If (Value type($value.values[$i])#Is text)
    return
   End if
   $items.push(New object("label"; $value.values[$i]; "key"; String($i)))
  End for
  If ((New collection(Is real; Is integer; Is longint).indexOf(Value type($value.index))>=0) && \
    ($value.index=Int($value.index)) && ($value.index>=0) && ($value.index<$items.length))
   $index:=$value.index
  End if
 Else
  $list:=OBJECT Get list reference(*; $name; Choice list)
  If (($list=0) && (New collection(Is real; Is integer; Is longint).indexOf(Value type($value))>=0))
   If (Is a list($value))
    $list:=$value
   End if
  End if
  If ($list=0)
   return
  End if
  // Only the first level supplies tabs. Reading a position never expands a
  // shared list, unlike List item position. Keep reference IDs in the host.
  $position:=1
  While ($position<=Count list items($list))
   GET LIST ITEM($list; $position; $reference; $text; $sublist; $expanded)
   $items.push(New object("label"; $text; "key"; String($reference)))
   $position:=$position+1
   If (($sublist#0) & $expanded)
    $position:=$position+Count list items($sublist)
   End if
  End while
 End if
End if
If ($items.length>4096)
 $result.error:="tabCountExceeded"
 return
End if
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
If (($right<=$left) | ($bottom<=$top))
 $result.ok:=True
 return
End if
$originX:=0
$originY:=0
CONVERT COORDINATES($originX; $originY; XY Current form; XY Current window)
If ($paintOffset#Null)
 // 4D scrolls the existing canvas bitmap without repainting its cells.
 // Query the unscrolled paint, then retain segment boxes in form coordinates.
 $originX:=$originX+$paintOffset[0]
 $originY:=$originY+$paintOffset[1]
End if
$label:=OBJECT Get help tip(*; $name)
If (($options#Null) && ($options.controls#Null))
 $metadata:=$options.controls[$name]
 If (($metadata#Null) && (Value type($metadata.label)=Is text))
  $label:=$metadata.label
 End if
End if
If ($label="")
 $label:=$name
End if
If (Length($label)>512)
 $end:=512
 If (AXB_TextIndex($label; $end; False)<0)
  $end:=$end-1
 End if
 $label:=Substring($label; 1; $end)
End if
$id:="control."+Substring(Generate digest($name; SHA256 digest); 1; 32)
$group:=New object("id"; $id; "objectName"; $name; "role"; "tabgroup"; "label"; $label; "value"; ""; "enabled"; OBJECT Get enabled(*; $name); "visible"; True; "focusable"; False; "editable"; False; "frame"; New collection($left; $top; $right-$left; $bottom-$top))
$result.nodes.push($group)
If ($items.length=0)
 $result.ok:=True
 return
End if
If ($state#Null)
 $previous:=$state[$name]
 If ($previous=Null)
  $previous:=New object("owner"; Generate UUID; "signature"; ""; "frame"; New collection; "serial"; 0)
  $state[$name]:=$previous
 End if
End if
$signature:=Substring(Generate digest(JSON Stringify($items); SHA256 digest); 1; 24)
$metadata:=New object("frame"; New collection($left+$originX; $top+$originY; $right-$left; $bottom-$top); "count"; $items.length; "signature"; $signature)
If ($previous#Null)
 $metadata.owner:=$previous.owner
End if
$layout:=AXB_Host("layout"; $metadata)
If (Not($layout.ok=True))
 $result.error:=$layout.error
 return
End if
If ($previous#Null)
 If ((($previous.signature#$signature) | (JSON Stringify($previous.frame)#JSON Stringify($metadata.frame))) && ($layout.serial<=$previous.serial))
  // Source or dimensions can change before the canvas repaints. Require
  // current geometry for both strips and compact controls.
  $result.error:="nativeTabLayoutPending"
  return
 End if
 $previous.signature:=$signature
 $previous.frame:=$metadata.frame.copy()
 $previous.serial:=$layout.serial
End if
If ($layout.kind="popup")
 // 4D turns a narrow tab control into a native popup. Keep that presentation
 // and its original menu/handlers instead of inventing hidden tab buttons.
 $group.role:="popup"
 $group.value:=$layout.label
 If (($group.value="") & ($index>=0) & ($index<$items.length))
  $group.value:=$items[$index].label
 End if
 If (($group.value="") & ($list#0))
  GET LIST ITEM($list; *; $reference; $text)
  $group.value:=$text
  If (($reference=0) & ($items.length>0))
   $group.value:=$items[0].label
  End if
 End if
 $result.ok:=True
 return
End if
For ($i; 0; $items.length-1)
 $segment:=$layout.segments[$i]
 If (($index>=0) & ($index<$items.length))
  // The live binding owns selection. A painted cell may lag the business
  // handler by one cycle; that lag must not retire an unchanged choice.
  $segment.selected:=$i=$index
 End if
 $label:=$items[$i].label
 If (Length($label)>512)
  $end:=512
  If (AXB_TextIndex($label; $end; False)<0)
   $end:=$end-1
  End if
  $label:=Substring($label; 1; $end)
 End if
 $node:=New object("id"; $id+"."+$signature+"."+String($i); "parent"; $id; "objectName"; $name; "role"; "tab"; "label"; $label; "value"; $segment.selected; "enabled"; $group.enabled & $segment.enabled; "visible"; True; "focusable"; False; "editable"; False; "frame"; New collection($segment.frame[0]-$originX; $segment.frame[1]-$originY; $segment.frame[2]; $segment.frame[3]))
 $node.automationChild:=New collection("tab"; $items[$i].key)
 $result.nodes.push($node)
End for
$result.ok:=True
