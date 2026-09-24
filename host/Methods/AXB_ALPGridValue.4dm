// Read the vendor's displayed cell and permissions, including an uncommitted
// checkbox editor. Bound array pointers stay in the owning host form.
#DECLARE($state : Object; $column : Object; $row : Integer) -> $result : Object
var $area; $mode; $error; $checked : Integer
var $hidden; $protected; $boolean : Boolean
var $source : Pointer
var $semantic : Variant
$area:=$state.area
$hidden:=AL_GetCellLongProperty($area; $row; $column.number; ALP_Cell_Invisible)#0
$protected:=AL_GetCellTextProperty($area; $row; $column.number; ALP_Cell_FormatResolved)=Char(8226)
$mode:=AL_GetCellLongProperty($area; $row; $column.number; ALP_Cell_Enterable)
If ($mode=-1)
 $mode:=AL_GetColumnLongProperty($area; $column.number; ALP_Column_Enterable)
End if
$result:=New object("ok"; True; "value"; ""; "enabled"; Not($hidden); "editable"; ($column.typed | $column.checkbox) & Not($hidden | $protected) & ((AL_GetAreaLongProperty($area; ALP_Area_ReadOnly)%2)=0) & (New collection(1; 3; 5).indexOf($mode)>=0); "active"; False)
If ($hidden | $protected)
 return
End if
If ($column.value#Null)
 $semantic:=$column.value.call(Null; New object("key"; $state.rowKeys[$row-1]; "row"; $row; "column"; $column.number))
 If (Value type($semantic)#Is text)
  return New object("ok"; False)
 End if
 $result.value:=$semantic
Else
 If ($column.checkbox)
  $source:=$column.source
  If (Is nil pointer($source))
   return New object("ok"; False)
  End if
  If (($row<1) | ($row>Size of array($source->)))
   return New object("ok"; False)
  End if
  $checked:=Num($source->{$row})
  If ((AL_GetAreaLongProperty($area; ALP_Area_Selected)=1) & (AL_GetAreaLongProperty($area; ALP_Area_EntryInProgress)=1))
   If ((AL_GetAreaLongProperty($area; ALP_Area_EntryRow)=$row) & (AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)=$column.number))
    If (Type($source->)=Boolean array)
     $error:=AL_GetAreaPtrProperty($area; ALP_Area_EntryValue; ->$boolean)
     $checked:=Num($boolean)
    Else
     $error:=AL_GetAreaPtrProperty($area; ALP_Area_EntryValue; ->$checked)
    End if
    If ($error#0)
     return New object("ok"; False)
    End if
    $result.active:=True
   End if
  End if
  If (($checked<0) | ($checked>2))
   return New object("ok"; False)
  End if
  $result.role:="checkbox"
  $result.checked:=$checked
  $result.focusable:=$column.focusable
  $result.value:=String($checked)
 Else
  $result.value:=AL_GetCellTextProperty($area; $row; $column.number; ALP_Cell_FormattedValue)
  If (AL_GetColumnLongProperty($area; $column.number; ALP_Column_Attributed)#0)
   $result.value:=AL_GetPlainText($result.value)
  End if
 End if
End if
