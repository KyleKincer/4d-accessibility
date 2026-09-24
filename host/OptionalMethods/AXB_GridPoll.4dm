// Serve at most two page requests per event cycle in their original form view.
#DECLARE($context : Object; $tree : Object; $requests : Collection)
var $query; $route; $packet; $reply; $token : Object
var $key : Text
var $i : Integer
If ($context.gridQueue=Null)
 $context.gridQueue:=New collection
 $context.gridQueued:=New object
End if
If ($requests#Null)
 For each ($query; $requests)
  $key:=Generate digest(JSON Stringify($query); SHA256 digest)
  If (Not(OB Is defined($context.gridQueued; $key)) & ($context.gridQueue.length<256))
   $context.gridQueued[$key]:=True
   $context.gridQueue.push(New object("key"; $key; "query"; $query))
  End if
 End for each
End if
$context.gridPages:=New collection
For ($i; 1; 2)
 If ($context.gridQueue.length=0)
  break
 End if
 $packet:=$context.gridQueue.shift()
 OB REMOVE($context.gridQueued; $packet.key)
 $query:=$packet.query
 $route:=$tree.routes[$query.node]
 If (($route#Null) && ($route.node.grid#Null) && $route.node.visible)
  $packet:=New object("operation"; "readGrid"; "rootView"; $context.view; "path"; $route.path; "lineage"; $route.lineage; "instance"; $route.instance; "scope"; $route.scope; "action"; New object("node"; $route.localID); "requests"; New collection($query); "depth"; 0)
  $reply:=AXB_View($packet)
  If (($reply.ok=True) && ($reply.pages#Null))
   $context.gridPages:=$context.gridPages.concat($reply.pages)
  End if
 End if
End for
$token:=$context.token
Use ($token)
 // Background cache requests must not keep full-form discovery in the fast
 // editor loop. They continue on the ordinary bounded polling schedule.
 $token.fast:=($context.pending#Null)
End use
