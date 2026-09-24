// Confirm the actual vendor editor before reading or selecting its text.
// No array assignment or synthetic business callback is used for text entry.
#DECLARE($cell : Object; $operation : Text; $selection : Collection) -> $result : Object
var $state; $column : Object
var $pointer; $focused : Pointer
var $area; $row; $mode; $start; $end : Integer
var $text : Text
$result:=New object("active"; False)
$state:=$cell.state
If (Not($state.valid=True) | ($state.generation#$cell.generation))
 return
End if
If (Not(OB Is defined($state.positions; $cell.row)) | Not(OB Is defined($state.columns; $cell.column)))
 return
End if
$pointer:=OBJECT Get pointer(Object named; $cell.objectName)
$focused:=OBJECT Get pointer(Object with focus)
If (Is nil pointer($pointer) | Is nil pointer($focused))
 return
End if
$area:=$state.area
If (($pointer#$focused) | ($pointer->#$area) | Not(OBJECT Get enabled(*; $cell.objectName)) | Not(OBJECT Get visible(*; $cell.objectName)))
 return
End if
If ((AL_GetAreaLongProperty($area; ALP_Area_Selected)#1) | (AL_GetAreaLongProperty($area; ALP_Area_EntryInProgress)#1) | ((AL_GetAreaLongProperty($area; ALP_Area_ReadOnly)%2)#0))
 return
End if
$row:=$state.positions[$cell.row]
$column:=$state.columns[$cell.column]
If ((AL_GetAreaLongProperty($area; ALP_Area_EntryRow)#$row) | (AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)#$column.number) | (AL_GetCellLongProperty($area; $row; $column.number; ALP_Cell_Invisible)#0))
 return
End if
// The vendor's password format also applies inside its editor. Never read
// EntryText for a protected cell, even when the user focused it directly.
If (AL_GetCellTextProperty($area; $row; $column.number; ALP_Cell_FormatResolved)=Char(8226))
 return
End if
$mode:=AL_GetCellLongProperty($area; $row; $column.number; ALP_Cell_Enterable)
If ($mode=-1)
 $mode:=AL_GetColumnLongProperty($area; $column.number; ALP_Column_Enterable)
End if
If (Not($column.typed) | (New collection(1; 3; 5).indexOf($mode)<0))
 return
End if
$text:=AL_GetAreaTextProperty($area; ALP_Area_EntryText)
If ($operation="select")
 $start:=AXB_TextIndex($text; $selection[0]-1; False)
 $end:=AXB_TextIndex($text; $selection[1]-1; False)
 If (($start<0) | ($end<$start))
  return
 End if
 AL_SetAreaTextProperty($area; ALP_Area_EntryHighlight; String($start+1)+","+String($end+1))
 If ((AL_GetAreaLongProperty($area; ALP_Area_EntryInProgress)#1) | (AL_GetAreaLongProperty($area; ALP_Area_EntryRow)#$row) | (AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)#$column.number))
  return
 End if
End if
$start:=AXB_TextIndex($text; AL_GetAreaLongProperty($area; ALP_Area_EntryHighlightS)-1; True)
$end:=AXB_TextIndex($text; AL_GetAreaLongProperty($area; ALP_Area_EntryHighlightE)-1; True)
If (($start<0) | ($end<$start))
 return
End if
$result:=New object("active"; True; "text"; $text; "start"; $start+1; "end"; $end+1)
