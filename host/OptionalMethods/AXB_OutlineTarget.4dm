// Resolve only a fresh semantic group. Published geometry may be translated;
// backing position and break level always come from the owning-form capture.
#DECLARE($state : Object; $action : Object; $before : Boolean) -> $target : Object
var $grid; $value; $group; $expected : Object
var $key; $property : Text
var $position : Integer
$target:=New object("ok"; False; "message"; "Group changed before disclosure completion")
If (($state=Null) || Not($state.valid=True) || ($action=Null) || ($action.operation#"gridSetExpanded"))
 return
End if
$grid:=$state.descriptor
If (($grid=Null) || ($action.value=Null) || (Value type($action.value)#Is object))
 return
End if
$value:=$action.value
If (Not($grid.actions.disclose=True) || (Value type($value.generation)#Is text) || ($value.generation#$grid.generation) || (Value type($value.row)#Is text) || (Value type($value.expanded)#Is Boolean))
 return
End if
$key:=$value.row
If (($grid.outline=Null) || Not(OB Is defined($grid.outline; $key)) || Not(OB Is defined($state.positions; $key)))
 return
End if
If (AXB_KeyIndex($grid.disabled; $key)>=0)
 return
End if
$group:=$grid.outline[$key]
If (($group.kind#"group") || ($value.expectedGroup=Null) || (Value type($value.expectedGroup)#Is object))
 return
End if
$expected:=$value.expectedGroup
If ((Value type($expected.kind)#Is text) || ($expected.kind#"group") || (Value type($expected.expanded)#Is Boolean))
 return
End if
For each ($property; New collection("parent"; "label"))
 If ((Value type($expected[$property])#Is text) || (Compare strings($group[$property]; $expected[$property]; sk char codes)#0))
  return
 End if
End for each
If ((Value type($expected.level)#Is real) || ($group.level#$expected.level) || ($before & ($group.expanded#$expected.expanded)))
 return
End if
$position:=$state.positions[$key]
If (($position<1) | ($position>$state.binding.count) | ($group.level<0) | ($group.level>=$state.binding.hierarchy.length))
 return
End if
return New object("ok"; True; "backingRow"; $position; "breakLevel"; $group.level+1; "expanded"; $group.expanded)
