// Existing application permission and validation controls for the fixture.
If (Form.permissionPhase=Null)
 Form.permissionPhase:=0
End if
Form.permissionPhase:=(Form.permissionPhase+1)%6
AL_SetAreaLongProperty(Form.area; ALP_Area_ReadOnly; Choose(Form.permissionPhase=1; 7; 6))
AL_SetCellLongProperty(Form.area; 600; 8; ALP_Cell_Enterable; Choose(Form.permissionPhase=2; 0; 1); 1; 1)
AL_SetColumnLongProperty(Form.area; 8; ALP_Column_Enterable; Choose(Form.permissionPhase=3; 0; 1); 1)
If (Form.permissionPhase=3)
 AL_SetCellLongProperty(Form.area; 600; 8; ALP_Cell_Enterable; -1; 1; 1)
End if
Form.reject:=(Form.permissionPhase=4)
