// Read one displayed scalar. Never serialize an application's object graph.
#DECLARE($state : Object; $column : Object; $row : Integer) -> $result : Object
var $pointer : Pointer
var $item; $request : Object
var $value : Variant
var $issue : Text
var $type; $checked : Integer
$result:=New object("ok"; True; "value"; ""; "editable"; False; "enabled"; True)
If ($column.protected | ($column.blank=True))
 return
End if
$issue:=String($row)+":"+$column.name
If ($state.valueIssues=Null)
 $state.valueIssues:=New object
End if
If ($column.value#Null)
 $request:=New object("row"; $row; "column"; $column.name)
 If (Value type($column.pointer)=Is pointer)
  $pointer:=$state.binding.keyPointer
  $request.key:=$pointer->{$row}
 Else
  $request.item:=$state.binding.source[$row-1]
  $request.key:=$request.item[$state.binding.keyProperty]
 End if
 // Match the collection/entity renderer's This without evaluating its source.
 // Array callbacks keep a null receiver and use the current source row.
 $value:=$column.value.call($request.item; $request)
 If (Value type($value)=Is text)
  OB REMOVE($state.valueIssues; $issue)
  $result.value:=$value
 Else
  $state.valueIssues[$issue]:=$column.name
  $result.ok:=False
  $result.value:="Cell description required"
 End if
 return
End if
If (Value type($column.pointer)=Is pointer)
 $pointer:=$column.pointer
 $value:=$pointer->{$row}
Else
 $item:=$state.binding.source[$row-1]
 If ($item=Null)
  $state.valueIssues[$issue]:=$column.name
  $result.ok:=False
  $result.value:="Row is unavailable"
  return
 End if
 $value:=$item[$column.property]
 // List fields retain their native type even when objects store dates as
 // strings or times as numbers. ORDA always expresses time in seconds;
 // native snapshots follow the application's object compatibility setting.
 If (($column.fieldType#Null) & ($value#Null))
  If ($column.fieldType=Is time)
   If (Value type($state.binding.source)=Is collection)
    $value:=OB Get($item; $column.property; Is time)
   Else
    $value:=Time($value)
   End if
  End if
  If (($column.fieldType=Is date) & (Value type($state.binding.source)=Is collection))
   $value:=OB Get($item; $column.property; Is date)
  End if
 End if
 If (($state.liveValues#Null) && ($state.binding.records#Null) && ($state.liveValues.record=$state.binding.records[$row-1]) && OB Is defined($state.liveValues.values; $column.name))
  $value:=$state.liveValues.values[$column.name]
  If (New collection(Is date; Is time).indexOf($column.fieldType)>=0)
   $value:=OB Get($state.liveValues.values; $column.name; $column.fieldType)
  End if
 End if
End if
If (($value=Null) || (New collection(Is text; Is real; Is integer; Is longint; Is date; Is time; Is Boolean).indexOf(Value type($value))>=0))
 OB REMOVE($state.valueIssues; $issue)
 $type:=Value type($value)
 $result.value:=AXB_ControlValue($value; $column.format)
 // Null collection/entity expressions cannot enter a native cell editor.
 $result.editable:=$value#Null
 If (($column.controlRole="checkbox") & ($type#Is Boolean))
  If ((New collection(Is real; Is integer; Is longint).indexOf($type)<0) || ($value=Null) || ($column.threeStates & (New collection(0; 1; 2).indexOf($value)<0)))
   $result.ok:=False
   $result.editable:=False
   $state.valueIssues[$issue]:=$column.name
   return
  End if
  $checked:=Choose($value=0; 0; 1)
  If ($column.threeStates)
   $checked:=$value
  End if
  $result.role:="checkbox"
  $result.checked:=$checked
  $result.value:=String($checked)
  return
 End if
 If (($type=Is Boolean) & ($column.controlRole#"text"))
  $result.boolean:=True
  If (($column.display=lk numeric format) & (Position(";"; $column.format)>0))
   $result.role:="popup"
  Else
   $result.role:="checkbox"
   $result.checked:=Choose($value; 1; 0)
   $result.label:=$column.format
   $result.value:=String($value)
  End if
 Else
  If (($column.display=lk three states checkbox) & ($value#Null))
   If (New collection(Is real; Is integer; Is longint).indexOf($type)<0)
    $result.ok:=False
    $result.editable:=False
    $state.valueIssues[$issue]:=$column.name
    return
   End if
   $result.editable:=$value>=0
   $result.enabled:=$value>=0
   If ($value=-1)
    $result.value:=""
   Else
    If (($value<0) & (New collection(-2; -3; -4).indexOf($value)<0))
     $result.ok:=False
     $result.value:="Unsupported checkbox state"
     $state.valueIssues[$issue]:=$column.name
     return
    End if
    $checked:=2
    If (($value=0) | ($value=-2))
     $checked:=0
    End if
    If (($value=1) | ($value=-3))
     $checked:=1
    End if
    $result.role:="checkbox"
    $result.checked:=$checked
    // A numeric format is not the checkbox caption. Its column label names
    // the control; applications can supply a missing caption in that label.
    $result.value:=String($checked)
   End if
  End if
 End if
Else
 $state.valueIssues[$issue]:=$column.name
 $result.ok:=False
 $result.value:="Cell description required"
End if
