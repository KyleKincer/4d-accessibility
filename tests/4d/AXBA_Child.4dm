LinePicker_Form
If (Form event code=On Load)
 // Use the exact documented adapter, with fixture-only observation wrappers.
 Form.axbView.describe:=Formula(AXBA_Describe)
 Form.axbView.apply:=Formula(AXBA_Apply($1))
 Form.nativeEvents:=0
 // Prove the existing human cell editor still works alongside AX selection.
 AL_SetAreaLongProperty(Form.area; ALP_Area_ReadOnly; 6)
 AL_SetAreaLongProperty(Form.area; ALP_Area_EntryClick; 2)
 AL_SetColumnLongProperty(Form.area; 1; ALP_Column_Enterable; 0)
 AL_SetColumnLongProperty(Form.area; 2; ALP_Column_Enterable; 1)
 AL_SetColumnLongProperty(Form.area; 3; ALP_Column_Enterable; 0)
End if
