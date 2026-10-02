// Read a private text copy, never the application's bound variable or editor.
// URL labels can be read here. 4D references need their original render context.
#DECLARE($text : Text) -> $result : Object
var $savedOK; $content : Integer
var $hyphen; $referencePattern : Text
var $reference : Boolean
$savedOK:=OK
OK:=1
$result:=New object("ok"; False; "text"; ""; "references"; False)
// Parsing a fresh copy can evaluate an embedded 4D method, even when the
// requested output mode omits expression values. Require its rendered context.
$reference:=Position("-d4-ref"; Lowercase($text))>0
If (Not($reference) && (Position("&"; $text)>0))
 // 4D decodes XML entities before recognizing its reference property. Match
 // both cases and numeric encodings without invoking the styled-text parser.
 $hyphen:="(?:-|&#0*45;|&#x0*2d;|&hyphen;|&dash;)"
 $referencePattern:="(?i)"+$hyphen+"(?:d|&#0*(?:68|100);|&#x0*(?:44|64);)(?:4|&#0*52;|&#x0*34;)"+$hyphen
 $referencePattern:=$referencePattern+"(?:r|&#0*(?:82|114);|&#x0*(?:52|72);)(?:e|&#0*(?:69|101);|&#x0*(?:45|65);)(?:f|&#0*(?:70|102);|&#x0*(?:46|66);)"
 $reference:=Match regex($referencePattern; $text; 1)
End if
If ($reference)
 $result.ok:=True
 $result.references:=True
 $result.requiresRenderedValue:=True
 OK:=$savedOK
 return
End if
$content:=ST Get content type($text; ST Start text; ST End text)
If (OK=1)
 $result.references:=$content#ST Plain type
 // Do not evaluate embedded application expressions while inspecting text.
 // Their displayed values require a provider with the original render context.
 $result.text:=ST Get plain text($text; ST URL as labels+ST User links as labels+ST Tags as plain text)
 $result.ok:=OK=1
End if
OK:=$savedOK
