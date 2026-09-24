var $state; $control; $request : Object
var $name : Text
var $i; $left; $top; $right; $bottom; $x; $y : Integer
ARRAY TEXT($names; 0)
ARRAY TEXT($order; 0)
ARRAY POINTER($pointers; 0)
ARRAY LONGINT($pages; 0)
$state:=New object("phase"; "ready"; "runId"; Form.config.runId; "compiled"; Is compiled mode; "start"; Form.start; "events"; Form.events; "name"; Form.name; "allowed"; Form.allowed; "email"; Form.email; "phone"; Form.phone; "saved"; Form.saved; "choice"; AXBF_Choices; "focus"; OBJECT Get name(Object with focus); "controls"; New collection)
If (Form.config.dynamic)
 $state.start:=Form.axbDynamic.startResult
End if
FORM GET OBJECTS($names; $pointers; $pages; Form current page+Form inherited)
$state.failure:=Form.axbFailure
$state.notes:=Form.notes
$state.validationError:=Form.validationError
$state.secretAccepted:=Form.secret="AX synthetic password"
$state.summaryEnterable:=OBJECT Get enterable(*; "Summary")
If (Form.axbView#Null)
 If (Form.axbView.discovery#Null)
  For each ($control; Form.axbView.discovery.nodes)
   If ($control.objectName="Summary")
    $state.summaryDescriptor:=$control
   End if
  End for each
 End if
End if
If (OBJECT Get name(Object with focus)="Name")
 $state.editedText:=Get edited text
End if
FORM GET ENTRY ORDER($order; *)
$state.entryOrder:=New collection
For ($i; 1; Size of array($order))
 $state.entryOrder.push($order{$i})
End for
For ($i; 1; Size of array($names))
 $name:=$names{$i}
 OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
 $x:=($left+$right)/2
 $y:=($top+$bottom)/2
 CONVERT COORDINATES($x; $y; XY Current form; XY Screen)
 $control:=New object("name"; $name; "type"; OBJECT Get type(*; $name); "title"; OBJECT Get title(*; $name); "font"; OBJECT Get font(*; $name); "visible"; OBJECT Get visible(*; $name); "enabled"; OBJECT Get enabled(*; $name); "center"; New collection($x; $y))
 $state.controls.push($control)
End for
File("/RESOURCES/runtime-status.json").setText(JSON Stringify($state))
// The baseline probe is deliberately separate from AX acceptance tests.
If (File("/RESOURCES/probe.json").exists)
 $request:=JSON Parse(File("/RESOURCES/probe.json").getText())
 File("/RESOURCES/probe.json").delete()
 If (Find in array($names; $request.object)>0)
  Case of
   : ($request.operation="focus")
    GOTO OBJECT(*; $request.object)
   : ($request.operation="click")
    OBJECT GET COORDINATES(*; $request.object; $left; $top; $right; $bottom)
    $x:=($left+$right)/2
    $y:=($top+$bottom)/2
    CONVERT COORDINATES($x; $y; XY Current form; XY Current window)
    POST CLICK($x; $y; Current process)
   : ($request.operation="type")
    HIGHLIGHT TEXT(*; $request.object; 1; 2147483647)
    For ($i; 1; Length($request.value))
     POST KEY(Character code(Substring($request.value; $i; 1)); 0; Current process)
    End for
   : ($request.operation="key")
    POST KEY($request.code; $request.modifiers; Current process)
  End case
 End if
End if
