// Existing fixture action opens a protected vendor editor without using AX.
GOTO OBJECT(*; "Items")
AL_SetAreaTextProperty(Form.area; ALP_Area_EntryGotoCell; "7,2")
