// Viewport-safe view provider for classic DISPLAY SELECTION output forms (destination="listScreen").
// Publishes header-band controls interactively and a bounded list summary (<=100 rows)
// so large selections (tens of thousands of records) never flood AXChildren or stall the UI.
#DECLARE($operation : Text; $view : Object; $request : Object) -> $result : Object
var $meta; $discovered; $node; $col; $tableNode : Object
var $columns; $rows; $visible; $selected; $bodyCols : Collection
var $table; $ptr : Pointer
var $header; $body; $i; $left; $top; $right; $bottom; $winLeft; $winTop; $winRight; $winBottom : Integer
var $tableNum; $fieldNum; $totalRecords; $limit; $rowIdx; $rowHeight; $y; $selRec : Integer
var $name; $varName; $colLabel; $rowKey : Text
var $frames; $headers; $rowFrames : Object
ARRAY TEXT($objects; 0)
If ($operation="readGrid")
 $result:=New object("ok"; True; "pages"; New collection)
 If (($view.listScreenCols#Null) && ($view.listScreenColOrder#Null) && ($request#Null) && (Value type($request.requests)=Is collection))
  $table:=Current form table
  If (Not(Is nil pointer($table)))
   var $query; $pageObj; $es; $ent : Object
   var $pageRows; $cells : Collection
   var $rKey; $cId; $cellVal; $fieldName : Text
   var $start; $end; $first; $last; $r; $c : Integer
   $es:=Create entity selection($table->)
   For each ($query; $request.requests)
    If (($query.generation#$view.instance) | ($query.order#1))
     continue
    End if
    $start:=$query.row
    $end:=$start+$query.rowCount
    $first:=$query.column
    $last:=$first+$query.columnCount
    If (($start<0) | ($query.rowCount<1) | ($query.rowCount>16) | ($first<0) | ($last>$view.listScreenColOrder.length) | ($query.columnCount<1) | ($query.columnCount>8))
     continue
    End if
    $pageRows:=New collection
    For ($r; $start; $end-1)
     $rKey:=String($r+1)
     $cells:=New collection
     $ent:=Null
     If (($es#Null) && ($r<$es.length))
      $ent:=$es[$r]
     End if
     For ($c; $first; $last-1)
      $cId:=$view.listScreenColOrder[$c]
      $cellVal:=""
      $col:=$view.listScreenCols[$cId]
      If (($col#Null) & ($col.field>0) & ($ent#Null))
       $fieldName:=Field name($col.table; $col.field)
       If ($fieldName#"")
        $cellVal:=AXB_ControlValue($ent[$fieldName]; "")
       End if
      End if
      $cells.push(New object("column"; $cId; "value"; $cellVal; "editable"; False; "enabled"; True))
     End for
     $pageRows.push(New object("id"; $rKey; "cells"; $cells))
    End for
    $pageObj:=New object("node"; $query.node; "generation"; $view.instance; "order"; 1; "row"; $start; "column"; $first; "rows"; $pageRows)
    $result.pages.push($pageObj)
   End for each
  End if
 End if
 return
End if
If ($operation="apply")
 $result:=New object("status"; "rejected"; "message"; "Unsupported list screen action")
 If (($request#Null) && ($request.action#Null))
  If (($request.action.operation="gridSelect") && ($request.action.value#Null) && (Value type($request.action.value)=Is collection) && ($request.action.value.length=1))
   $table:=Current form table
   If (Not(Is nil pointer($table)))
    $rowIdx:=Num($request.action.value[0])
    If (($rowIdx>=1) & ($rowIdx<=Records in selection($table->)))
     GOTO SELECTED RECORD($table->; $rowIdx)
     $result:=New object("status"; "applied"; "message"; "")
    End if
   End if
   return
  End if
  $discovered:=AXB_Discover($view.options; $view.tabs; New collection(0; 0); Null; Null; Null; Null)
  $result:=AXB_ControlAction($request.action; $view.options; $view.tabs; New collection(0; 0); $discovered)
 End if
 return
End if
$result:=New object("ok"; True; "nodes"; New collection; "subforms"; New collection; "unsupported"; New collection)
If (Not(OB Is defined($view; "listScreenMeta")))
 $view.listScreenMeta:=AXB_FormStored("meta")
End if
$meta:=$view.listScreenMeta
$header:=0
$body:=0
If (($meta#Null) && (Value type($meta)=Is object))
 If (OB Is defined($meta; "header"))
  $header:=Num($meta.header)
 End if
 If (OB Is defined($meta; "body"))
  $body:=Num($meta.body)
 End if
End if
// Publish interactive header controls positioned above the body band.
If ($view.listScreenStatic=Null)
 $view.listScreenStatic:=New object("form"; Current form name; "types"; New object; "menus"; New object)
End if
$discovered:=AXB_Discover($view.options; New object; New collection(0; 0); Null; Null; Null; $view.listScreenStatic)
If (($discovered#Null) && ($discovered.ok=True))
 For each ($node; $discovered.nodes)
  If (($header<=0) | (($node.frame#Null) && ($node.frame.length>=4) && (($node.frame[1]+$node.frame[3])<=($header+4))))
   $result.nodes.push($node)
  End if
 End for each
End if
$table:=Current form table
If (Is nil pointer($table) | ($body<=$header))
 return
End if
$tableNum:=Table($table)
$rowHeight:=$body-$header
If ($rowHeight<12)
 $rowHeight:=18
End if
// Collect body-band objects as table columns sorted left-to-right.
$bodyCols:=New collection
FORM GET OBJECTS($objects; Form current page+Form inherited)
For ($i; 1; Size of array($objects))
 $name:=$objects{$i}
 If (Not(OBJECT Get visible(*; $name)))
  continue
 End if
 OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
 If (($right>$left) & ($bottom>$top) & ($top>=($header-2)) & ($bottom<=($body+4)))
  $ptr:=OBJECT Get pointer(Object named; $name)
  $varName:=""
  $fieldNum:=0
  If (Not(Is nil pointer($ptr)))
   RESOLVE POINTER($ptr; $varName; $tableNum; $fieldNum)
  End if
  $colLabel:=$name
  If (($fieldNum>0) & (Table($table)=$tableNum))
   $colLabel:=Field name($tableNum; $fieldNum)
  End if
  $bodyCols.push(New object("id"; $name; "label"; $colLabel; "left"; $left; "width"; $right-$left; "field"; $fieldNum; "table"; $tableNum))
 End if
End for
$bodyCols:=$bodyCols.orderBy("left asc")
GET WINDOW RECT($winLeft; $winTop; $winRight; $winBottom; Current form window)
$totalRecords:=Records in selection($table->)
// Hard cap at 100 rows so massive DISPLAY SELECTION sets (e.g. 90k records) stay fast and AX-safe.
$limit:=New collection($totalRecords; 100).min()
$columns:=New collection
$headers:=New object
$view.listScreenCols:=New object
$view.listScreenColOrder:=New collection
For each ($col; $bodyCols)
 $columns.push(New object("id"; $col.id; "label"; $col.label; "enabled"; True; "editable"; False))
 $view.listScreenCols[$col.id]:=$col
 $view.listScreenColOrder.push($col.id)
 If ($header>0)
  $headers[$col.id]:=New collection($col.left; 0; $col.width; $header)
 End if
End for each
$rows:=New collection
$visible:=New collection
$selected:=New collection
$frames:=New object
$selRec:=Selected record number($table->)
If ($limit>0)
 For ($rowIdx; 1; $limit)
  $rowKey:=String($rowIdx)
  $rows.push($rowKey)
  If ($rowIdx=$selRec)
   $selected.push($rowKey)
  End if
  $y:=$header+(($rowIdx-1)*$rowHeight)
  If ($y<($winBottom-$winTop))
   $visible.push($rowKey)
   $rowFrames:=New object
   For each ($col; $bodyCols)
    $rowFrames[$col.id]:=New collection($col.left; $y; $col.width; $rowHeight)
   End for each
   $frames[$rowKey]:=$rowFrames
  End if
 End for
End if
$tableNode:=New object(\
"id"; "listScreen."+Substring(Generate digest(Current form name; SHA256 digest); 1; 24); \
"objectName"; Current form name; \
"role"; "table"; \
"label"; Choose($totalRecords>$limit; $view.label+" (showing first "+String($limit)+" of "+String($totalRecords)+")"; $view.label); \
"value"; ""; \
"enabled"; True; \
"visible"; True; \
"focused"; False; \
"focusable"; True; \
"frame"; New collection(0; $header; New collection(100; $winRight-$winLeft).max(); New collection(100; ($winBottom-$winTop)-$header).max()); \
"grid"; New object(\
"generation"; $view.instance; \
"order"; 1; \
"rows"; $rows; \
"columns"; $columns; \
"selected"; $selected; \
"visible"; $visible; \
"frames"; $frames; \
"headers"; $headers; \
"disabled"; New collection; \
"unselectable"; New collection; \
"actions"; New object("select"; True; "reveal"; False; "edit"; False)))
$result.nodes.push($tableNode)
