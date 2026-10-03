// This runs inside the row after 4D's native EDIT ITEM event cycle.
#DECLARE($request : Object) -> $result : Object
var $table : Pointer
$result:=New object("ok"; False)
$table:=Table($request.table)
If ((Current form name#$request.form) | Not(Is record loaded($table->)) | (Record number($table->)#$request.record) | Not(Is editing text))
 return
End if
If (Not(OBJECT Get visible(*; $request.column)) | Not(OBJECT Get enabled(*; $request.column)) | Not(OBJECT Get enterable(*; $request.column)) | (OBJECT Get type(*; $request.column)#Object type text input) | OBJECT Is styled text(*; $request.column) | (OBJECT Get font(*; $request.column)="%password"))
 return
End if
GOTO OBJECT(*; $request.column)
$result.ok:=True
