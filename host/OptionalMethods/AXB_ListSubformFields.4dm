// Inspect the list's real body controls without loading a record or evaluating
// a data-source expression. The parent passes only its verified table and form.
#DECLARE($request : Object) -> $result : Object
var $name; $variable; $property; $label : Text
var $position; $table; $field; $fieldType; $type; $left; $top; $right; $bottom; $x; $y; $end : Integer
var $column; $metadata; $caption : Object
var $captions; $matches : Collection
var $liveValue : Variant
var $pointer; $recordTable : Pointer
ARRAY TEXT($names; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; False; "columns"; New collection; "unsupported"; New collection)
If (Current form name#$request.form)
 return
End if
FORM GET OBJECTS($names; $variables; $pages; Form current page+Form inherited)
$x:=0
$y:=0
CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
$result.origin:=New collection($x; $y)
$recordTable:=Table($request.table)
$captions:=New collection
For ($position; 1; Size of array($names))
 $name:=$names{$position}
 If ((OBJECT Get type(*; $name)=Object type static text) && OBJECT Get visible(*; $name))
  OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
  $label:=OBJECT Get title(*; $name)
  If (($top>=0) & ($bottom<=$request.header) & ($label#""))
   $captions.push(New object("label"; $label; "left"; $left))
  End if
 End if
End for
$result.liveValues:=New object("record"; -1; "values"; New object)
If (Is record loaded($recordTable->))
 $result.liveValues.record:=Record number($recordTable->)
End if
For ($position; 1; Size of array($names))
 $name:=$names{$position}
 If (Not(OBJECT Get visible(*; $name)))
  continue
 End if
 OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
 $type:=OBJECT Get type(*; $name)
 If (($right<=$left) | ($bottom<=$top))
  continue
 End if
 If (($bottom<=$request.header) | ($top>=$request.body))
  If (New collection(Object type static text; Object type line; Object type rectangle; Object type rounded rectangle; Object type oval).indexOf($type)<0)
   $result.unsupported.push(New object("column"; $name; "reason"; "listSubformHeaderFooterControlPending"))
  End if
  continue
 End if
 If (New collection(Object type line; Object type rectangle; Object type rounded rectangle; Object type oval).indexOf($type)>=0)
  continue
 End if
 $metadata:=New object
 If (($request.options.columns#Null) && ($request.options.columns[$name]#Null))
  $metadata:=$request.options.columns[$name]
 End if
 If ($metadata.decorative=True)
  continue
 End if
 If (New collection(Object type text input; Object type checkbox; Object type 3D checkbox).indexOf($type)<0)
  $result.unsupported.push(New object("column"; $name; "reason"; "listSubformControlPending"))
  continue
 End if
 If (($type=Object type text input) && OBJECT Is styled text(*; $name))
  $result.unsupported.push(New object("column"; $name; "reason"; "listSubformStyledTextPending"))
  continue
 End if
 $pointer:=$variables{$position}
 $table:=0
 $field:=0
 $property:=""
 If (Not(Is nil pointer($pointer)))
  RESOLVE POINTER($pointer; $variable; $table; $field)
  If (($table=$request.table) & ($field>0))
   $property:=Field name($table; $field)
  End if
 End if
 $fieldType:=-1
 If (($property#"") & ($metadata.value=Null))
  GET FIELD PROPERTIES($table; $field; $fieldType)
  If (New collection(Is alpha field; Is text; Is real; Is integer; Is longint; Is integer 64 bits; Is date; Is time; Is Boolean).indexOf($fieldType)<0)
   $result.unsupported.push(New object("column"; $name; "reason"; "gridValueDescriptionRequired"))
   continue
  End if
 End if
 If (($property="") & ($metadata.value=Null))
  $result.unsupported.push(New object("column"; $name; "reason"; "gridValueDescriptionRequired"))
  continue
 End if
 $label:=""
 If ($type#Object type text input)
  $label:=OBJECT Get title(*; $name)
 End if
 $matches:=New collection
 For each ($caption; $captions)
  If (Abs($caption.left-$left)<=4)
   $matches.push($caption)
  End if
 End for each
 If (($label="") & ($matches.length=1))
  $label:=$matches[0].label
 End if
 If ($label="")
  $label:=$property
 End if
 If ($metadata.label#Null)
  $label:=$metadata.label
 End if
 If ($label="")
  $label:=$name
 End if
 If (Length($label)>512)
  $end:=512
  If (AXB_TextIndex($label; $end; False)<0)
   $end:=$end-1
  End if
  $label:=Substring($label; 1; $end)
 End if
 $column:=New object("name"; $name; "id"; $name; "label"; $label; "property"; $property; "format"; OBJECT Get format(*; $name); "protected"; OBJECT Get font(*; $name)="%password"; "enabled"; OBJECT Get enabled(*; $name); "nativeEditable"; OBJECT Get enterable(*; $name); "editable"; False; "frame"; New collection($left; $top; $right-$left; $bottom-$top))
 $column.value:=$metadata.value
 $column.hasHeader:=($request.header>0) & ($matches.length=1)
 $column.fieldNumber:=$field
 $column.fieldType:=$fieldType
 If (($property#"") & ($result.liveValues.record>=0) & Not($column.protected))
  $liveValue:=$pointer->
  If (($liveValue=Null) || (New collection(Is text; Is real; Is integer; Is longint; Is date; Is time; Is Boolean).indexOf(Value type($liveValue))>=0))
   $result.liveValues.values[$name]:=$liveValue
  End if
 End if
 $column.automationKey:=Choose($metadata.automationKey=Null; $name; $metadata.automationKey)
 $column.display:=lk three states checkbox
 $column.controlRole:="checkbox"
 If ($type=Object type text input)
  $column.display:=lk numeric format
  $column.controlRole:="text"
  $column.multiline:=OBJECT Get multiline(*; $name)=Multiline Yes
 Else
  $column.threeStates:=OBJECT Get three states checkbox(*; $name)
 End if
 $result.columns.push($column)
End for
$result.ok:=True
