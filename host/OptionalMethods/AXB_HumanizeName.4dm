// Turn an icon filename or 4D dataSource expression into a readable control label.
// Returns "" when the input has no meaningful human-readable stem.
#DECLARE($raw : Text; $kind : Text) -> $label : Text
var $work; $ch; $prev; $out : Text
var $pos; $i; $code; $prevCode : Integer
$label:=""
$work:=AXB_Trim($raw)
If ($work="")
 return
End if
If ($kind="icon")
 // Take filename stem after the last "/" or ":".
 Repeat
  $pos:=Position("/"; $work)
  If ($pos>0)
   $work:=Substring($work; $pos+1)
  End if
 Until ($pos=0)
 Repeat
  $pos:=Position(":"; $work)
  If ($pos>0)
   $work:=Substring($work; $pos+1)
  End if
 Until ($pos=0)
 $pos:=Position("."; $work)
 If ($pos>1)
  $work:=Substring($work; 1; $pos-1)
 End if
Else
 // dataSource: strip [Table] prefix, Form. prefix, or pointer dereference.
 If (Position("["; $work)=1)
  $pos:=Position("]"; $work)
  If ($pos>0)
   $work:=Substring($work; $pos+1)
  End if
 End if
 If (Position("Form."; $work)=1)
  $work:=Substring($work; 6)
 End if
 If (Position("This."; $work)=1)
  $work:=Substring($work; 6)
 End if
 If (Position("<>"; $work)=1)
  $work:=Substring($work; 3)
 End if
 // Keep final segment of dotted paths (e.g. Form.customer.firstName -> firstName).
 Repeat
  $pos:=Position("."; $work)
  If ($pos>0)
   $work:=Substring($work; $pos+1)
  End if
 Until ($pos=0)
End if
// Strip common Hungarian / UI prefixes when followed by an uppercase letter or underscore.
If (Match regex("^(btn|b|pict|pic|img|ico|icon|txt|lbl|fld|cb|chk|rb|pop|dd|at|al|ab|ar|ad|ai|v|r|t|l|f)_+"; $work))
 $work:=Replace string($work; "_"; " "; 1)
 $pos:=Position(" "; $work)
 If ($pos>0)
  $work:=Substring($work; $pos+1)
 End if
Else
 If ((Length($work)>=3) & (Position(Substring($work; 1; 1); "vbrtpfl")>0) & (Character code(Substring($work; 2; 1))>=65) & (Character code(Substring($work; 2; 1))<=90))
  $work:=Substring($work; 2)
 End if
End if
// Replace underscores/hyphens with spaces and split camelCase boundaries.
$work:=Replace string($work; "_"; " ")
$work:=Replace string($work; "-"; " ")
$out:=""
$prev:=""
For ($i; 1; Length($work))
 $ch:=Substring($work; $i; 1)
 $code:=Character code($ch)
 $prevCode:=Choose($prev=""; 0; Character code($prev))
 If (($prev#"") & ($prev#" ") & ($code>=65) & ($code<=90) & ($prevCode>=97) & ($prevCode<=122))
  $out:=$out+" "
 End if
 $out:=$out+$ch
 $prev:=$ch
End for
$out:=AXB_Trim($out)
While (Position("  "; $out)>0)
 $out:=Replace string($out; "  "; " ")
End while
// Ignore meaningless purely numeric or single-character stems.
If ((Length($out)<2) | Not(Match regex(".*[[:alpha:]].*"; $out)))
 return
End if
$label:=Uppercase(Substring($out; 1; 1))+Substring($out; 2)
