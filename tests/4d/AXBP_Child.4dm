// Ordinary vendor initialization. No accessibility registration in the child.
var $pointer : Pointer
var $prefix : Text
var $error : Integer
ARRAY LONGINT($hidden; 600)
If (Form event code=On Load)
 $pointer:=OBJECT Get pointer(Object named; "Items")
 Form.area:=$pointer->
 Form.events:=0
 Form.selections:=0
 Form.starts:=0
 Form.ends:=0
 Form.rejections:=0
 $prefix:="a"+Form.side
 $error:=AL_SetArraysNam(Form.area; 1; 1; $prefix+"Item")
 $error:=AL_SetArraysNam(Form.area; 2; 1; $prefix+"Description")
 $error:=AL_SetArraysNam(Form.area; 3; 1; $prefix+"Amount")
 $error:=AL_SetArraysNam(Form.area; 4; 1; $prefix+"Styled")
 $error:=AL_SetArraysNam(Form.area; 5; 1; $prefix+"Picture")
 $error:=AL_SetArraysNam(Form.area; 6; 1; $prefix+"Spacer")
 $error:=AL_SetArraysNam(Form.area; 7; 1; $prefix+"Key")
 AL_SetHeaders(Form.area; 1; 1; "Item")
 AL_SetHeaders(Form.area; 2; 1; "Description")
 AL_SetHeaders(Form.area; 3; 1; "Amount")
 AL_SetHeaders(Form.area; 4; 1; "Styled")
 AL_SetHeaders(Form.area; 5; 1; "R")
 AL_SetWidths(Form.area; 1; 1; 100)
 AL_SetWidths(Form.area; 2; 1; 280)
 AL_SetWidths(Form.area; 3; 1; 120)
 AL_SetWidths(Form.area; 4; 1; 160)
 AL_SetWidths(Form.area; 5; 1; 60)
 AL_SetWidths(Form.area; 6; 1; 30)
 AL_SetColumnLongProperty(Form.area; 4; ALP_Column_Attributed; 1)
 AL_SetColumnLongProperty(Form.area; 4; ALP_Column_Enterable; 0)
 AL_SetColumnLongProperty(Form.area; 5; ALP_Column_Enterable; 0)
 AL_SetAreaLongProperty(Form.area; ALP_Area_CompHideCols; 1)
 AL_SetAreaLongProperty(Form.area; ALP_Area_SelType; 0)
 AL_SetAreaLongProperty(Form.area; ALP_Area_SelMultiple; 1)
 AL_SetAreaLongProperty(Form.area; ALP_Area_SelNone; 1)
 AL_SetAreaTextProperty(Form.area; ALP_Area_CallbackMethEntryStart; "AXBP_EntryStart")
 AL_SetAreaTextProperty(Form.area; ALP_Area_CallbackMethEntryEnd; "AXBP_EntryEnd")
 AL_SetAreaLongProperty(Form.area; ALP_Area_ReadOnly; 6)
 AL_SetAreaLongProperty(Form.area; ALP_Area_EntryClick; 2)
 AL_SetColumnLongProperty(Form.area; 1; ALP_Column_Enterable; 0)
 AL_SetColumnLongProperty(Form.area; 2; ALP_Column_Enterable; 1)
 AL_SetColumnLongProperty(Form.area; 3; ALP_Column_Enterable; 0)
 AL_SetColumnTextProperty(Form.area; 3; ALP_Column_Format; "###,##0.00"; 1)
 AL_SetCellLongProperty(Form.area; 5; 2; ALP_Cell_Invisible; 1; 1; 1)
 AL_SetCellTextProperty(Form.area; 7; 2; ALP_Cell_Format; Char(8226); 1; 1)
 $hidden{2}:=1
 $error:=AL_SetObjects(Form.area; ALP_Object_RowHide; $hidden)
End if
