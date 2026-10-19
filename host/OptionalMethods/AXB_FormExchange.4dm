// Own all snapshot/revision/receipt bookkeeping in one place.
var $context; $tree; $snapshot; $envelope; $reply; $action; $route; $rowRoute; $local; $result; $node; $packet; $pending; $token; $native; $focusTree; $changes : Object
var $rowID; $metaState; $nodeState : Text
var $sent; $sentIDs; $changed; $touched : Collection
var $nodeStates; $registry : Object
var $index : Integer
var $sameOrder : Boolean
var $selection; $frame; $viewport : Collection
var $left; $top; $right; $bottom : Real
var $allowed; $unchanged : Boolean
$context:=AXB_FormContext
If ($context=Null)
 return
End if
If (Not($context.active))
 return
End if
// Describe again only the objects whose drawing changed, when the plugin knows them.
$changes:=AXB_Host("changes"; New object("session"; $context.session))
If (Not($changes.ok=True))
 $changes:=Null
End if
$tree:=AXB_FormTree($changes)
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
 If ($pending.packet.data.nativeButton=True)
  // Native delivery already checked the captured node and physical hit target.
  // Its normal handler may change scope or open a modal window.
  $result:=AXB_ControlConfirm($pending.packet.data)
 Else
  If (($route#Null) & (Value type($route)=Is object))
   If ((Current form window=Frontmost window) & $route.node.enabled & $route.node.visible)
    $result:=AXB_View($pending.packet)
   End if
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
 // with the receipt, after rechecking the whole clipped form tree. A step that
 // is still pending has only posted input that 4D applies after this callback;
 // the next poll describes the form again before confirming the next step.
 If (Value type($context.receipt)=Is object)
  $tree:=AXB_FormTree
  If (Not($tree.ok=True))
   AXB_FormFailed($context; New object("error"; $tree.error))
   return
  End if
 End if
End if
$token:=$context.token
Use ($token)
 $token.fast:=$context.pending#Null
 $token.verify:=AXB_FormRoots[String(Current form window)].verifying=True
End use
$snapshot:=New object("version"; 1; "label"; $context.label; "enabled"; Current form window=Frontmost window)
If (Value type($context.view.options.automationKey)=Is text)
 $snapshot.automationKey:=$context.view.options.automationKey
End if
// The application asserts that this form's window does not scroll; controls parked outside it are omitted.
If ($context.view.options.omitOutsideWindow=True)
 $snapshot.omitOutsideWindow:=True
End if
// Seconds between descriptions of an unchanged form; the plugin's default is 5.
If (Value type($context.view.options.idleRefresh)=Is real)
 $snapshot.idleRefresh:=$context.view.options.idleRefresh
End if
$metaState:=JSON Stringify($snapshot)
// A node the last exchange sent, at the same place and with no change of focus since, is the
// same: a description reuses the nodes of unchanged objects. Only the others are compared, each
// with what was sent for its id.
$registry:=AXB_FormRoots[String(Current form window)]
$touched:=$registry.touched
If ($touched=Null)
 $touched:=New collection
End if
$registry.touched:=New collection
$sent:=$context.sentNodes
$sentIDs:=$context.sentIDs
$sameOrder:=($sent#Null) && ($sent.length=$tree.nodes.length)
$nodeStates:=$context.nodeStates
If (Not($sameOrder) | ($nodeStates=Null))
 $sameOrder:=False
 $nodeStates:=New object
End if
$changed:=New collection
If ($sameOrder)
 For ($index; 0; $tree.nodes.length-1)
  $node:=$tree.nodes[$index]
  // The same object, not an equal one: 4D compares objects in a collection by reference.
  If ((New collection($sent[$index]).indexOf($node)=0) && ($touched.indexOf($node)<0))
   continue
  End if
  If (Compare strings($node.id; $sentIDs[$index]; sk char codes)#0)
   $sameOrder:=False
   break
  End if
  $nodeState:=JSON Stringify($node)
  If (Compare strings($nodeState; String($nodeStates[$node.id]); sk char codes)#0)
   $changed.push($node)
   $nodeStates[$node.id]:=$nodeState
  End if
 End for
End if
If (Not($sameOrder))
 // Nodes were added, removed or moved: every node's state is what this exchange sends.
 $nodeStates:=New object
 For each ($node; $tree.nodes)
  $nodeStates[$node.id]:=JSON Stringify($node)
 End for each
End if
$unchanged:=$sameOrder && ($changed.length=0) && (Compare strings($metaState; String($context.metaState); sk char codes)=0)
If (Not($unchanged))
 $context.revision:=$context.revision+1
End if
$context.metaState:=$metaState
$context.nodeStates:=$nodeStates
// The description reuses its collections: keep the nodes themselves, as sent.
$context.sentNodes:=$tree.nodes.slice(0)
$context.sentIDs:=$tree.nodes.extract("id")
$context.sentEnabled:=$snapshot.enabled
$snapshot.revision:=$context.revision
$envelope:=New object("snapshot"; $snapshot)
Case of
 : ($context.exchanged#True)
  $snapshot.nodes:=$tree.nodes
 : ($unchanged)
  // The plugin holds an unchanged form's tree: send only its revision.
  $envelope.snapshot:=New object("version"; 1; "revision"; $context.revision; "unchanged"; True)
 : ($sameOrder)
  // Only the nodes that changed, each replacing the node with its id in the tree the plugin holds.
  $snapshot.base:=$context.revision-1
  $snapshot.changed:=$changed
 Else
  $snapshot.nodes:=$tree.nodes
End case
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
If (Not($reply.ok=True) && ($snapshot.changed#Null))
 // A plugin that does not take changed nodes, or holds another tree, gets the whole tree.
 OB REMOVE($snapshot; "base")
 OB REMOVE($snapshot; "changed")
 $snapshot.nodes:=$tree.nodes
 $reply:=AXB_Host("exchange"; New object("session"; $context.session; "envelope"; $envelope))
End if
If (Not($reply.ok=True))
 $context.exchanged:=False
 AXB_FormFailed($context; New object("error"; $reply.error))
 return
End if
$context.exchanged:=True
$context.diagnostics:=New object("ok"; True; "ready"; True; "revision"; $context.revision; "nodeCount"; $tree.nodes.length; "issues"; $tree.issues)
// How many form and subform views were described whole, and how many only where they changed.
$context.diagnostics.wholeDescriptions:=Num(AXB_FormRoots[String(Current form window)].wholeDescriptions)
$context.diagnostics.partialDescriptions:=Num(AXB_FormRoots[String(Current form window)].partialDescriptions)
// How many objects the backstop checked again, a few at a time.
$context.diagnostics.verifiedObjects:=Num(AXB_FormRoots[String(Current form window)].verifiedObjects)
// How many nodes the last exchange that changed the tree sent: all of them, or only the changed ones.
If (Not($unchanged))
 $context.sentNodeCount:=Choose($snapshot.nodes#Null; $tree.nodes.length; $changed.length)
End if
$context.diagnostics.sentNodes:=Num($context.sentNodeCount)
// How many labels, values and controls the plugin had to shorten, mend or leave out to publish the form.
$context.diagnostics.repairs:=Num($reply.repairs)
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
   If (($route.node.revealable=True) & ($action.operation#"gridSetExpanded"))
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
