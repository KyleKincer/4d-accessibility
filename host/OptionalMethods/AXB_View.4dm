// Fixed recursive entry point for a registered form/subform instance.
// Every path comes from the application's describe callback, never an AX request.
#DECLARE($request : Object) -> $result : Object
var $view; $description; $node; $copy; $route; $child; $packet; $options; $created; $registry; $grids; $issue : Object
var $name; $prefix; $id; $key; $registration : Text
var $frame; $clip; $offset; $path; $lineage; $unsupported : Collection
var $left; $top; $right; $bottom; $originX; $originY : Integer
var $x; $y; $r; $b : Real
var $allowed; $replace; $reading; $readOnly : Boolean
var $pointer : Pointer
ARRAY TEXT($objects; 0)
ARRAY POINTER($variables; 0)
ARRAY LONGINT($pages; 0)
$result:=New object("ok"; False; "error"; "invalidView"; "status"; "rejected"; "message"; "Form instance is unavailable")
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
If ($request.autoParent#Null)
 // Each path owns its provider state, even when two children bind the same
 // business object. Never store automatic child state on that shared object.
 $name:=$request.container
 $options:=New object("label"; $name)
 $registration:=""
 If ((Form.axbView#Null) && Not(Form.axbView.root=True))
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
  $view:=Form.axbView
 End if
End if
If (($view=Null) | (Value type($view)#Is object))
 $result.error:="unregisteredView"
 return
End if
If ($view.automatic=True)
 $description:=AXB_Discover($view.options)
 $view.discovery:=$description
 $grids:=AXB_Grids($view; New object("operation"; "describe"))
 If (Not($grids.ok=True))
  return $grids
 End if
 $unsupported:=New collection
 For each ($issue; $description.unsupported)
  $allowed:=False
  If ($issue.reason="providerPending")
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
 $description.nodes:=$description.nodes.concat($grids.nodes)
 $description.unsupported:=$description.unsupported.concat($grids.unsupported)
 $description.unsupported:=$description.unsupported.concat(AXB_ControlGroups($description.nodes; $view.options))
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
  // Keep deferred formulas and their form-owned data by reference. Only this
  // hop's path and depth change; no deep copy of callback objects is needed.
  $packet:=New object
  For each ($key; $request)
   $packet[$key]:=$request[$key]
  End for each
  $packet.path:=$request.path.slice(1)
  $packet.depth:=$request.depth+1
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
     $result:=AXB_ControlAction($request.action; $view.options)
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
$offset:=New collection($originX-$request.rootOrigin[0]; $originY-$request.rootOrigin[1])
For each ($node; $description.nodes)
 $copy:=OB Copy($node)
 If ($request.depth>0)
  $copy.label:=Substring($view.label+": "+$node.label; 1; 512)
 End if
 $id:=$prefix+$node.id
 $copy.id:=$id
 If (Value type($node.objectName)=Is text)
  $registry.controlContexts[$id]:=New object("formName"; $view.formName; "origin"; $view.origin; "bindingKey"; $view.bindingKey)
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
  $copy.clip:=$clip
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
End for each
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
    $packet:=New object("operation"; "describe"; "path"; $path; "offset"; New collection($left+$offset[0]; $top+$offset[1]); "clip"; New collection($x; $y; New collection(0; $r-$x).max(); New collection(0; $b-$y).max()); "enabled"; $request.enabled & Not($description.enabled=False) & OBJECT Get enabled(*; $name); "depth"; $request.depth+1)
    $packet.ancestors:=$lineage
    $packet.navigation:=$request.navigation.concat(New collection($top; $left))
    $packet.rootOrigin:=$request.rootOrigin
    $packet.rootView:=$request.rootView
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
