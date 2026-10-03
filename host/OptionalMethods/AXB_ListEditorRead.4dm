// Run inside the real list row. Never load a record or assign a field.
#DECLARE($request : Object) -> $result : Object
var $table : Pointer
var $start; $end : Integer
$result:=New object("active"; False)
$table:=Table($request.table)
If ((Current form name#$request.form) | Not(Is record loaded($table->)) | (Record number($table->)#$request.record) | Not(Is editing text) | (OBJECT Get name(Object with focus)#$request.column))
 return
End if
If (Not(OBJECT Get enterable(*; $request.column)) | Not(OBJECT Get enabled(*; $request.column)) | Not(OBJECT Get visible(*; $request.column)) | (OBJECT Get font(*; $request.column)="%password") | OBJECT Is styled text(*; $request.column))
 return
End if
// HIGHLIGHT TEXT addresses the template field rather than this list overlay.
// Return its actual selection; AXB_TextAction uses verified native navigation
// when the requested selection differs, preserving ordinary key handlers.
GET HIGHLIGHT(*; $request.column; $start; $end)
$result:=New object("active"; True; "start"; $start; "end"; $end; "text"; Get edited text)
