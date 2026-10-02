// Only this private process changes its record selection. No application
// formula, renderer, controller or form method runs here.
#DECLARE($reply : Object)
var $table : Pointer
var $source : 4D.EntitySelection
var $selected : Object
var $row : Integer
ARRAY LONGINT($records; 0)
AXB_SelectionWorkerReply:=$reply
ON ERR CALL("AXB_SelectionError")
$table:=Table($reply.table)
READ ONLY($table->)
COLLECTION TO ARRAY($reply.records; $records)
CREATE SELECTION FROM ARRAY($table->; $records)
$source:=Create entity selection($table->)
$source.refresh()
$selected:=New shared object
If ($reply.highlight#"")
 USE SET($reply.highlight)
 LONGINT ARRAY FROM SELECTION($table->; $records)
 Use ($selected)
  For ($row; 1; Size of array($records))
   $selected[String($records{$row})]:=True
  End for
 End use
 CLEAR SET($reply.highlight)
End if
Use ($reply)
 $reply.highlight:=""
 $reply.source:=$source.copy(ck shared)
 $reply.selected:=$selected
 $reply.done:=True
End use
