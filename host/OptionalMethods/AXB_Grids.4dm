// Compose reusable grid providers with the automatic ordinary-control tree.
// Provider selection uses fixed internal methods, never an AX-supplied name.
#DECLARE($view : Object; $request : Object) -> $result : Object
var $name; $id; $property; $issueKey; $column; $detectedKind; $autoLabel; $lbNamedSel; $prevErr; $metaKey : Text
var $columns : Collection
var $options; $state; $reply; $action; $configured; $hints; $hint; $probe; $merged; $alpHelpers : Object
var $table : Pointer
var $detail; $list : Text
var $position; $type; $lbTable; $lbRows : Integer
var $formKey; $issues : Text
var $ready; $hierarchical; $wasConfigured : Boolean
var $lbVal : Variant
ARRAY TEXT($objects; 0)
ARRAY TEXT($methods; 0)
ARRAY POINTER($variables; 0)
ARRAY POINTER($hierarchy; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; True; "nodes"; New collection; "unsupported"; New collection; "pages"; New collection; "status"; "rejected"; "message"; "Grid is unavailable")
$configured:=New object
If ($view.options.grids#Null)
 For each ($name; $view.options.grids)
  $configured[$name]:=$view.options.grids[$name]
 End for each
End if
If ($view.grids=Null)
 $view.grids:=New object
End if
If (Not(OB Is defined($view; "gridHintsLoaded")))
 $view.gridHints:=AXB_FormStored("hints")
 $view.gridHintsLoaded:=True
End if
$hints:=$view.gridHints
// Detect AreaList Pro provider once per view (host method, local method, or sibling component).
If ($view.areaListProvider=Null)
 METHOD GET NAMES($methods; "AXB_ALPGrid"; *)
 If (Find in array($methods; "AXB_ALPGrid")<=0)
  METHOD GET NAMES($methods; "AXB_ALPGrid")
 End if
 If (Find in array($methods; "AXB_ALPGrid")>0)
  $view.areaListProvider:=True
 Else
  $prevErr:=Method called on error(ek local)
  ON ERR CALL("AXB_WatchError"; ek local)
  $probe:=Null
  EXECUTE METHOD("AXB_ALPGrid"; $probe; "ping"; New object; New object; New object)
  ON ERR CALL($prevErr; ek local)
  $view.areaListProvider:=($probe#Null) && (Value type($probe)=Is object) && ($probe.ok=True)
 End if
End if
$alpHelpers:=New object(\
"controlFocus"; Formula(AXB_ControlFocus($1)); \
"keyIndex"; Formula(AXB_KeyIndex($1; $2)); \
"textAction"; Formula(AXB_TextAction($1; $2; $3)); \
"textIndex"; Formula(AXB_TextIndex($1; $2; $3)))
FORM GET OBJECTS($objects; $variables; $pages; Form current page+Form inherited)
// An object's type is fixed by its form: read it once per form.
$formKey:=Current form name
$table:=Current form table
If (Not(Is nil pointer($table)))
 $formKey:=$formKey+"/"+String(Table($table))
End if
If ((Value type($view.objectTypes)#Is object) || ($view.objectTypes.form#$formKey))
 $view.objectTypes:=New object("form"; $formKey; "types"; New object)
End if
For ($position; 1; Size of array($objects))
 $name:=$objects{$position}
 If (OB Is defined($view.objectTypes.types; $name))
  $type:=$view.objectTypes.types[$name]
 Else
  $type:=OBJECT Get type(*; $name)
  $view.objectTypes.types[$name]:=$type
 End if
 If (Not(OBJECT Get visible(*; $name)))
  continue
 End if
 If (($view.options.controls#Null) && ($view.options.controls[$name]#Null) && ($view.options.controls[$name].decorative=True))
  continue
 End if
 If (($type=Object type subform) && Not(OB Is defined($configured; $name)))
  OBJECT GET SUBFORM(*; $name; $table; $detail; $list)
  If (Not(Is nil pointer($table)) & ($list#""))
   $configured[$name]:=New object("kind"; "listSubform"; "label"; $name)
  End if
  continue
 End if
 If (($type=Object type hierarchical list) && Not(OB Is defined($configured; $name)))
  // A hierarchical list needs no configuration; a configured label still wins.
  $configured[$name]:=New object("kind"; "hierarchicalList")
  If (($view.options.controls#Null) && ($view.options.controls[$name]#Null) && (Value type($view.options.controls[$name].label)=Is text) && ($view.options.controls[$name].label#""))
   $configured[$name].label:=$view.options.controls[$name].label
  Else
   $configured[$name].label:=Choose(OBJECT Get help tip(*; $name)#""; OBJECT Get help tip(*; $name); $name)
  End if
  continue
 End if
 If ($type=Object type listbox)
  $wasConfigured:=OB Is defined($configured; $name)
  If ($wasConfigured && OB Is defined($configured[$name]; "kind"))
   If (($configured[$name].kind="array") && Not(OB Is defined($configured[$name]; "keyColumn")))
    $merged:=OB Copy($configured[$name])
    $merged.positionalKeys:=True
    $configured[$name]:=$merged
   End if
   If (($configured[$name].kind="collection") && Not(OB Is defined($configured[$name]; "keyProperty")))
    $merged:=OB Copy($configured[$name])
    $merged.positionalKeys:=True
    $configured[$name]:=$merged
   End if
  Else
   // Auto-discover listbox data source type when visible.
   $lbRows:=LISTBOX Get number of rows(*; $name)
   If (Not($wasConfigured) & ($lbRows>2000))
    continue
   End if
   $detectedKind:=""
   $lbTable:=0
   $lbNamedSel:=""
   LISTBOX GET TABLE SOURCE(*; $name; $lbTable; $lbNamedSel)
   If ($lbTable>0)
    $detectedKind:="selection"
   Else
    $lbVal:=OBJECT Get value($name)
    Case of
     : (Value type($lbVal)=Is collection)
      $detectedKind:="collection"
     : ((Value type($lbVal)=Is object) && ($lbVal#Null) && OB Instance of($lbVal; 4D.EntitySelection))
      $detectedKind:="entity"
     Else
      LISTBOX GET HIERARCHY(*; $name; $hierarchical; $hierarchy)
      If (Not($hierarchical))
       $detectedKind:="array"
      End if
    End case
   End if
   If ($detectedKind#"")
    $merged:=New object
    If ($wasConfigured)
     For each ($metaKey; $configured[$name])
      $merged[$metaKey]:=$configured[$name][$metaKey]
     End for each
    End if
    $merged.kind:=$detectedKind
    $merged.auto:=True
    If ((($detectedKind="array") & Not(OB Is defined($merged; "keyColumn"))) | ((New collection("collection"; "entity"; "selection").indexOf($detectedKind)>=0) & Not(OB Is defined($merged; "keyProperty"))))
     $merged.positionalKeys:=True
    End if
    If (Not(OB Is defined($merged; "label")))
     $autoLabel:=""
     If (($view.options.controls#Null) && ($view.options.controls[$name]#Null) && (Value type($view.options.controls[$name].label)=Is text) && ($view.options.controls[$name].label#""))
      $autoLabel:=$view.options.controls[$name].label
     End if
     If ($autoLabel="")
      $autoLabel:=OBJECT Get help tip(*; $name)
     End if
     If (($autoLabel="") && ($hints#Null) && ($hints[$name]#Null) && (Value type($hints[$name].tooltip)=Is text))
      $autoLabel:=$hints[$name].tooltip
     End if
     If ($autoLabel="")
      $autoLabel:=$name
     End if
     $merged.label:=$autoLabel
    End if
    $configured[$name]:=$merged
   End if
  End if
  // Auto-wire Form.* selection hints when no explicit selection Formula is configured.
  If (OB Is defined($configured; $name) && (New collection("collection"; "entity").indexOf($configured[$name].kind)>=0) && Not(OB Is defined($configured[$name]; "selection")))
   If (($hints#Null) && ($hints[$name]#Null))
    $hint:=$hints[$name]
    If ((Value type($hint.selectedItemsSource)=Is text) && (Position("Form."; $hint.selectedItemsSource)=1) && Not(OB Is defined($configured[$name]; "selectedSource")))
     $merged:=New object
     For each ($metaKey; $configured[$name])
      $merged[$metaKey]:=$configured[$name][$metaKey]
     End for each
     $merged.selectedSource:=Substring($hint.selectedItemsSource; 6)
     $configured[$name]:=$merged
    Else
     If ((Value type($hint.currentItemSource)=Is text) && (Position("Form."; $hint.currentItemSource)=1) && Not(OB Is defined($configured[$name]; "currentSource")))
      $merged:=New object
      For each ($metaKey; $configured[$name])
       $merged[$metaKey]:=$configured[$name][$metaKey]
      End for each
      $merged.currentSource:=Substring($hint.currentItemSource; 6)
      $configured[$name]:=$merged
     End if
    End if
   End if
  End if
  continue
 End if
 If (($type=Object type plugin area) & ($view.areaListProvider=True) & (Position("__AXB_Bridge"; $name)#1))
  $wasConfigured:=OB Is defined($configured; $name)
  If ($wasConfigured)
   If (($configured[$name].kind="areaList") | Not(OB Is defined($configured[$name]; "kind")))
    $merged:=OB Copy($configured[$name])
    If (Not(OB Is defined($merged; "kind")))
     $merged.kind:="areaList"
     $merged.auto:=True
    End if
    If (Not(OB Is defined($merged; "keys")))
     $merged.positionalKeys:=True
    End if
    $configured[$name]:=$merged
   End if
  Else
   $probe:=Null
   EXECUTE METHOD("AXB_ALPGrid"; $probe; "probe"; New object("objectName"; $name); New object; New object)
   If (($probe#Null) && (Value type($probe)=Is object) && ($probe.isAreaList=True) && (Num($probe.rows)<=2000))
    $autoLabel:=""
    If (($view.options.controls#Null) && ($view.options.controls[$name]#Null) && (Value type($view.options.controls[$name].label)=Is text) && ($view.options.controls[$name].label#""))
     $autoLabel:=$view.options.controls[$name].label
    End if
    If (($autoLabel="") && ($hints#Null) && ($hints[$name]#Null) && (Value type($hints[$name].tooltip)=Is text))
     $autoLabel:=$hints[$name].tooltip
    End if
    If ($autoLabel="")
     $autoLabel:=$name
    End if
    $configured[$name]:=New object("kind"; "areaList"; "auto"; True; "positionalKeys"; True; "label"; $autoLabel)
   End if
  End if
 End if
End for
For each ($name; $configured)
 If ((Find in array($objects; $name)>0) && OBJECT Get visible(*; $name))
  // Normalize only the outer object. Providers read nested configuration;
  // keeping its identity avoids deep-copying Formula objects on every poll.
  $options:=New object
  For each ($property; $configured[$name])
   $options[$property]:=$configured[$name][$property]
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
  If ($options.kind="outline")
   If ($view.nativeOutlines=Null)
    $reply:=AXB_Host("info"; New object)
    $view.nativeOutlines:=($reply.ok=True) && (Value type($reply.nativeStatus)=Is text) && (Position("; nativeOutlines 1;"; $reply.nativeStatus)>0)
   End if
   If (Not($view.nativeOutlines=True))
    return New object("ok"; False; "error"; "nativeOutlinesUnavailable")
   End if
   If ($view.nativeOutlineDisclosure=Null)
    $reply:=AXB_Host("info"; New object)
    $view.nativeOutlineDisclosure:=($reply.ok=True) && (Value type($reply.nativeStatus)=Is text) && (Position("; nativeOutlineDisclosure 1;"; $reply.nativeStatus)>0)
   End if
   If (Not($view.nativeOutlineDisclosure=True))
    return New object("ok"; False; "error"; "nativeOutlineDisclosureUnavailable")
   End if
  End if
  If ($options.kind="hierarchicalList")
   // The plugin's outline rows and disclosure carry the list; nothing else is native.
   If ($view.hierarchicalLists=Null)
    $reply:=AXB_Host("info"; New object)
    $view.hierarchicalLists:=($reply.ok=True) && (Value type($reply.nativeStatus)=Is text) && (Position("; nativeOutlines 1;"; $reply.nativeStatus)>0) && (Position("; nativeOutlineDisclosure 1;"; $reply.nativeStatus)>0)
   End if
   If (Not($view.hierarchicalLists=True))
    $result.unsupported.push(New object("object"; $name; "reason"; "hierarchicalListsUnavailable"))
    continue
   End if
   If (($request.operation="describe") | ($request.node=$id))
    $reply:=AXB_HList($request.operation; $options; $state; $request)
    If ($request.operation#"describe")
     return $reply
    End if
    If (Not($reply.ok=True))
     return $reply
    End if
    $result.nodes:=$result.nodes.concat($reply.nodes)
    $result.unsupported:=$result.unsupported.concat($reply.unsupported)
   End if
   continue
  End if
  If ($options.kind="listSubform")
   If (($request.operation="describe") | ($request.node=$id))
    $reply:=AXB_ListSubform($request.operation; $options; $state; $request)
    If ($request.operation#"describe")
     return $reply
    End if
    If (Not($reply.ok=True))
     return $reply
    End if
    $result.nodes:=$result.nodes.concat($reply.nodes)
    $result.unsupported:=$result.unsupported.concat($reply.unsupported)
   End if
   continue
  End if
  If ($options.kind="areaList")
   If (Not($view.areaListProvider=True))
    return New object("ok"; False; "error"; "areaListProviderUnavailable")
   End if
   $state.helpers:=$alpHelpers
   If (($request.operation="describe") | ($request.node=$id))
    EXECUTE METHOD("AXB_ALPGrid"; $reply; $request.operation; $options; $state; $request)
    If ($request.operation#"describe")
     return $reply
    End if
    If (Not($reply.ok=True))
     If ($options.auto=True)
      continue
     End if
     return $reply
    End if
    If (($options.auto=True) && ($reply.nodes.length>0) && ($reply.nodes[0].grid=Null) && ($state.suspended#True))
     continue
    End if
    $result.nodes:=$result.nodes.concat($reply.nodes)
   End if
   continue
  End if
  If (OBJECT Get type(*; $name)=Object type listbox)
   If ($request.operation="describe")
    $reply:=AXB_GridListbox("describe"; $options; $state; $request)
    If (Not($reply.ok=True))
     If ($options.auto=True)
      continue
     End if
     return $reply
    End if
    If (($options.auto=True) && ($reply.nodes.length>0) && ($reply.nodes[0].grid=Null) && ($state.suspended#True))
     continue
    End if
    $result.nodes:=$result.nodes.concat($reply.nodes)
    If ($options.kind="outline")
     $result.unsupported.push(New object("object"; $name; "reason"; "groupedActionsPending"))
    End if
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
     $issues:=JSON Stringify($state.valueIssues)
     $result:=AXB_GridListbox($request.operation; $options; $state; $request)
     // Reading a page can find a value that needs a description, or no longer does. Coverage
     // is gathered when the form is described: describe it again, even if nothing is redrawn.
     If (($request.operation="readGrid") && (Compare strings(JSON Stringify($state.valueIssues); $issues; sk char codes)#0) && (AXB_FormRoots#Null))
      If (AXB_FormRoots[String(Current form window)]#Null)
       AXB_FormRoots[String(Current form window)].describeAgain:=True
      End if
     End if
     return $result
    End if
   End if
  End if
 End if
End for each
