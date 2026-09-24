var $position; $entryColumn; $value : Integer
var $checked : Boolean
$state.permissionPhase:=Form.left.permissionPhase
$state.columns:=New collection
For ($i; 1; AL_GetAreaLongProperty(Form.left.area; ALP_Area_Columns))
 $state.columns.push(New object("number"; $i; "source"; AL_GetColumnTextProperty(Form.left.area; $i; ALP_Column_Source); "title"; AL_GetColumnTextProperty(Form.left.area; $i; ALP_Column_HeaderText); "visible"; AL_GetColumnLongProperty(Form.left.area; $i; ALP_Column_Visible); "display"; AL_GetColumnLongProperty(Form.left.area; $i; ALP_Column_DisplayControl)))
End for
$position:=Find in array(aLeftKey; Choose(Type(aLeftKey)=Text array; "line-0600"; 600))
$state.leftControls:=New collection(aLeftDirect{$position}; aLeftFocusable{$position}; aLeftMixed{$position}; aLeftNumeric{$position})
$position:=Find in array(aRightKey; Choose(Type(aRightKey)=Text array; "line-0600"; 600))
$state.rightControls:=New collection(aRightDirect{$position}; aRightFocusable{$position}; aRightMixed{$position}; aRightNumeric{$position})
If (AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryInProgress)=1)
 $entryColumn:=AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryColumn)
 $state.editor:=New object("row"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryRow); "column"; $entryColumn; "object"; OBJECT Get name(Object with focus))
 If (New collection(8; 9).indexOf($entryColumn)>=0)
  $state.editor.error:=AL_GetAreaPtrProperty(Form.left.area; ALP_Area_EntryValue; ->$checked)
  $state.editor.checked:=Num($checked)
 End if
 If (New collection(10; 11).indexOf($entryColumn)>=0)
  $state.editor.error:=AL_GetAreaPtrProperty(Form.left.area; ALP_Area_EntryValue; ->$value)
  $state.editor.checked:=$value
 End if
End if
