// Only this private process changes its record selection. No application
// formula, renderer, controller or form method runs here.
#DECLARE($reply : Object)
var $table; $pointer : Pointer
var $source; $value : Variant
var $selected; $item; $field : Object
var $row : Integer
ARRAY LONGINT($records; 0)
AXB_SelectionWorkerReply:=$reply
ON ERR CALL("AXB_SelectionError")
$table:=Table($reply.table)
READ ONLY($table->)
COLLECTION TO ARRAY($reply.records; $records)
CREATE SELECTION FROM ARRAY($table->; $records)
If ($reply.readFields=Null)
 $source:=Create entity selection($table->)
 $source.refresh()
Else
 $source:=New shared collection
 For ($row; 1; Records in selection($table->))
  GOTO SELECTED RECORD($table->; $row)
  $item:=New shared object
  Use ($item)
   For each ($field; $reply.readFields)
    $pointer:=Field($reply.table; $field.field)
    $value:=$pointer->
    $item[$field.name]:=$value
   End for each
  End use
  Use ($source)
   $source.push($item)
  End use
 End for
End if
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
 If ($reply.readFields=Null)
  $reply.source:=$source.copy(ck shared)
 Else
  $reply.source:=$source.copy(ck shared; $reply)
 End if
 $reply.selected:=$selected
 $reply.done:=True
End use
