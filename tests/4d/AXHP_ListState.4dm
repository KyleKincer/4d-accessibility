#DECLARE($name : Text) -> $state : Object
var $i; $count; $ref; $child; $current; $scroll : Integer
var $label : Text
var $expanded : Boolean
var $appearance; $icon; $lineHeight; $doubleClick; $multiple; $editable : Integer
ARRAY LONGINT($selected; 0)
$count:=Count list items(*; $name)
$state:=New object("count"; $count; "total"; Count list items(*; $name; *); "rows"; New collection)
For ($i; 1; $count)
 GET LIST ITEM(*; $name; $i; $ref; $label; $child; $expanded)
 $state.rows.push(New object("position"; $i; "ref"; $ref; "label"; $label; "child"; $child; "expanded"; $expanded; "parent"; List item parent(*; $name; $ref)))
End for
$current:=Selected list items(*; $name; $selected; *)
$state.selected:=New collection
ARRAY TO COLLECTION($state.selected; $selected)
$state.currentSelectedReference:=$current
GET LIST ITEM(*; $name; *; $ref; $label; $child; $expanded)
$state.current:=$ref
OBJECT GET SCROLL POSITION(*; $name; $scroll)
$state.scroll:=$scroll
GET LIST PROPERTIES(Form.tree; $appearance; $icon; $lineHeight; $doubleClick; $multiple; $editable)
$state.properties:=New object("appearance"; $appearance; "icon"; $icon; "minimumLineHeight"; $lineHeight; "doubleClick"; $doubleClick; "multiple"; $multiple; "editable"; $editable)
