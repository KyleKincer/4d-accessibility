// Read bounded value pages from a freshly verified provider state. Inspection
// never selects, reveals, enters an editor or evaluates a source expression.
#DECLARE($state : Object; $requests : Collection) -> $result : Object
var $descriptor; $query; $definition; $column; $value; $cell : Object
var $rows; $cells : Collection
var $key; $columnID : Text
var $start; $end; $first; $last; $r; $c; $position : Integer
$result:=New object("ok"; True; "pages"; New collection; "status"; "rejected"; "message"; "Grid changed before the request")
If (Not($state.valid=True))
 return
End if
$descriptor:=$state.descriptor
For each ($query; $requests)
 If (($query.generation#$descriptor.generation) | ($query.order#$descriptor.order))
  continue
 End if
 $start:=$query.row
 $end:=$start+$query.rowCount
 $first:=$query.column
 $last:=$first+$query.columnCount
 If (($start<0) | ($end>$descriptor.rows.length) | ($query.rowCount<1) | ($query.rowCount>16) | ($first<0) | ($last>$descriptor.columns.length) | ($query.columnCount<1) | ($query.columnCount>8))
  return
 End if
 $rows:=New collection
 For ($r; $start; $end-1)
  $key:=$descriptor.rows[$r]
  $position:=$state.positions[$key]
  $cells:=New collection
  For ($c; $first; $last-1)
   $definition:=$descriptor.columns[$c]
   $columnID:=$definition.id
   $column:=$state.columns[$columnID]
   $value:=AXB_GridValue($state; $column; $position)
   $cell:=New object("column"; $columnID; "value"; $value.value; "enabled"; $value.ok & $definition.enabled & $value.enabled & (AXB_KeyIndex($descriptor.disabled; $key)<0); "editable"; $value.editable & $definition.editable & (AXB_KeyIndex($descriptor.uneditable; $key)<0))
   If ($value.role#Null)
    $cell.role:=$value.role
    If ($value.checked#Null)
     $cell.checked:=$value.checked
    End if
    If ($value.label#Null)
     $cell.label:=$value.label
    End if
   End if
   $cells.push($cell)
  End for
  $rows.push(New object("id"; $key; "cells"; $cells))
 End for
 $result.pages.push(New object("node"; $query.node; "generation"; $descriptor.generation; "order"; $descriptor.order; "row"; $start; "column"; $first; "rows"; $rows))
End for each
