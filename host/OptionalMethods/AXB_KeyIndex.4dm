// Accessibility identities are exact strings. Collection.indexOf uses 4D's
// text equality, which also matches case/accent variants and @ wildcards.
#DECLARE($keys : Collection; $key : Text) -> $index : Integer
For ($index; 0; $keys.length-1)
 If (Compare strings($keys[$index]; $key; sk char codes)=0)
  return
 End if
End for
$index:=-1
