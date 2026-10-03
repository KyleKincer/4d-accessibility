// Caption formatting and row identity have separate contracts.
#DECLARE($value : Variant; $type : Integer) -> $result : Text
Case of
 : ($type=Text array)
  $result:=JSON Stringify(New collection($type; String($value)))
 : (($type=Integer array) | ($type=LongInt array))
  $result:=JSON Stringify(New collection($type; $value))
 : ($type=Date array)
  $result:=JSON Stringify(New collection($type; Year of($value); Month of($value); Day of($value)))
 : ($type=Time array)
  $result:=JSON Stringify(New collection($type; Num($value)))
 Else
  // Real serialization and additional caption types require separate evidence.
  $result:=""
End case
