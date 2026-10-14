// Fixed recursive entry point for a registered form/subform instance.
// Every path comes from the application's describe callback, never an AX request.
#DECLARE($request : Object) -> $result : Object
var $view; $description; $node; $other; $copy; $route; $child; $packet; $options; $created; $registry; $grids; $issue : Object
var $pageByObject : Object
var $name; $prefix; $id; $key; $registration; $standardAction : Text
var $detailForm; $listForm : Text
var $frame; $clip; $offset; $path; $lineage; $unsupported; $focusNames; $kept : Collection
var $left; $top; $right; $bottom; $originX; $originY; $position; $scrollX; $scrollY; $part : Integer
var $x; $y; $r; $b : Real
var $allowed; $replace; $reading; $readOnly; $aliases : Boolean
var $pointer; $focusPointer : Pointer
var $only; $cache; $buckets; $bucket; $described; $full : Object
var $cacheKey; $last : Text
var $reusable; $storing : Boolean
var $subformTable : Pointer
ARRAY TEXT($objects; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
ARRAY TEXT($parts; 0)
$result:=New object("ok"; False; "error"; "invalidView"; "status"; "rejected"; "message"; "Form instance is unavailable")
If ($request.paintOffset=Null)
 $request.paintOffset:=New collection(0; 0)
End if
If (Not(OB Is defined($request; "nativeEnabled")))
 $request.nativeEnabled:=$request.enabled
End if
$reading:=$request.operation="readGrid"
$readOnly:=$reading | ($request.operation="reveal")
If ($request.depth>8)
 $result.error:="subformDepthExceeded"
 return
End if
FORM GET OBJECTS($objects; $variables; $pages; Form current page+Form inherited)
If (((Value type(Form)#Is object) | (Form=Null)) & ($request.autoParent=Null))
 $result.error:="unregisteredView"
 return
End if
$registry:=AXB_FormRoots[String(Current form window)]
$aliases:=(Value type(Form)=Is object) && (Form#Null) && (New collection(4D.Object).indexOf(OB Class(Form))=0) && Not(OB Is shared(Form))
If ($request.autoParent#Null)
 // Each path owns its provider state, even when two children bind the same
 // business object. Never store automatic child state on that shared object.
 $name:=$request.container
 $options:=New object("label"; $name)
 $registration:=""
 If ($aliases && (Form.axbView#Null) && Not(Form.axbView.root=True))
  $options:=Form.axbView.options
  $registration:=Form.axbView.instance
 End if
 If ($request.autoParent.options.children#Null)
  If ($request.autoParent.options.children[$name]#Null)
   $options:=$request.autoParent.options.children[$name]
   If (Value type($options)#Is object)
    $result.error:="invalidChildOptions"
    return
   End if
   $options:=OB Copy($options)
   If (Not(OB Is defined($options; "label")))
    $options.label:=$name
   End if
  End if
 End if
 $view:=$request.autoParent.children[$name]
 $replace:=$view=Null
 If (Not($replace))
  $replace:=Not(OB Is defined($registry.bindings; $view.bindingKey)) | (New collection($registry.bindings[$view.bindingKey]).indexOf(Form)#0) | ($view.formName#Current form name) | ($view.registration#$registration)
 End if
 If ($replace)
  If ($request.operation#"describe")
   return
  End if
  $created:=AXB_ViewCreate($options)
  If (Not($created.ok=True))
   $result.error:=$created.error
   return
  End if
  $view:=$created.view
  $view.formName:=Current form name
  $view.registration:=$registration
  $request.autoParent.children[$name]:=$view
 End if
Else
 If ($request.depth=0)
  $view:=$request.rootView
 Else
  If ($aliases)
   $view:=Form.axbView
  End if
 End if
End if
If (($view=Null) | (Value type($view)#Is object))
 $result.error:="unregisteredView"
 return
End if
If ($view.automatic=True)
 If ($reading)
  // A grid page needs fresh grid state and its containing form path. Reading
  // unrelated labels/values for every page can prevent a large form's cache
  // from ever catching up. Keep the scope, instance and live-child checks
  // below, and describe the grids through their normal readiness guards.
  $description:=New object("ok"; True; "nodes"; New collection; "subforms"; New collection; "unsupported"; New collection)
  If ($request.path.length>0)
   $name:=$request.path[0]
   If ((Find in array($objects; $name)>0) && (OBJECT Get type(*; $name)=Object type subform) && OBJECT Get visible(*; $name))
    $description.subforms.push($name)
   End if
  End if
 Else
  // A form described before is described again only where its drawing changed: the objects
  // the plugin names. Anything that could change other objects' nodes describes it whole.
  $cache:=Null
  If ($request.operation="describe")
   $originX:=0
   $originY:=0
   CONVERT COORDINATES($originX; $originY; XY Current form; XY Current window)
   $cacheKey:=JSON Stringify(New collection(Current form name; FORM Get current page; $request.path; $request.ancestors; $request.enabled; $request.nativeEnabled; $request.clip; $request.paintOffset; $request.navigation; $request.rootOrigin; $originX; $originY; $view.instance))
   If (($request.changes#Null) && Not($request.changes.whole=True) && ($view.described#Null))
    If (Compare strings($view.described.key; $cacheKey; sk char codes)=0)
     $cache:=$view.described
     $only:=New object
     For each ($name; $request.changes.names)
      If (OB Is defined($cache.owners; $name))
       $name:=$cache.owners[$name]
      End if
      Case of
       : (OB Is defined($cache.subforms; $name))
        // A subform's own form describes its objects.
       : (OB Is defined($cache.structural; $name))
        $cache:=Null
       : (OB Is defined($cache.known; $name))
        $only[$name]:=True
       : (Find in array($objects; $name)>0)
        // An object the last complete description did not see.
        $cache:=Null
      End case
      If ($cache=Null)
       break
      End if
     End for each
    End if
   End if
  End if
  If ($cache=Null)
   $description:=AXB_Discover($view.options; $view.tabs; $request.paintOffset)
   $view.discovery:=$description
  Else
   $description:=AXB_Discover($view.options; $view.tabs; $request.paintOffset; $only; $cache.labels; $cache.entry)
   $description.subforms:=$cache.subformList.copy()
  End if
 End if
 $grids:=AXB_Grids($view; New object("operation"; "describe"))
 If (Not($grids.ok=True))
  return $grids
 End if
 $unsupported:=New collection
 For each ($issue; $description.unsupported)
  $allowed:=False
  If (New collection("providerPending"; "listSubformPending").indexOf($issue.reason)>=0)
   For each ($node; $grids.nodes)
    If (Compare strings($node.objectName; $issue.object; sk char codes)=0)
     $allowed:=True
    End if
   End for each
  End if
  If (Not($allowed))
   $unsupported.push($issue)
  End if
 End for each
 $description.unsupported:=$unsupported
 For each ($node; $grids.nodes)
  If ($node.grid=Null)
   $name:=$node.objectName
   $key:="gridUnavailable"
   If ($view.grids[$name].suspended=True)
    $key:="gridLoading"
   End if
   $description.unsupported.push(New object("object"; $name; "reason"; $key))
  End if
 End for each
 // A configured grid describes its list box in full, in place of the drawn rows.
 If ($grids.nodes.length>0)
  $kept:=New collection
  For each ($node; $description.nodes)
   $allowed:=True
   If ($node.role="drawnTable")
    For each ($other; $grids.nodes)
     If (Compare strings($other.objectName; $node.objectName; sk char codes)=0)
      $allowed:=False
     End if
    End for each
   End if
   If ($allowed)
    $kept.push($node)
   End if
  End for each
  $description.nodes:=$kept
 End if
 $description.nodes:=$description.nodes.concat($grids.nodes)
 $description.unsupported:=$description.unsupported.concat($grids.unsupported)
 $description.unsupported:=$description.unsupported.concat(AXB_ControlGroups($description.nodes; $view.options))
 // A standard page-navigation tab relates to the actual current page. Do
 // not infer page ownership for tabs whose application method loads data.
 $pageByObject:=New object
 For ($position; 1; Size of array($objects))
  $pageByObject[$objects{$position}]:=$pages{$position}
 End for
 For each ($node; $description.nodes)
  If (($node.role="tab") && ($node.value=True))
   $standardAction:=OBJECT Get action(*; $node.objectName)
   If (($standardAction=ak goto page) | (Position(ak goto page+"?"; $standardAction)=1))
    $node.linked:=New collection
    For each ($other; $description.nodes)
     If (OB Is defined($pageByObject; $other.objectName) && ($pageByObject[$other.objectName]>0) && $other.visible && ($other.parent=Null) && ($other.objectName#$node.objectName))
      $node.linked.push($other.id)
     End if
    End for each
   End if
  End if
 End for each
 If (OB Is defined($view.options; "scope"))
  If (Value type($view.options.scope)=Is text)
   $description.scope:=$view.options.scope
  Else
   If ((Value type($view.options.scope)=Is object) && OB Instance of($view.options.scope; 4D.Function))
    $description.scope:=$view.options.scope.call()
   Else
    $result.error:="invalidScope"
    return
   End if
  End if
 End if
Else
 $description:=$view.describe.call()
End if
If (($description=Null) | (Value type($description)#Is object))
 return
End if
If ($description.ok=False)
 $result.error:=$description.error
 return
End if
If ((Value type($description.nodes)#Is collection) | ($description.nodes=Null))
 return
End if
If (Not(OB Is defined($description; "scope")))
 $description.scope:=""
End if
If (Value type($description.scope)#Is text)
 $result.error:="invalidScope"
 return
End if
If (($request.operation="apply") | ($request.operation="confirm") | ($request.operation="reveal") | $reading)
 If (($view.instance#$request.lineage[$request.depth]) | (Compare strings($description.scope; $view.scope; sk char codes)#0) | (($description.enabled=False) & Not($readOnly)))
  return
 End if
 // Re-enter only an allowed, visible subform. Mutations also require enabled
 // ancestors; reading and reveal can inspect disabled content.
 If ($request.path.length>0)
  $name:=$request.path[0]
  If ((Value type($description.subforms)#Is collection) | (Find in array($objects; $name)<1))
   return
  End if
  If ($description.subforms.indexOf($name)<0)
   return
  End if
  If ((OBJECT Get type(*; $name)#Object type subform) | Not(OBJECT Get visible(*; $name)) | (Not(OBJECT Get enabled(*; $name)) & Not($readOnly)))
   return
  End if
  OBJECT GET SUBFORM(*; $name; $subformTable; $detailForm; $listForm)
  If ($listForm#"")
   $result.error:="listSubformPending"
   return
  End if
  // Keep deferred formulas and their form-owned data by reference. Only this
  // hop's path and depth change; no deep copy of callback objects is needed.
  $packet:=New object
  For each ($key; $request)
   $packet[$key]:=$request[$key]
  End for each
  $packet.path:=$request.path.slice(1)
  $packet.depth:=$request.depth+1
  OBJECT GET SCROLL POSITION(*; $name; $scrollY; $scrollX)
  $packet.paintOffset:=New collection($request.paintOffset[0]+$scrollX; $request.paintOffset[1]+$scrollY)
  OB REMOVE($packet; "autoParent")
  OB REMOVE($packet; "container")
  If ($view.automatic=True)
   $packet.autoParent:=$view
   $packet.container:=$name
  End if
  EXECUTE METHOD IN SUBFORM($name; "AXB_View"; $result; $packet)
  If (($request.operation="reveal") & ($result.ok=True))
   // Unwind from the innermost child. Each parent scrolls its own container.
   $result:=AXB_ScrollChild($name; $result.frame)
  End if
  return
 End if
 If (($view.instance#$request.instance) | (Compare strings($description.scope; $request.scope; sk char codes)#0))
  return
 End if
 If (Not($view.automatic=True) & Not($reading))
  If ((Value type($view.apply)#Is object) | ($view.apply=Null))
   return
  End if
  If (Not(OB Instance of($view.apply; 4D.Function)))
   return
  End if
 End if
 $allowed:=False
 For each ($node; $description.nodes)
  If ((Compare strings($node.id; $request.action.node; sk char codes)=0) & ($node.enabled | $readOnly) & $node.visible)
   If (($request.operation="reveal") & ($view.automatic=True))
    $originX:=0
    $originY:=0
    CONVERT COORDINATES($originX; $originY; XY Current form; XY Current window)
    return New object("ok"; True; "frame"; New collection($node.frame[0]+$originX; $node.frame[1]+$originY; $node.frame[2]; $node.frame[3]))
   End if
   $allowed:=True
  End if
 End for each
 If ($request.operation="reveal")
  return
 End if
 If ($allowed)
  If ($reading)
   return AXB_Grids($view; New object("operation"; "readGrid"; "node"; $request.action.node; "requests"; $request.requests))
  End if
  If ($request.operation="confirm")
   $result:=$request.confirm.call(Null; $request.data)
  Else
   If (($view.automatic=True) & ($view.apply=Null))
    If (Position("grid."; $request.action.node)=1)
     $result:=AXB_Grids($view; New object("operation"; "apply"; "node"; $request.action.node; "action"; $request.action))
    Else
     $result:=AXB_ControlAction($request.action; $view.options; $view.tabs; $request.paintOffset)
    End if
   Else
    $result:=$view.apply.call(Null; $request.action)
   End if
  End if
  If (($result=Null) | (Value type($result)#Is object))
   $result:=New object("status"; "rejected"; "message"; "Handler returned no completion result")
  End if
  If (($result.status="pending") & (Value type($result.confirm)=Is object) & ($result.confirm#Null))
   If (OB Instance of($result.confirm; 4D.Function))
    return
   End if
  End if
  $result:=AXB_Result($result)
 End if
 return
End if
// Scope changes invalidate all retained controls, including identical row keys.
If (Compare strings($description.scope; $view.scope; sk char codes)#0)
 $view.scope:=$description.scope
 $view.instance:=Generate UUID
End if
$lineage:=$request.ancestors.concat(New collection($view.instance))
$prefix:=$view.instance+"."+Substring(Generate digest(JSON Stringify(New collection($request.path; $lineage)); SHA256 digest); 1; 16)+"."
If ($cache#Null)
 If (Compare strings($prefix; $cache.prefix; sk char codes)#0)
  // A new scope renames every node: describe the whole form.
  $full:=New object
  For each ($key; $request)
   $full[$key]:=$request[$key]
  End for each
  OB REMOVE($full; "changes")
  return AXB_View($full)
 End if
End if
// Record what each object produces, to reuse it while the object does not change.
$storing:=($view.automatic=True) & ($request.operation="describe") & ($cache=Null)
$buckets:=New object
$reusable:=True
$last:=""
$result:=New object("ok"; True; "nodes"; New collection; "routes"; New object; "issues"; New collection)
If (($view.automatic=True) & (Value type($description.unsupported)=Is collection))
 For each ($issue; $description.unsupported)
  $copy:=New object("path"; $request.path.copy(); "object"; $issue.object; "reason"; $issue.reason)
  If (Value type($issue.column)=Is text)
   $copy.column:=$issue.column
  End if
  $result.issues.push($copy)
 End for each
End if
// Ask 4D for the actual subform origin, including borders and scrolling.
$originX:=0
$originY:=0
CONVERT COORDINATES($originX; $originY; XY Current form; XY Current window)
$registry.bindings[$view.bindingKey]:=Form
$registry.seen[$view.bindingKey]:=True
$view.formName:=Current form name
$view.origin:=New collection($originX; $originY)
If ($request.operation="describe")
 // Focus can name an unsupported object or a listbox part that has no
 // ordinary node. Keep the complete native name set for ownership checks.
 $focusNames:=Null
 If ($registry.focusPointerName#"")
  $focusNames:=New collection
  $focusPointer:=OBJECT Get pointer(Object with focus)
  For ($position; 1; Size of array($objects))
   $name:=$objects{$position}
   $focusNames.push($name)
   If ((Compare strings($name; $registry.focusPointerName; sk char codes)=0) && Not(Is nil pointer($focusPointer)))
    $pointer:=OBJECT Get pointer(Object named; $name)
    If (($pointer=$focusPointer) && ($registry.focusPointerOwners.indexOf($view.bindingKey)<0))
     $registry.focusPointerOwners.push($view.bindingKey)
    End if
   End if
   If (OBJECT Get type(*; $name)=Object type listbox)
    LISTBOX GET OBJECTS(*; $name; $parts)
    For ($part; 1; Size of array($parts))
     $focusNames.push($parts{$part})
     If (((Compare strings($parts{$part}; $registry.focusPointerName; sk char codes)=0) | (Compare strings($name; $registry.focusPointerName; sk char codes)=0)) && Not(Is nil pointer($focusPointer)))
      $pointer:=OBJECT Get pointer(Object named; $parts{$part})
      If (($pointer=$focusPointer) && ($registry.focusPointerOwners.indexOf($view.bindingKey)<0))
       $registry.focusPointerOwners.push($view.bindingKey)
      End if
     End if
    End for
   End if
  End for
 End if
 // A provider may refuse mutations while its native form still owns focus.
 $registry.formContexts[$view.bindingKey]:=New object("formName"; $view.formName; "origin"; $view.origin; "bindingKey"; $view.bindingKey; "path"; $request.path; "focusNames"; $focusNames; "enabled"; $request.nativeEnabled)
 AXB_FormObserver("bind"; New object("bindingKey"; $view.bindingKey; "formName"; $view.formName; "origin"; $view.origin; "path"; $request.path; "data"; Form))
End if
$offset:=New collection($originX-$request.rootOrigin[0]; $originY-$request.rootOrigin[1])
For each ($node; $description.nodes)
 $copy:=OB Copy($node)
 If ($request.depth>0)
  $copy.label:=Substring($view.label+": "+$node.label; 1; 512)
 End if
 $id:=$prefix+$node.id
 $copy.id:=$id
 // Public paths use container names, never the UUID-bearing action route.
 $key:=$node.id
 If (Value type($node.objectName)=Is text)
  $key:=$node.objectName
  If ($view.options.controls#Null)
   If ($view.options.controls[$key]#Null)
    If (Value type($view.options.controls[$key].automationKey)=Is text)
     $key:=$view.options.controls[$key].automationKey
    End if
   End if
  End if
 End if
 If (Value type($node.automationKey)=Is text)
  $key:=$node.automationKey
 End if
 $copy.automationPath:=$request.path.concat(New collection($key))
 If ($node.automationChild#Null)
  $copy.automationPath:=$copy.automationPath.concat($node.automationChild)
 End if
 If (Value type($node.objectName)=Is text)
  $registry.controlContexts[$id]:=New object("formName"; $view.formName; "origin"; $view.origin; "bindingKey"; $view.bindingKey; "path"; $request.path)
  // Keep host pointers outside the serializable tree. An unnamed button has
  // its own dynamic variable even in repeated instances of the same form.
  $pointer:=OBJECT Get pointer(Object named; $node.objectName)
  If (Not(Is nil pointer($pointer)))
   $registry.controlPointers[$id]:=$pointer
  End if
  If (($node.grid#Null) && ($node.cellFocus#Null))
   $pointer:=OBJECT Get pointer(Object named; $node.cellFocus.column)
   If (Not(Is nil pointer($pointer)))
    $registry.cellPointers[$id]:=$pointer
   End if
  End if
 End if
 If (OB Is defined($node; "parent"))
  $copy.parent:=$prefix+$node.parent
 End if
 If (OB Is defined($node; "labelledBy"))
  $copy.labelledBy:=$prefix+$node.labelledBy
 End if
 If (OB Is defined($node; "linked"))
  $copy.linked:=New collection
  For each ($key; $node.linked)
   $copy.linked.push($prefix+$key)
  End for each
 End if
 $copy.enabled:=$node.enabled & $request.enabled & Not($description.enabled=False)
 $copy.revealable:=$view.automatic=True
 $frame:=$node.frame
 // Navigation follows the form layout, independently of its scroll offsets.
 $copy.navigation:=$request.navigation.concat(New collection($frame[1]; $frame[0]))
 $copy.frame:=New collection($frame[0]+$offset[0]; $frame[1]+$offset[1]; $frame[2]; $frame[3])
 $clip:=$request.clip
 If (Value type($node.clip)=Is collection)
  $clip:=New collection($node.clip[0]+$offset[0]; $node.clip[1]+$offset[1]; $node.clip[2]; $node.clip[3])
  If (Value type($request.clip)=Is collection)
   $x:=New collection($clip[0]; $request.clip[0]).max()
   $y:=New collection($clip[1]; $request.clip[1]).max()
   $r:=New collection($clip[0]+$clip[2]; $request.clip[0]+$request.clip[2]).min()
   $b:=New collection($clip[1]+$clip[3]; $request.clip[1]+$request.clip[3]).min()
   $clip:=New collection($x; $y; New collection(0; $r-$x).max(); New collection(0; $b-$y).max())
  End if
 End if
 If ((Value type($clip)=Is collection) & ($clip#Null))
  // Store a fresh rectangle per node. In 4D 20.8, assigning one shared clip collection to
  // hundreds of node objects cost about 1.7 ms each, most of a large form's description.
  $copy.clip:=New collection($clip[0]; $clip[1]; $clip[2]; $clip[3])
  If (Not($view.automatic=True))
   $copy.visible:=$node.visible & AXB_Intersects($copy.frame; $clip)
  End if
 End if
 If ($copy.grid#Null)
  $copy.grid:=AXB_GridGeometry($node.grid; $offset; $clip)
 End if
 $result.nodes.push($copy)
 If (($view.automatic=True) & $copy.visible & ($copy.missingLabel=True))
  $result.issues.push(New object("path"; $request.path.copy(); "object"; $copy.objectName; "reason"; "missingLabel"))
 End if
 $result.routes[$id]:=New object("path"; $request.path; "lineage"; $lineage; "instance"; $view.instance; "scope"; $view.scope; "localID"; $node.id; "node"; $copy)
 If (Value type($node.objectName)=Is text)
  If ($buckets[$node.objectName]=Null)
   $buckets[$node.objectName]:=New object("nodes"; New collection; "first"; $result.nodes.length-1)
  Else
   // An object whose nodes are not together cannot be replaced in place.
   $reusable:=$reusable & (Compare strings($last; $node.objectName; sk char codes)=0)
  End if
  $last:=$node.objectName
  $bucket:=$buckets[$node.objectName]
  $bucket.nodes.push($copy)
 Else
  $reusable:=False
 End if
End for each
If ($cache#Null)
 // Replace each changed object's nodes in place. An object that appeared, disappeared or
 // changed shape describes the whole form.
 For each ($name; $buckets)
  If ((Not(OB Is defined($cache.counts; $name))) || ($cache.counts[$name]#$buckets[$name].nodes.length))
   $reusable:=False
  End if
 End for each
 For each ($name; $only)
  If (Not(OB Is defined($buckets; $name)) && (Num($cache.counts[$name])>0))
   $reusable:=False
  End if
 End for each
 If (Not($reusable))
  $full:=New object
  For each ($key; $request)
   $full[$key]:=$request[$key]
  End for each
  OB REMOVE($full; "changes")
  return AXB_View($full)
 End if
 For each ($name; $buckets)
  $position:=$cache.first[$name]
  For each ($node; $buckets[$name].nodes)
   $cache.nodes[$position]:=$node
   $cache.routes[$node.id]:=$result.routes[$node.id]
   $position:=$position+1
  End for each
 End for each
 $result.nodes:=$cache.nodes
 $result.routes:=$cache.routes
 If ($cache.subformList.length>0)
  // Subforms add their routes to this view's: keep the reused ones apart.
  $result.routes:=New object
  For each ($key; $cache.routes)
   $result.routes[$key]:=$cache.routes[$key]
  End for each
 End if
 $result.issues:=$cache.issues.copy()
 $registry.partialDescriptions:=Num($registry.partialDescriptions)+1
End if
If ($storing)
 $registry.wholeDescriptions:=Num($registry.wholeDescriptions)+1
 OB REMOVE($view; "described")
 If ($reusable)
  $described:=New object("key"; $cacheKey; "prefix"; $prefix; "entry"; $description.entry; "nodes"; $result.nodes; "routes"; New object; "first"; New object; "counts"; New object; "known"; New object; "structural"; New object; "owners"; New object; "subforms"; New object; "subformList"; New collection; "labels"; New collection; "issues"; $result.issues.copy())
  For each ($key; $result.routes)
   $described.routes[$key]:=$result.routes[$key]
  End for each
  For each ($name; $buckets)
   $described.first[$name]:=$buckets[$name].first
   $described.counts[$name]:=$buckets[$name].nodes.length
  End for each
  For ($position; 1; Size of array($objects))
   $described.known[$objects{$position}]:=True
  End for
  If (Value type($description.subforms)=Is collection)
   $described.subformList:=$description.subforms.copy()
   For each ($name; $description.subforms)
    $described.subforms[$name]:=True
   End for each
  End if
  For each ($node; $description.nodes)
   If (Value type($node.objectName)=Is text)
    // Captions label their neighbours, and radio buttons, tabs and groups relate to other
    // objects: changing one describes the whole form.
    If ((New collection("text"; "radio"; "tab"; "tabgroup"; "group").indexOf($node.role)>=0) | ($buckets[$node.objectName].nodes.length>1))
     $described.structural[$node.objectName]:=True
    End if
    If (($node.role="text") && Match regex("(?s).*[[:alnum:]].*"; $node.label))
     $described.labels.push($node)
    End if
    If ((($node.role="drawnTable") | ($node.grid#Null)) && (OBJECT Get type(*; $node.objectName)=Object type listbox))
     // 4D draws a list box's columns and headers in layers of their own.
     LISTBOX GET OBJECTS(*; $node.objectName; $parts)
     For ($part; 1; Size of array($parts))
      $described.owners[$parts{$part}]:=$node.objectName
     End for
    End if
   End if
  End for each
  // Declared layers let any control cover a button: such a form is always described whole.
  If ($view.options.controls#Null)
   For each ($name; $view.options.controls)
    If (($view.options.controls[$name].layer#Null) && ($view.options.controls[$name].layer#0))
     $described:=Null
     break
    End if
   End for each
  End if
  If ($described#Null)
   $view.described:=$described
  End if
 End if
End if
If (Value type($description.subforms)=Is collection)
 For each ($name; $description.subforms)
  If (Find in array($objects; $name)>0)
   If ((OBJECT Get type(*; $name)=Object type subform) & OBJECT Get visible(*; $name))
   OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
   If (($right<=$left) | ($bottom<=$top))
    // A collapsed container has no usable viewport, even if 4D calls it visible.
    continue
   End if
    $x:=$left+$offset[0]
    $y:=$top+$offset[1]
    $r:=$right+$offset[0]
    $b:=$bottom+$offset[1]
    $clip:=$request.clip
    If ((Value type($clip)=Is collection) & ($clip#Null))
     $x:=New collection($x; $clip[0]).max()
     $y:=New collection($y; $clip[1]).max()
     $r:=New collection($r; $clip[0]+$clip[2]).min()
     $b:=New collection($b; $clip[1]+$clip[3]).min()
    End if
    $path:=$request.path.concat(New collection($name))
    OBJECT GET SUBFORM(*; $name; $subformTable; $detailForm; $listForm)
    If ($listForm#"")
     // Explicit child discovery must not publish a repeated list as one row.
     $result.issues.push(New object("path"; $path; "object"; $name; "reason"; "listSubformPending"))
     continue
    End if
    $packet:=New object("operation"; "describe"; "path"; $path; "offset"; New collection($left+$offset[0]; $top+$offset[1]); "clip"; New collection($x; $y; New collection(0; $r-$x).max(); New collection(0; $b-$y).max()); "enabled"; $request.enabled & Not($description.enabled=False) & OBJECT Get enabled(*; $name); "depth"; $request.depth+1)
    $packet.ancestors:=$lineage
    $packet.nativeEnabled:=$request.nativeEnabled & OBJECT Get enabled(*; $name)
    $packet.navigation:=$request.navigation.concat(New collection($top; $left))
    $packet.rootOrigin:=$request.rootOrigin
    $packet.rootView:=$request.rootView
    $packet.changes:=$request.changes
    OBJECT GET SCROLL POSITION(*; $name; $scrollY; $scrollX)
    $packet.paintOffset:=New collection($request.paintOffset[0]+$scrollX; $request.paintOffset[1]+$scrollY)
    If ($view.automatic=True)
     $packet.autoParent:=$view
     $packet.container:=$name
    End if
    $child:=Null
    EXECUTE METHOD IN SUBFORM($name; "AXB_View"; $child; $packet)
    If ($child=Null)
     // A visible container can be an empty placeholder awaiting a form.
     $child:=New object("ok"; False; "error"; "unregisteredView")
    End if
    If ($child.ok=True)
     $result.nodes:=$result.nodes.concat($child.nodes)
     $result.issues:=$result.issues.concat($child.issues)
     For each ($key; $child.routes)
      $result.routes[$key]:=$child.routes[$key]
     End for each
    Else
     If ($child.error#"unregisteredView")
      $result:=$child
      return
     End if
    End if
   End if
  End if
 End for each
End if
