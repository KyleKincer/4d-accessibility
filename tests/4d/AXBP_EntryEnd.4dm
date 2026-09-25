// Existing application validation. AreaList writes the array before asking
// this callback whether the user may leave the cell.
#DECLARE($area : Integer; $cause : Integer) -> $accepted : Boolean
var $data : Object
var $row : Integer
$accepted:=True
If ($area=AXBP_LeftData.area)
 $data:=AXBP_LeftData
Else
 $data:=AXBP_RightData
End if
$data.ends:=$data.ends+1
$data.lastCause:=$cause
If (($area=AXBP_LeftData.area) & ($cause#AL Esc key action))
 $row:=AL_GetAreaLongProperty($area; ALP_Area_EntryRow)
 If ((AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)=2) & ($row>0))
  If (aLeftDescription{$row}="REJECT")
   $data.rejections:=$data.rejections+1
   aLeftDescription{$row}:=aLeftDescription{0}
   $accepted:=False
  End if
  If (aLeftDescription{$row}="CHANGE SCOPE")
   $data.scope:=Generate UUID
  End if
 End if
End if
