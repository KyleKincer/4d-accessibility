// Convert a boundary between UTF-8 bytes and UTF-16 code units. Return -1
// for an offset inside a Unicode character or outside the text.
#DECLARE($text : Text; $position : Integer; $fromUTF8 : Boolean) -> $index : Integer
var $units; $bytes; $code; $next; $size; $width : Integer
$index:=-1
While ($units<=Length($text))
 If (($fromUTF8 & ($bytes=$position)) | (Not($fromUTF8) & ($units=$position)))
  If ($fromUTF8)
   return $units
  Else
   return $bytes
  End if
 End if
 If (($units=Length($text)) | ($fromUTF8 & ($bytes>$position)) | (Not($fromUTF8) & ($units>$position)))
  return
 End if
 $code:=Character code(Substring($text; $units+1; 1))
 $width:=1
 Case of
  : ($code<128)
   $size:=1
  : ($code<2048)
   $size:=2
  Else
   $size:=3
   If (($code>=55296) & ($code<=56319) & (($units+1)<Length($text)))
    $next:=Character code(Substring($text; $units+2; 1))
    If (($next>=56320) & ($next<=57343))
     $size:=4
     $width:=2
    End if
   End if
 End case
 $units:=$units+$width
 $bytes:=$bytes+$size
End while
