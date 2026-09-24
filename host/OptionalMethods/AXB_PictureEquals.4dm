// Formula-friendly pixel comparison. The mask is temporary bridge data;
// preserve OK so describing an image cannot affect application command state.
#DECLARE($picture : Picture; $reference : Picture) -> $equal : Boolean
var $mask : Picture
var $savedOK : Integer
$savedOK:=OK
$equal:=Equal pictures($picture; $reference; $mask)
OK:=$savedOK
