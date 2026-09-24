// Compose reusable grid providers with the automatic ordinary-control tree.
// Provider selection uses fixed internal methods, never an AX-supplied name.
#DECLARE($view : Object; $request : Object) -> $result : Object
var $name; $id; $property; $issueKey; $column : Text
var $columns : Collection
var $options; $state; $reply; $action : Object
var $ready : Boolean
ARRAY TEXT($objects; 0)
ARRAY TEXT($methods; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; True; "nodes"; New collection; "unsupported"; New collection; "pages"; New collection; "status"; "rejected"; "message"; "Grid is unavailable")
If ($view.options.grids=Null)
 return
End if
If ($view.grids=Null)
 $view.grids:=New object
End if
FORM GET OBJECTS($objects; $variables; $pages; Form current page+Form inherited)
For each ($name; $view.options.grids)
 If ((Find in array($objects; $name)>0) && OBJECT Get visible(*; $name))
  // Normalize only the outer object. Providers read nested configuration;
  // keeping its identity avoids deep-copying Formula objects on every poll.
  $options:=New object
  For each ($property; $view.options.grids[$name])
   $options[$property]:=$view.options.grids[$name][$property]
  End for each
  If (Not(AXB_GridOptions(New object($name; $options))))
   return New object("ok"; False; "error"; "invalidGrids")
  End if
  $options.objectName:=$name
  $id:="grid."+Substring(Generate digest($name; SHA256 digest); 1; 32)
  $options.id:=$id
  If (Not(OB Is defined($options; "label")))
   $options.label:=$name
  End if
  $state:=$view.grids[$name]
  If ($state=Null)
   $state:=New object("generation"; Generate UUID; "order"; 0; "orderState"; "")
   If (($options.meta#Null) & (OBJECT Get type(*; $name)=Object type listbox))
    // Bind the mapping when this grid is first discovered, including while
    // loading or before invalid row keys can produce a successful binding.
    $state.metaExpression:=LISTBOX Get property(*; $name; lk meta expression)
   End if
   $view.grids[$name]:=$state
  End if
  $ready:=True
  If (OB Is defined($options; "ready"))
   If (Value type($options.ready)=Is Boolean)
    $ready:=$options.ready
   Else
    $ready:=$options.ready.call()=True
   End if
  End if
  If (Not($ready))
   If (Not($state.suspended=True))
    $state.generation:=Generate UUID
   End if
   $state.suspended:=True
   $state.valid:=False
   If ($request.operation="describe")
    $reply:=AXB_Host("node"; New object("objectName"; $name; "id"; $id; "role"; "table"; "label"; $options.label+": loading"; "value"; ""; "enabled"; False))
    If (Not($reply.ok=True))
     return $reply
    End if
    $reply.node.objectName:=$name
    $result.nodes.push($reply.node)
   End if
   continue
  End if
  $state.suspended:=False
  If ($options.kind="areaList")
   If ($view.areaListProvider=Null)
    METHOD GET NAMES($methods; "AXB_ALPGrid")
    $view.areaListProvider:=Find in array($methods; "AXB_ALPGrid")>0
   End if
   If (Not($view.areaListProvider=True))
    return New object("ok"; False; "error"; "areaListProviderUnavailable")
   End if
   If (($request.operation="describe") | ($request.node=$id))
    EXECUTE METHOD("AXB_ALPGrid"; $reply; $request.operation; $options; $state; $request)
    If ($request.operation#"describe")
     return $reply
    End if
    If (Not($reply.ok=True))
     return $reply
    End if
    $result.nodes:=$result.nodes.concat($reply.nodes)
   End if
   continue
  End if
  If (OBJECT Get type(*; $name)=Object type listbox)
   If ($request.operation="describe")
    $reply:=AXB_GridListbox("describe"; $options; $state; $request)
    If (Not($reply.ok=True))
     return $reply
    End if
    $result.nodes:=$result.nodes.concat($reply.nodes)
    If ($state.editingIssues#Null)
     For each ($column; $state.editingIssues)
      $result.unsupported.push(New object("object"; $name; "column"; $column; "reason"; "gridCellEditingPending"))
     End for each
    End if
    If ($state.valueIssues#Null)
     $columns:=New collection
     For each ($issueKey; $state.valueIssues)
      $column:=$state.valueIssues[$issueKey]
      If (AXB_KeyIndex($columns; $column)<0)
       $columns.push($column)
       $result.unsupported.push(New object("object"; $name; "column"; $column; "reason"; "gridValueDescriptionRequired"))
      End if
     End for each
    End if
   Else
    If ($request.node=$id)
     return AXB_GridListbox($request.operation; $options; $state; $request)
    End if
   End if
  End if
 End if
End for each
