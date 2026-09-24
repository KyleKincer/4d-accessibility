var $name : Text
$name:=OBJECT Get name(Object current)
Case of
 : ($name="Sort")
  AL_SetAreaLongProperty(Form.left.area; ALP_Area_SortList; -7)
 : ($name="Bottom")
  AL_SetRowLongProperty(Form.left.area; 600; ALP_Row_Reveal; 0; 1)
 : ($name="Top")
  AL_SetRowLongProperty(Form.left.area; 1; ALP_Row_Reveal; 0; 1)
 : ($name="Scope")
  Form.left.scope:=Generate UUID
 : ($name="Hide")
  OBJECT SET VISIBLE(*; "Left"; Not(OBJECT Get visible(*; "Left")))
 : ($name="Loading")
  Form.left.ready:=Not(Form.left.ready)
 : ($name="Edit")
  EXECUTE METHOD IN SUBFORM("Left"; "AXBP_Enter")
End case
AXBP_State
