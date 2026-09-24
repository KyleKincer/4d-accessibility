var $state : Object
var $row; $error; $i : Integer
var $left; $right : Collection
ARRAY LONGINT($selected; 0)
$left:=New collection
$right:=New collection
$error:=AL_GetObjects(Form.left.area; ALP_Object_Selection; $selected)
For ($i; 1; Size of array($selected))
 $row:=$selected{$i}
 $left.push(aLeftKey{$row})
End for
$error:=AL_GetObjects(Form.right.area; ALP_Object_Selection; $selected)
For ($i; 1; Size of array($selected))
 $row:=$selected{$i}
 $right.push(aRightKey{$row})
End for
$state:=New object("registration"; Form.registration; "phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "timerTicks"; Form.timerTicks; "startResult"; Form.startResult; "leftSelected"; $left; "rightSelected"; $right; "leftSelections"; Form.left.selections; "rightSelections"; Form.right.selections; "leftFirst"; aLeftKey{1}; "leftTop"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_TopRow); "rightTop"; AL_GetAreaLongProperty(Form.right.area; ALP_Area_TopRow); "leftError"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_LastError); "rightError"; AL_GetAreaLongProperty(Form.right.area; ALP_Area_LastError); "receipt"; Form.axbForm.receipt; "bridgeError"; Form.axbError; "failure"; Form.axbFailure)
$state.leftStarts:=Form.left.starts
$state.leftEnds:=Form.left.ends
$state.leftRejections:=Form.left.rejections
$state.leftValue:=aLeftDescription{600}
$state.rightValue:=aRightDescription{600}
If (AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryInProgress)=1)
 $state.editor:=New object("row"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryRow); "column"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryColumn); "text"; AL_GetAreaTextProperty(Form.left.area; ALP_Area_EntryText); "start"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryHighlightS); "end"; AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryHighlightE); "editing4DText"; Is editing text; "object"; OBJECT Get name(Object with focus); "native"; AXB_Host("focus"; New object))
End if
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
