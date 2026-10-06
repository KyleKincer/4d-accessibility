// A classic hierarchical list as a logical outline. Items are keyed by their
// list reference; selection and disclosure use 4D's own keyboard handling, so
// the list's normal events run.
#DECLARE($operation : Text; $options : Object; $state : Object; $request : Object) -> $result : Object
var $node; $reply; $descriptor; $outline; $frames; $positions; $levels; $texts; $known; $item; $data; $query; $cell : Object
var $rows; $selected; $visible; $rowLayout; $pageRows; $cells; $chain : Collection
var $name; $key; $parentKey : Text
var $list; $ref; $sub; $parent; $i; $count; $level; $first; $lineHeight; $left; $top; $right; $bottom; $start; $end; $r : Integer
var $appearance; $icon; $doubleClick; $multi; $editable : Integer
var $text : Text
var $expanded; $duplicate : Boolean
var $y : Real
ARRAY LONGINT($selection; 0)
$name:=$options.objectName
$result:=New object("ok"; True; "nodes"; New collection; "pages"; New collection; "unsupported"; New collection; "status"; "rejected"; "message"; "Hierarchical list changed before the request")
If ($operation="readGrid")
 If (Not($state.valid=True))
  return
 End if
 $descriptor:=$state.descriptor
 For each ($query; $request.requests)
  If (($query.generation#$descriptor.generation) | ($query.order#$descriptor.order))
   continue
  End if
  $start:=$query.row
  $end:=$start+$query.rowCount
  If (($start<0) | ($end>$descriptor.rows.length) | ($query.rowCount<1) | ($query.rowCount>16) | ($query.column#0) | ($query.columnCount#1))
   return
  End if
  $pageRows:=New collection
  For ($r; $start; $end-1)
   $key:=$descriptor.rows[$r]
   $cells:=New collection(New object("column"; "item"; "value"; $state.texts[$key]; "enabled"; True; "editable"; False; "role"; "text"))
   $pageRows.push(New object("id"; $key; "cells"; $cells))
  End for
  $result.pages.push(New object("node"; $query.node; "generation"; $descriptor.generation; "order"; $descriptor.order; "row"; $start; "column"; 0; "rows"; $pageRows))
 End for each
 return
End if
If ($operation="apply")
 // Recheck the live list before any click can run an application handler.
 $reply:=AXB_HList("describe"; $options; $state; New object)
 If (Not($state.valid=True) | (Current form window#Frontmost window) | Not(OBJECT Get enabled(*; $name)))
  return
 End if
 $descriptor:=$state.descriptor
 Case of
  : ($request.action.operation="gridSelect")
   // A row's selected setter adds to the current selection; in a single-selection
   // list the request is the one item it adds.
   $key:=""
   For each ($parentKey; $request.action.value)
    If (Not(OB Is defined($state.positions; $parentKey)))
     return
    End if
    If (AXB_KeyIndex($descriptor.selected; $parentKey)<0)
     If ($key#"")
      $result.message:="Select one list item at a time"
      return
     End if
     $key:=$parentKey
    End if
   End for each
   If ($key="")
    If ($request.action.value.length=$descriptor.selected.length)
     return New object("status"; "completed"; "message"; "List item already selected")
    End if
    $result.message:="A list item cannot be deselected through accessibility"
    return
   End if
   $data:=New object("options"; $options; "state"; $state; "action"; $request.action; "generation"; $descriptor.generation; "kind"; "select"; "target"; $key; "deadline"; Milliseconds+3000)
   return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
  : ($request.action.operation="gridSetExpanded")
   $key:=$request.action.value.row
   If (Not(OB Is defined($state.positions; $key)) || ($descriptor.outline[$key].kind#"group"))
    return
   End if
   If ($descriptor.outline[$key].expanded=($request.action.value.expanded=True))
    return New object("status"; "completed"; "message"; Choose($request.action.value.expanded=True; "List item already expanded"; "List item already collapsed"))
   End if
   $data:=New object("options"; $options; "state"; $state; "action"; $request.action; "generation"; $descriptor.generation; "kind"; "disclose"; "target"; $key; "expanded"; $request.action.value.expanded=True; "deadline"; Milliseconds+4000)
   return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
  : ($request.action.operation="gridReveal")
   $key:=$request.action.value.row
   If (($request.action.value.generation#$descriptor.generation) | Not(OB Is defined($state.positions; $key)))
    return
   End if
   If (AXB_KeyIndex($descriptor.visible; $key)>=0)
    return New object("status"; "completed"; "message"; "List item already visible")
   End if
   // 4D scrolls the list to its visible line, as its own keyboard navigation does.
   OBJECT SET SCROLL POSITION(*; $name; $descriptor.rows.indexOf($key)+1)
   $data:=New object("options"; $options; "state"; $state; "action"; $request.action; "generation"; $descriptor.generation; "kind"; "reveal"; "target"; $key; "deadline"; Milliseconds+2000)
   return New object("status"; "pending"; "confirm"; Formula(AXB_HListConfirm($1)); "data"; $data)
 End case
 return
End if
// Describe the visible rows, in the order 4D shows them.
$state.valid:=False
$reply:=AXB_Host("node"; New object("objectName"; $name; "id"; $options.id; "role"; "table"; "label"; $options.label; "value"; ""; "enabled"; False))
If (Not($reply.ok=True))
 return $reply
End if
$node:=$reply.node
$node.objectName:=$name
$result.nodes.push($node)
$list:=OBJECT Get value($name)
If (((Value type($list)#Is real) && (Value type($list)#Is longint)) || Not(Is a list($list)))
 $node.label:=$options.label+": no list is assigned"
 return
End if
GET LIST PROPERTIES($list; $appearance; $icon; $lineHeight; $doubleClick; $multi; $editable)
$rows:=New collection
$outline:=New object
$positions:=New object
$levels:=New object
$texts:=New object
$known:=New object
$duplicate:=False
$count:=Count list items($list)
For ($i; 1; $count)
 GET LIST ITEM($list; $i; $ref; $text; $sub; $expanded)
 $key:="i:"+String($ref)
 If (OB Is defined($known; $key))
  $duplicate:=True
  break
 End if
 $known[$key]:=True
 // Depth from the parent chain; a well-formed 4D list is at most a few levels deep.
 $level:=0
 $parent:=List item parent($list; $ref)
 $parentKey:=Choose($parent=0; ""; "i:"+String($parent))
 While (($parent#0) & ($level<31))
  $level:=$level+1
  $parent:=List item parent($list; $parent)
 End while
 $rows.push($key)
 $positions[$key]:=$ref
 $levels[$key]:=$level
 $texts[$key]:=$text
 If (Is a list($sub))
  $outline[$key]:=New object("parent"; $parentKey; "level"; $level; "kind"; "group"; "label"; $text; "expanded"; $expanded)
 Else
  $outline[$key]:=New object("parent"; $parentKey; "level"; $level; "kind"; "leaf")
 End if
End for
If ($duplicate)
 $node.label:=$options.label+": item references must be unique"
 $result.unsupported.push(New object("object"; $name; "reason"; "hierarchicalListDuplicateReferences"))
 return
End if
If ($lineHeight<1)
 $node.label:=$options.label+": line height is unavailable"
 $result.unsupported.push(New object("object"; $name; "reason"; "hierarchicalListGeometryPending"))
 return
End if
$count:=Selected list items($list; $selection; *)
$selected:=New collection
For ($i; 1; Size of array($selection))
 $key:="i:"+String($selection{$i})
 If (OB Is defined($positions; $key))
  $selected.push($key)
 End if
End for
// 4D draws each visible item on one line of the list's line height, from the
// object's top edge; OBJECT GET SCROLL POSITION is the first visible line.
OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
OBJECT GET SCROLL POSITION(*; $name; $first)
$first:=New collection(1; $first).max()
$frames:=New object
$visible:=New collection
$rowLayout:=New collection
For ($i; 1; $rows.length)
 $key:=$rows[$i-1]
 $y:=$top+(($i-$first)*$lineHeight)
 $rowLayout.push(New collection($y; $lineHeight))
 If ($outline[$key].kind="group")
  $outline[$key].frame:=New collection($left; $y; $right-$left; $lineHeight)
 End if
 If (($y>=$top) & (($y+$lineHeight)<=$bottom))
  $visible.push($key)
  $frames[$key]:=New object("item"; New collection($left; $y; $right-$left; $lineHeight))
 End if
End for
$descriptor:=New object("generation"; $state.generation; "rows"; $rows; "outline"; $outline; \
 "columns"; New collection(New object("id"; "item"; "label"; $options.label; "enabled"; True; "editable"; False; "selectionTarget"; True)); \
 "selected"; $selected; "selectionMode"; Choose($multi=0; "single"; "multiple"); "visible"; $visible; "frames"; $frames; "headers"; New object; "headerHeight"; 0; \
 "layout"; New object("rows"; $rowLayout; "columns"; New collection(New collection($left; $right-$left))); \
 "disabled"; New collection; "unselectable"; New collection; "uneditable"; $rows.copy(); \
 "actions"; New object("select"; True; "disclose"; True; "reveal"; True))
If (($editable#0) | OBJECT Get enterable(*; $name))
 // Selection and disclosure work; editing an item's text is not yet published.
 $result.unsupported.push(New object("object"; $name; "reason"; "hierarchicalListEditingPending"))
End if
If ($multi#0)
 // One click replaces a multiple selection; extending it needs modifier clicks.
 $descriptor.selectionMode:="single"
 $result.unsupported.push(New object("object"; $name; "reason"; "hierarchicalListMultipleSelectionPending"))
End if
$key:=JSON Stringify(New collection($rows; $outline; $texts))
If (Compare strings($key; $state.orderState; sk char codes)#0)
 $state.order:=$state.order+1
 $state.orderState:=$key
End if
$descriptor.order:=$state.order
$state.list:=$list
$state.positions:=$positions
$state.levels:=$levels
$state.texts:=$texts
$state.lineHeight:=$lineHeight
$state.descriptor:=$descriptor
$state.valid:=True
$node.grid:=$descriptor
$node.enabled:=OBJECT Get enabled(*; $name)
