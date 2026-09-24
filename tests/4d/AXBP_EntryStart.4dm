// Existing application callback, independent of accessibility integration.
#DECLARE($area : Integer; $cause : Integer; $record : Integer)
If ($area=AXBP_LeftData.area)
 AXBP_LeftData.starts:=AXBP_LeftData.starts+1
Else
 AXBP_RightData.starts:=AXBP_RightData.starts+1
End if
