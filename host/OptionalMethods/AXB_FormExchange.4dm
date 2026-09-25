// Own all snapshot/revision/receipt bookkeeping in one place.
var $context; $tree; $snapshot; $envelope; $reply; $action; $route; $rowRoute; $local; $result; $node; $packet; $pending; $token; $native; $focusTree : Object
var $state; $rowID : Text
var $selection; $frame; $viewport : Collection
var $left; $top; $right; $bottom : Real
var $allowed : Boolean
$context:=AXB_FormContext
If ($context=Null)
 return
End if
If (Not($context.active))
 return
End if
$tree:=AXB_FormTree
If (Not($tree.ok=True))
 AXB_FormFailed($context; New object("error"; $tree.error))
 return
End if
// Some 4D bindings update after the action's event cycle. Confirm once in the
// same form instance on the next poll; only final receipts reach the plugin.
If ((Value type($context.pending)=Is object) & ($context.pending#Null))
 $pending:=$context.pending
 OB REMOVE($context; "pending")
 $result:=New object("status"; "rejected"; "message"; "Form changed before action confirmation")
 $route:=$tree.routes[$pending.node]
 If (($route#Null) & (Value type($route)=Is object))
  If ((Current form window=Frontmost window) & $route.node.enabled & $route.node.visible)
   $result:=AXB_View($pending.packet)
  End if
 End if
 If (Not($context.active))
  return
 End if
 If ($result.status="pending")
  $pending.packet.confirm:=$result.confirm
  $pending.packet.data:=$result.data
  $context.pending:=$pending
 Else
  $result:=AXB_Result($result)
  $result.id:=$pending.id
  $context.receipt:=$result
 End if
 // A confirmed callback can update dependent controls. Publish their new state
 // with the receipt, after rechecking the whole clipped form tree.
 $tree:=AXB_FormTree
 If (Not($tree.ok=True))
  AXB_FormFailed($context; New object("error"; $tree.error))
  return
 End if
End if
$token:=$context.token
Use ($token)
 $token.fast:=$context.pending#Null
End use
$snapshot:=New object("version"; 1; "label"; $context.label; "enabled"; Current form window=Frontmost window; "nodes"; $tree.nodes)
$state:=JSON Stringify($snapshot)
If (Compare strings($state; $context.state; sk char codes)#0)
 $context.revision:=$context.revision+1
 $context.state:=$state
End if
$snapshot.revision:=$context.revision
$envelope:=New object("snapshot"; $snapshot)
If ($context.gridPages#Null)
 $envelope.gridPages:=$context.gridPages
End if
If (Value type($context.receipt)=Is object)
 $envelope.receipt:=$context.receipt
End if
If ($context.controlInput#Null)
 $envelope.controlInput:=$context.controlInput
End if
If ($context.editorInput#Null)
 $envelope.editorInput:=$context.editorInput
End if
$reply:=AXB_Host("exchange"; New object("session"; $context.session; "envelope"; $envelope))
If (Not($reply.ok=True))
 AXB_FormFailed($context; New object("error"; $reply.error))
 return
End if
$context.diagnostics:=New object("ok"; True; "ready"; True; "revision"; $context.revision; "nodeCount"; $tree.nodes.length; "issues"; $tree.issues)
OB REMOVE($context; "receipt")
OB REMOVE($context; "controlInput")
$context.controlInputResult:=$reply.controlInputResult
$context.controlInputReadAt:=Milliseconds
OB REMOVE($context; "editorInput")
$context.editorInputResult:=$reply.editorInputResult
OB REMOVE($context; "gridPages")
AXB_GridPoll($context; $tree; $reply.gridRequests)
If (Value type($reply.action)#Is object)
 return
End if
$action:=$reply.action
$result:=New object("status"; "rejected"; "message"; "Stale or unavailable control")
If (($action.session=$context.session) & ($action.revision=$context.revision) & (Current form window=Frontmost window))
 $route:=$tree.routes[$action.node]
 If (($route#Null) & (Value type($route)=Is object))
  $local:=New object("id"; $action.id; "node"; $route.localID; "operation"; $action.operation; "value"; $action.value)
  $node:=$route.node
  $allowed:=($node.enabled | ($action.operation="reveal")) & $node.visible
  If ($action.operation="selectRows")
   $selection:=New collection
   For each ($rowID; $action.value)
    $rowRoute:=$tree.routes[$rowID]
    If (($rowRoute=Null) | (Value type($rowRoute)#Is object))
     $allowed:=False
    Else
     $node:=$rowRoute.node
     If (Not($node.enabled & $node.visible))
      $allowed:=False
     End if
     If (($rowRoute.instance#$route.instance) | (Compare strings(JSON Stringify($rowRoute.path); JSON Stringify($route.path); sk char codes)#0))
      $allowed:=False
     Else
      $selection.push($rowRoute.localID)
     End if
    End if
   End for each
   $local.value:=$selection
  End if
  If ($allowed)
   $packet:=New object("operation"; "apply"; "rootView"; $context.view; "path"; $route.path; "lineage"; $route.lineage; "instance"; $route.instance; "scope"; $route.scope; "action"; $local; "depth"; 0)
   If ($route.node.revealable=True)
    $packet.operation:="reveal"
    $result:=AXB_View($packet)
    If ($result.ok=True)
     $native:=AXB_Host("focus"; New object)
     $frame:=$result.frame
     $viewport:=$native.viewport
     If (($native.ok=True) && ($viewport#Null) && AXB_Intersects($frame; $viewport))
      $left:=New collection($frame[0]; $viewport[0]).max()
      $top:=New collection($frame[1]; $viewport[1]).max()
      $right:=New collection($frame[0]+$frame[2]; $viewport[0]+$viewport[2]).min()
      $bottom:=New collection($frame[1]+$frame[3]; $viewport[1]+$viewport[3]).min()
      $local.viewport:=New collection($left; $top; $right-$left; $bottom-$top)
     Else
      $result:=New object("ok"; False; "status"; "rejected"; "message"; "Control is outside the form viewport")
     End if
    End if
    If ($result.ok=True)
     If ($action.operation="reveal")
      $result:=New object("status"; "completed"; "message"; "Control revealed")
     Else
      $packet.operation:="apply"
      // A focus event must not compare the new origin with positions from
      // before reveal. Refresh only when scrolling actually moved a child.
      $focusTree:=New object("ok"; True)
      If (AXB_FormRoots[String(Current form window)].focusGeometryChanged=True)
       $focusTree:=AXB_FormTree
      End if
      If ($focusTree.ok=True)
       $result:=AXB_View($packet)
      Else
       $result:=New object("status"; "rejected"; "message"; "Form changed while revealing the control")
      End if
     End if
    End if
   Else
    $result:=AXB_View($packet)
   End if
  End if
 End if
End if
// The callback may stop or replace the form. A captured inactive context cannot
// acknowledge an old action in the replacement session.
If ($context.active)
 If ($result.status="pending")
  $packet.operation:="confirm"
  $packet.confirm:=$result.confirm
  $packet.data:=$result.data
  $context.pending:=New object("id"; $action.id; "node"; $action.node; "packet"; $packet)
  // The first editor step can already have posted a character. Switch the
  // worker now, before its next sleep: the idle interval may be one second,
  // long enough for an application's search timer to submit that character.
  Use ($token)
   $token.fast:=True
  End use
 Else
  $result.id:=$action.id
  $context.receipt:=$result
 End if
End if
