// Definitions are an application allowlist, evaluated in the current form.
// Off-page controls are omitted. A misspelled name is an adapter error.
#DECLARE($definitions : Collection) -> $result : Object
var $definition; $reply : Object
ARRAY TEXT($current; 0)
ARRAY TEXT($all; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; True; "nodes"; New collection)
FORM GET OBJECTS($all; $variables; $pages; Form all pages+Form inherited)
FORM GET OBJECTS($current; $variables; $pages; Form current page+Form inherited)
For each ($definition; $definitions)
 If (Find in array($all; $definition.objectName)<1)
  $result:=New object("ok"; False; "error"; "unknownControl")
  return
 End if
 If (Find in array($current; $definition.objectName)>0)
  $reply:=AXB_Host("node"; $definition)
  If (Not($reply.ok=True))
   $result:=$reply
   return
  End if
  $result.nodes.push($reply.node)
 End if
End for each
