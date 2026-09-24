#DECLARE($area : Integer; $keys : Pointer; $tableID : Text; $action : Object) -> $result : Object
var $index; $row; $error : Integer
var $known; $readback; $requested : Object
var $readbackCount : Integer
var $rowID : Text
ARRAY LONGINT($selected; 0)
ARRAY LONGINT($actual; 0)
$result:=New object("status"; "rejected"; "message"; "Grid action rejected")
If (($action.operation#"selectRows") | (Compare strings($action.node; $tableID; sk char codes)#0) | (Value type($action.value)#Is collection))
 return
End if
$known:=New object
For ($row; 1; Size of array($keys->))
 $rowID:=$tableID+"."+$keys->{$row}
 If (OB Is defined($known; $rowID))
  $result.message:="Duplicate stable row ID"
  return
 End if
 $known[$rowID]:=$row
End for
$requested:=New object
For each ($rowID; $action.value)
 If (OB Is defined($requested; $rowID))
  $result.message:="Duplicate requested row ID"
  return
 End if
 $requested[$rowID]:=True
 If (Not(OB Is defined($known; $rowID)))
  $result.message:="Row no longer exists"
  return
 End if
 APPEND TO ARRAY($selected; $known[$rowID])
End for each
$error:=AL_SetObjects($area; ALP_Object_Selection; $selected)
If ($error#0)
 $result.message:="AreaList Pro rejected selection"
 return
End if
$error:=AL_GetObjects($area; ALP_Object_Selection; $actual)
$readback:=New object
$readbackCount:=0
For ($index; 1; Size of array($actual))
 $row:=$actual{$index}
 If (($row>0) & ($row<=Size of array($keys->)))
  $readback[$tableID+"."+$keys->{$row}]:=True
  $readbackCount:=$readbackCount+1
 End if
End for
If (($error=0) & ($readbackCount=$action.value.length))
 $result.status:="completed"
 For each ($rowID; $action.value)
  If (Not(OB Is defined($readback; $rowID)))
   $result.status:="rejected"
  End if
 End for each
End if
$result.message:="AreaList selection "+$result.status+": "+String($readbackCount)+" row(s)"
If (($result.status="completed") & (Size of array($actual)>0))
 AL_SetRowLongProperty($area; $actual{1}; ALP_Row_Reveal; 0; 1)
End if
