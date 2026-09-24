var $nodes : Collection
var $snapshot; $envelope; $response; $action; $result : Object
var $state; $responseText : Text
var $error : Integer
var $gridNodes : Collection
var $gridNode : Object
$nodes:=New collection
$nodes.push(AXB_ControlNode("Name"; "name"; "textfield"; "Tester name"; Form.name; True))
$nodes.push(AXB_ControlNode("Allowed"; "allowed"; "checkbox"; "Allow submission"; Form.allowed; True))
$nodes.push(AXB_ControlNode("Submit"; "submit"; "button"; "Submit in 4D"; ""; Form.allowed))
$nodes.push(AXB_ControlNode("Reverse"; "reverse"; "button"; "Reverse grid rows"; ""; True))
$nodes.push(AXB_ControlNode("Modal"; "modal"; "button"; "Open modal"; ""; True))
$nodes.push(AXB_ControlNode("Hide"; "hide"; "button"; "Toggle name visibility"; ""; True))
$nodes.push(AXB_ControlNode("Remove"; "remove"; "button"; "Remove line 003"; ""; True))
$nodes.push(AXB_ControlNode("Second"; "second"; "button"; "Second window"; ""; True))
$nodes.push(AXB_ControlNode("More"; "more"; "button"; "Load 60 scrolling rows"; ""; True))
$nodes.push(AXB_ControlNode("Status"; "status"; "text"; "4D result"; Form.message+" ["+Form.lastSource+"]"; True))
Form.gridGeometry:="Host timer fired "+String(Form.timerFirings)+" time(s); "+Form.build
$nodes.push(AXB_ControlNode("Geometry"; "diagnostics"; "text"; "Runtime diagnostics"; Form.gridGeometry; True))
$gridNodes:=AXB_ALPTable(vAXBGrid; "Grid"; ->aAXBKeys; "lines")
For each ($gridNode; $gridNodes)
 $nodes.push($gridNode)
End for each
$snapshot:=New object("version"; 1; "label"; "4D form controls"; "enabled"; Current form window=Frontmost window; "nodes"; $nodes)
$state:=JSON Stringify($snapshot)
If ($state#Form.lastState)
 Form.revision:=Form.revision+1
 Form.lastState:=$state
End if
$snapshot.revision:=Form.revision
$envelope:=New object("snapshot"; $snapshot)
If (Value type(Form.receipt)=Is object)
 $envelope.receipt:=Form.receipt
End if
$responseText:=AXB Exchange(Current form window; Form.session; JSON Stringify($envelope))
$response:=JSON Parse($responseText)
If ($response.ok)
 OB REMOVE(Form; "receipt")
 If (Value type($response.action)=Is object)
  $action:=$response.action
  $result:=New object("status"; "rejected"; "message"; "Stale action rejected by 4D")
  If (($action.session=Form.session) & ($action.revision=Form.revision) & (Current form window=Frontmost window))
   Form.lastSource:="accessibility"
   If ($action.node="lines")
    $result:=AXB_ALPSelect(vAXBGrid; ->aAXBKeys; "lines"; $action)
    Form.message:=$result.message
   Else
    $result:=AXB_FixtureApply($action.node; $action.operation; Choose(Value type($action.value)=Is text; $action.value; ""))
   End if
  End if
  $result.id:=$action.id
  Form.receipt:=$result
 End if
Else
 AXB_Stop
 Form.message:="Bridge stopped: "+$response.error
End if
