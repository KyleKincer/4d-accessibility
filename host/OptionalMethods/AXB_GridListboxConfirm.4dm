// Confirmation re-enters the original form/view before touching its editor.
#DECLARE($data : Object) -> $result : Object
var $reply; $grid; $action; $cell; $node; $textAction; $value; $native; $header : Object
var $key; $column : Text
var $start; $end; $position; $scrollRow; $scrollColumn; $nativeColumn; $nativeRow : Integer
var $matches : Boolean
var $headerFrame : Collection
var $left; $top; $right; $bottom; $x; $y; $alignment; $inset; $padding : Integer
$result:=New object("status"; "rejected"; "message"; "Grid changed before action completion")
$reply:=AXB_GridListbox("describe"; $data.options; $data.state; New object)
If (Not($data.state.valid=True))
 return
End if
$grid:=$data.state.descriptor
$action:=$data.action
If ($action.operation="gridSelect")
 If (($grid.generation#$data.generation) | (Current form window#Frontmost window))
  return
 End if
 $result.message:="Application did not confirm the requested selection"
 If (Milliseconds>=$data.deadline)
  return
 End if
 $result:=New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
 $matches:=$grid.selected.length=$action.value.length
 For each ($key; $action.value)
  If ((AXB_KeyIndex($grid.unselectable; $key)>=0) & (AXB_KeyIndex($data.retainedSelection; $key)<0))
   return New object("status"; "rejected"; "message"; "Row became unavailable during selection")
  End if
  $matches:=$matches & (AXB_KeyIndex($grid.selected; $key)>=0)
 End for each
 If (Not($matches))
  If ($data.hookCalled=True)
   return New object("status"; "rejected"; "message"; "Application changed the requested selection")
  End if
  return
 End if
 If (Not($data.hookCalled=True))
  $data.hookCalled:=True
  If ($data.options.onSelection#Null)
   $data.options.onSelection.call()
   // Its normal validation or dependent-UI updates can change the selection.
   return
  End if
 End if
 If ($action.value.length>0)
  $key:=$action.value[$action.value.length-1]
  If (Not($data.scrolled=True))
   $position:=$data.state.positions[$key]
   OBJECT GET SCROLL POSITION(*; $data.options.objectName; $scrollRow; $scrollColumn)
   OBJECT SET SCROLL POSITION(*; $data.options.objectName; $position; $scrollColumn)
   $data.scrolled:=True
   return
  End if
  If (AXB_KeyIndex($grid.visible; $key)<0)
   return
  End if
 End if
 return New object("status"; "completed"; "message"; "List box selection confirmed")
End if
If (New collection("gridHeaderPress"; "gridHeaderReveal").indexOf($action.operation)>=0)
 $column:=$action.value.column
 If (($grid.generation#$data.generation) | Not(OB Is defined($data.state.columns; $column)))
  return
 End if
 If ($data.inputSent=True)
  $native:=AXB_PollGuard.context.controlInputResult
  If (($native#Null) && ($native.action=$action.id))
   If ($native.accepted=True)
    return New object("status"; "completed"; "message"; "Column header activated")
   End if
   return New object("status"; "rejected"; "message"; "Header changed before native input delivery")
  End if
  If ((Milliseconds>=$data.deadline) & (AXB_PollGuard.context.controlInputReadAt>=$data.deadline))
   return New object("status"; "rejected"; "message"; "Native header activation timed out")
  End if
  return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
 End if
 $header:=$data.state.columns[$column].header
 $headerFrame:=$grid.headers[$column]
 If (Not($header.visible=True) | (Current form window#Frontmost window))
  return
 End if
 If ($headerFrame#Null)
  If ($action.operation="gridHeaderReveal")
   return New object("status"; "completed"; "message"; "Column header is visible")
  End if
  If (Not($header.enabled & $header.press) | ((($header.visible#$action.value.expectedHeader.visible) | ($header.enabled#$action.value.expectedHeader.enabled) | ($header.press#$action.value.expectedHeader.press) | ($header.sortable#$action.value.expectedHeader.sortable) | ($header.sort#$action.value.expectedHeader.sort))))
   return
  End if
  $x:=$headerFrame[0]+($headerFrame[2]/2)
  $y:=$headerFrame[1]+($headerFrame[3]/2)
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  $data.inputSent:=True
  AXB_PollGuard.context.controlInput:=New object("action"; $action.id; "point"; New collection($x; $y))
 End if
 If (Milliseconds<$data.deadline)
  return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
 End if
 return New object("status"; "rejected"; "message"; "Column header could not be revealed")
End if
$key:=$action.value.row
$column:=$action.value.column
If (($grid.generation#$data.generation) | Not(OB Is defined($data.state.positions; $key)) | Not(OB Is defined($data.state.columns; $column)))
 return
End if
If ($action.operation="gridReveal")
 If (($grid.frames[$key]#Null) && ($grid.frames[$key][$column]#Null))
  return New object("status"; "completed"; "message"; "Cell is visible")
 End if
Else
 If ($data.widget#Null)
  $position:=$data.state.positions[$key]
  $value:=AXB_GridValue($data.state; $data.state.columns[$column]; $position)
  If (Not($value.ok) | ($value.role#$data.widget.role))
   return
  End if
  // Once native input was sent, observe its result. A normal data-change
  // handler may advance focus or make the edited column read-only.
  If ($data.inputSent=True)
   $native:=AXB_PollGuard.context.controlInputResult
   If (($native=Null) || ($native.action#$action.id))
    // Native menu tracking can suspend this form's polling. Fetch a fresh
    // acknowledgement after the deadline before treating its old absence
    // as a timeout. The next exchange still belongs to this exact action.
    If ((Milliseconds<$data.deadline) | (AXB_PollGuard.context.controlInputReadAt<$data.deadline))
     return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
    End if
    return New object("status"; "rejected"; "message"; "Native cell activation timed out")
   End if
   If (Not($native.accepted=True))
    return New object("status"; "rejected"; "message"; "Cell changed before native input delivery")
   End if
   If ($value.role="popup")
    If ($native.menuOpened=True)
     return New object("status"; "completed"; "message"; "Native cell choices opened")
    End if
   Else
    If ($value.checked#$data.widget.checked)
     return New object("status"; "completed"; "message"; "Cell checkbox state confirmed")
    End if
   End if
   If (Milliseconds<$data.deadline)
    return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
   End if
   If ($value.role="popup")
    return New object("status"; "rejected"; "message"; "Application did not open the cell choices")
   End if
   return New object("status"; "rejected"; "message"; "Application did not accept the cell state change")
  End if
  If (Not($data.state.columns[$column].editable=True) | (AXB_KeyIndex($grid.uneditable; $key)>=0) | Not($value.enabled & $value.editable) | (Current form window#Frontmost window))
   return
  End if
  If ($action.operation="gridEdit")
   LISTBOX GET CELL POSITION(*; $data.options.objectName; $nativeColumn; $nativeRow)
   If (Not(AXB_ControlFocus($data.options.objectName)) | ($nativeColumn#$data.state.columns[$column].number) | ($nativeRow#$position) | Is editing text)
    return New object("status"; "rejected"; "message"; "Cell did not receive keyboard focus")
   End if
   return New object("status"; "completed"; "message"; "Cell control is focused")
  End if
  If ((Compare strings($value.value; $data.widget.value; sk char codes)#0) | ($value.checked#$data.widget.checked))
   return New object("status"; "rejected"; "message"; "Application changed the cell before activation")
  End if
  LISTBOX GET CELL COORDINATES(*; $data.options.objectName; $data.state.columns[$column].number; $position; $left; $top; $right; $bottom)
  $x:=($left+$right)/2
  $y:=($top+$bottom)/2
  If ($value.role="checkbox")
   $alignment:=OBJECT Get horizontal alignment(*; $column)
   If ($alignment=Align default)
    $alignment:=Choose($value.boolean=True; Align left; Align right)
   End if
   $padding:=LISTBOX Get property(*; $column; lk cell horizontal padding)
   If ($padding=lk inherited)
    $padding:=LISTBOX Get property(*; $data.options.objectName; lk cell horizontal padding)
   End if
   // 4D 20.8 places the native indicator center 11 logical pixels inside
   // its padded edge. Live left/center/right and inherited-padding cases
   // verify this; the native dispatcher also checks the clipped cell hit.
   $inset:=New collection(11+New collection(0; $padding).max(); ($right-$left)/2).min()
   If ($alignment=Align left)
    $x:=$left+$inset
   End if
   If ($alignment=Align right)
    $x:=$right-$inset
   End if
  End if
  CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
  $data.inputSent:=True
  AXB_PollGuard.context.controlInput:=New object("action"; $action.id; "point"; New collection($x; $y))
  return New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
 End if
 If (Not($data.state.columns[$column].editable=True) | (AXB_KeyIndex($grid.uneditable; $key)>=0))
  return
 End if
 $cell:=New object("objectName"; $data.options.objectName; "row"; $key; "column"; $column; "generation"; $grid.generation)
 If (AXB_TextFocus($column; $cell) & Is editing text)
  If ($action.value.expectedEditor#Null)
   GET HIGHLIGHT(*; $column; $start; $end)
   If ((Compare strings(Get edited text; $action.value.expectedValue; sk char codes)#0) | (($start-1)#$action.value.expectedEditor.selection[0]) | (($end-$start)#$action.value.expectedEditor.selection[1]))
    return New object("status"; "rejected"; "message"; "Cell editor changed before the request")
   End if
  End if
  If ($action.operation="gridEdit")
   return New object("status"; "completed"; "message"; "Cell editor is focused")
  End if
  $node:=New object("objectName"; $column; "gridCell"; $cell; "protected"; False; "multiline"; LISTBOX Get property(*; $column; lk allow wordwrap)=lk yes)
  $textAction:=New object("id"; $action.id; "operation"; "setValue"; "value"; $action.value.text)
  If ($action.operation="gridSetSelection")
   $textAction.operation:="setSelection"
   $textAction.value:=$action.value.selection
  End if
  If ($action.operation="gridReplaceSelection")
   $textAction.operation:="replaceSelection"
  End if
  return AXB_TextAction($textAction; $node; New object)
 End if
End if
If (Milliseconds<$data.deadline)
 $result:=New object("status"; "pending"; "confirm"; Formula(AXB_GridListboxConfirm($1)); "data"; $data)
End if
