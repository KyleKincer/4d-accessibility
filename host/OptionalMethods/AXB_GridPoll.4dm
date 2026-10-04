// Serve at most two page requests per event cycle in their original form view.
#DECLARE($context : Object; $tree : Object; $requests : Collection)
var $query; $route; $packet; $reply; $token; $next : Object
var $batch : Collection
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
 $batch:=New collection($query)
 // Only adjacent requests for the same live route share one fresh read.
 // Preserve the FIFO budget; never search past a different provider.
 If (($i=1) && ($context.gridQueue.length>0))
  $next:=$context.gridQueue[0]
  If (Compare strings($next.query.node; $query.node; sk char codes)=0)
   $next:=$context.gridQueue.shift()
   OB REMOVE($context.gridQueued; $next.key)
   $batch.push($next.query)
   $i:=2
  End if
 End if
 $route:=$tree.routes[$query.node]
 If (($route#Null) && ($route.node.grid#Null) && $route.node.visible)
  $packet:=New object("operation"; "readGrid"; "rootView"; $context.view; "path"; $route.path; "lineage"; $route.lineage; "instance"; $route.instance; "scope"; $route.scope; "action"; New object("node"; $route.localID); "requests"; $batch; "depth"; 0)
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
