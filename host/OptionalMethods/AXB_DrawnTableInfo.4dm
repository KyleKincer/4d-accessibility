// The columns of a list box that no grid adapter describes, as the native plugin reads the
// rows 4D draws: each column's title, width and visibility, and the title band's height.
#DECLARE($name : Text) -> $info : Object
var $i : Integer
var $header : Text
var $columns : Collection
ARRAY TEXT($columnNames; 0)
ARRAY TEXT($headerNames; 0)
ARRAY POINTER($columnVariables; 0)
ARRAY POINTER($headerVariables; 0)
ARRAY BOOLEAN($visible; 0)
ARRAY POINTER($styles; 0)
LISTBOX GET ARRAYS(*; $name; $columnNames; $headerNames; $columnVariables; $headerVariables; $visible; $styles)
$columns:=New collection
For ($i; 1; Size of array($columnNames))
 $header:=""
 If ($headerNames{$i}#"")
  $header:=OBJECT Get title(*; $headerNames{$i})
 End if
 $columns.push(New object("header"; $header; "width"; LISTBOX Get column width(*; $columnNames{$i}); "hidden"; Not($visible{$i})))
End for
$info:=New object("columns"; $columns; "headerHeight"; LISTBOX Get headers height(*; $name); "showHeaders"; LISTBOX Get property(*; $name; lk display header)=1)
