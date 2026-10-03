"""Build two independent, clipped hierarchy children in the owned fixture."""
import json


def prepare(sources):
    methods = sources / "Methods"
    forms = sources / "Forms"
    probe = forms / "Probe"
    definition = json.loads((probe / "form.4DForm").read_text())
    # Compile both standalone and nested layouts together. Drivers select one
    # through a resource, keeping source and compiled artifacts identical.
    standalone = forms / "StandaloneProbe"
    for path in probe.rglob("*"):
        if path.is_file():
            destination = standalone / path.relative_to(probe)
            destination.parent.mkdir(exist_ok=True, parents=True)
            destination.write_bytes(path.read_bytes())
    (standalone / "method.4dm").write_text("AXHO_Form\n")
    original_startup = (sources / "DatabaseMethods/onStartup.4dm").read_text()
    (methods / "AXHS_Standalone.4dm").write_text(original_startup.replace('"Probe"', '"StandaloneProbe"'))
    original_configuration = (methods / "AXB_Configure.4dm").read_text().split("\n", 1)[1]
    definition["pages"][0] = None
    definition["pages"][1]["objects"]["Close"]["visibility"] = "hidden"
    (probe / "form.4DForm").write_text(json.dumps(definition, indent=2) + "\n")
    form_method = methods / "AXHP_Form.4dm"
    source = form_method.read_text()
    (methods / "AXHO_Form.4dm").write_text(source)
    timer = source[source.index(' : (Form event code=On Timer)') + len(' : (Form event code=On Timer)'):]
    timer = timer[:timer.rfind("End case")]
    timer = timer[:timer.index('  If (File("/RESOURCES/close.json").exists)')]
    form_method.write_text(source[:source.index(' : (Form event code=On Timer)')].replace('Form.disclosureCalls:=New collection', 'Form.disclosureCalls:=Form.invocationLedger\n  If (Form.loadSerial=Null)\n   Form.loadSerial:=0\n  End if\n  Form.loadSerial:=Form.loadSerial+1').replace('  GOTO OBJECT(*; "Close")\n', '').replace('  SET TIMER(6)\n', '') + "End case\n")
    (methods / "AXHP_Tick.4dm").write_text(timer.replace('Form.command:=AXHP_Command($request)', 'Form.command:=AXHP_Command($request)\n    File("/RESOURCES/request.json").delete()'))
    # The root supplies the actual current child options by reference, after
    # automatic discovery has copied the initial configuration.
    state = methods / "AXHP_State.4dm"
    state.write_text(state.read_text().replace('$context:=AXB_FormContext', '''$state.rootTick:=Form.rootTick
$state.loadSerial:=Form.loadSerial
If (Form.liveOptions#Null)
 AXHP_Options:=Form.liveOptions
 $state.runtimeGeneration:=Form.runtimeGeneration
 $state.runtimeDisclosure:=AXHP_Options.grids.Grouped.setExpanded#Null
End if
$context:=AXB_FormContext'''))
    for path in tuple(methods.glob("AXHP_*.4dm")):
        (methods / path.name.replace("AXHP_", "AXHQ_")).write_text(path.read_text().replace("AXHP_", "AXHQ_").replace('/RESOURCES/state.json', '/RESOURCES/peer-state.json').replace('/RESOURCES/request.json', '/RESOURCES/peer-request.json'))
    peer = forms / "PeerProbe"
    peer.mkdir()
    for path in probe.rglob("*"):
        if path.is_file():
            destination = peer / path.relative_to(probe)
            destination.parent.mkdir(exist_ok=True, parents=True)
            destination.write_text(path.read_text().replace("AXHP_", "AXHQ_"))
    for source_folder, name in ((probe, "ProbeReplacement"), (peer, "PeerProbeReplacement")):
        for path in source_folder.rglob("*"):
            if path.is_file():
                destination = forms / name / path.relative_to(source_folder)
                destination.parent.mkdir(exist_ok=True, parents=True)
                destination.write_bytes(path.read_bytes())
    wrapper_objects = {"Child": {"type": "subform", "detailForm": "Probe", "dataSource": "Form.child",
        "left": 18, "top": 15, "width": 580, "height": 500, "scrollbarVertical": "visible", "scrollbarHorizontal": "visible"}}
    for name, child in (("Wrapper", "Probe"), ("PeerWrapper", "PeerProbe")):
        folder = forms / name
        folder.mkdir()
        objects = json.loads(json.dumps(wrapper_objects))
        objects["Child"]["detailForm"] = child
        (folder / "form.4DForm").write_text(json.dumps({"width": 720, "height": 660, "pages": [None, {"objects": objects}]}, indent=2) + "\n")
    root = forms / "Root"
    root.mkdir()
    (root / "form.4DForm").write_text(json.dumps({"windowTitle": "AX native hierarchy probe", "width": 1350, "height": 600,
        "method": "method.4dm", "events": ["onLoad", "onTimer"], "pages": [None, {"objects": {
            "Wrapper": {"type": "subform", "detailForm": "Wrapper", "dataSource": "Form.main", "left": 20, "top": 20,
                "width": 645, "height": 400, "scrollbarVertical": "visible", "scrollbarHorizontal": "visible"},
            "PeerWrapper": {"type": "subform", "detailForm": "PeerWrapper", "dataSource": "Form.peer", "left": 685, "top": 20,
                "width": 645, "height": 400, "scrollbarVertical": "visible", "scrollbarHorizontal": "visible"},
            "Close": {"type": "button", "text": "Close probe", "action": "cancel", "left": 20, "top": 550, "width": 130, "height": 28}
        }}]}, indent=2) + "\n")
    (root / "method.4dm").write_text("AXHS_Root\n")
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''If (File("/RESOURCES/launch-variant.txt").getText()="standalone")
 AXHS_Standalone
 return
End if
ON ERR CALL("AXHP_Error")
var $window; $tree : Integer
var $data; $main; $peer : Object
var $owned : Collection
$owned:=New collection
$main:=New object("instance"; "main"; "invocations"; New collection; "child"; New object("runId"; File("/RESOURCES/run-id.txt").getText()); "ownedTrees"; $owned)
$peer:=New object("instance"; "peer"; "invocations"; New collection; "child"; New object("runId"; $main.child.runId); "ownedTrees"; $owned)
$main.child.invocationLedger:=$main.invocations
$peer.child.invocationLedger:=$peer.invocations
$data:=New object("runId"; $main.child.runId; "scope"; "Root A"; "main"; $main; "peer"; $peer; "ownedTrees"; $owned)
$window:=Open form window("Root"; Plain form window)
DIALOG("Root"; $data)
For each ($tree; $owned)
 CLEAR LIST($tree; *)
End for each
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.runId; "clearedTrees"; $owned.length)))
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "AXB_Configure.4dm").write_text('''#DECLARE($name : Text) -> $options : Object
If ($name="StandaloneProbe")
''' + original_configuration + '''
 return $options
End if
var $main; $peer : Object
$main:=New object("label"; "Main content"; "scope"; Formula(Form.scope); "grids"; New object("Grouped"; New object("kind"; "outline"; "keyColumn"; "RowKey"; "label"; "Main grouped items"; "ready"; Formula(Form.ready); "setExpanded"; Formula(AXHP_SetExpanded($1)))))
$peer:=New object("label"; "Peer content"; "scope"; Formula(Form.scope); "grids"; New object("Grouped"; New object("kind"; "outline"; "keyColumn"; "RowKey"; "label"; "Peer grouped items"; "ready"; Formula(Form.ready); "setExpanded"; Formula(AXHQ_SetExpanded($1)))))
$options:=New object("label"; "Nested hierarchy probe"; "scope"; Formula(Form.scope); "children"; New object("Wrapper"; New object("label"; "Main panel"; "children"; New object("Child"; $main)); "PeerWrapper"; New object("label"; "Peer panel"; "children"; New object("Child"; $peer))))
''')
    (methods / "AXHS_WrapperTick.4dm").write_text('''#DECLARE($request : Object) -> $state : Object
var $vertical; $horizontal; $tree : Integer
var $reply : Object
var $form : Text
If (($request#Null) && ($request.target=Form.instance))
 Case of
  : ($request.operation="childReady")
   Form.child.ready:=$request.ready
  : ($request.operation="childScope")
   Form.child.scope:=Generate UUID
  : ($request.operation="innerScroll")
   $vertical:=$request.vertical
   $horizontal:=$request.horizontal
   OBJECT SET SCROLL POSITION(*; "Child"; $vertical; $horizontal; *)
  : ($request.operation="replace")
   $tree:=Form.child.tree
   If ((Form.ownedTrees.indexOf($tree)<0) & ($tree>0))
    Form.ownedTrees.push($tree)
   End if
   $reply:=AXB_Invalidate("Child")
   Form.invalidation:=$reply
   $form:=Choose(Form.instance="main"; "ProbeReplacement"; "PeerProbeReplacement")
   OBJECT SET SUBFORM(*; "Child"; $form)
 End case
End if
If (Form.instance="main")
 AXHP_Tick
Else
 AXHQ_Tick
End if
$tree:=Form.child.tree
If ((Form.ownedTrees.indexOf($tree)<0) & ($tree>0))
 Form.ownedTrees.push($tree)
End if
OBJECT GET SCROLL POSITION(*; "Child"; $vertical; $horizontal)
$state:=New object("instance"; Form.instance; "innerScroll"; New collection($vertical; $horizontal); "invalidation"; Form.invalidation)
'''.replace(' AXHP_Tick', ' EXECUTE METHOD IN SUBFORM("Child"; "AXHP_Tick")').replace(' AXHQ_Tick', ' EXECUTE METHOD IN SUBFORM("Child"; "AXHQ_Tick")'))
    (methods / "AXHS_Root.4dm").write_text('''var $context; $view; $request; $state; $child; $main; $peer : Object
var $name : Text
var $vertical; $horizontal; $left; $top; $right; $bottom; $height : Integer
Case of
 : (Form event code=On Load)
  Form.command:=New object("id"; "")
  Form.tick:=0
  GOTO OBJECT(*; "Close")
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.tick:=Form.tick+1
  Form.main.child.rootTick:=Form.tick
  Form.peer.child.rootTick:=Form.tick
  $request:=Null
  If (File("/RESOURCES/root-request.json").exists)
   $request:=JSON Parse(File("/RESOURCES/root-request.json").getText())
   If ($request.id=Form.command.id)
    $request:=Null
   End if
  End if
  If ($request#Null)
   Case of
    : ($request.operation="rootFocus")
     GOTO OBJECT(*; "Close")
    : ($request.operation="rootScope")
     Form.scope:=Generate UUID
    : ($request.operation="outerScroll")
     $name:=Choose($request.target="main"; "Wrapper"; "PeerWrapper")
     $vertical:=$request.vertical
     $horizontal:=$request.horizontal
     OBJECT SET SCROLL POSITION(*; $name; $vertical; $horizontal; *)
    : ($request.operation="clip")
     $name:=Choose($request.target="main"; "Wrapper"; "PeerWrapper")
     $height:=$request.height
     OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
     OBJECT SET COORDINATES(*; $name; $left; $top; $right; $top+$height)
   End case
  End if
  $context:=AXB_FormContext
  If ($context#Null)
   For each ($name; New collection("Wrapper"; "PeerWrapper"))
    $view:=$context.view.children[$name]
    If (($view#Null) && ($view.children.Child#Null))
     $view:=$view.children.Child
     $child:=Choose($name="Wrapper"; Form.main.child; Form.peer.child)
     $child.liveOptions:=$view.options
     $child.runtimeGeneration:=$view.grids.Grouped.generation
    End if
   End for each
  End if
  EXECUTE METHOD IN SUBFORM("Wrapper"; "AXHS_WrapperTick"; $main; $request)
  EXECUTE METHOD IN SUBFORM("PeerWrapper"; "AXHS_WrapperTick"; $peer; $request)
  If ($request#Null)
   Form.command:=$request
   File("/RESOURCES/root-request.json").delete()
  End if
  $state:=New object("runId"; Form.runId; "rootTick"; Form.tick; "compiled"; Is compiled mode; "command"; Form.command; "scope"; Form.scope; "focus"; OBJECT Get name(Object with focus); "main"; $main; "peer"; $peer; "outerScroll"; New object; "containers"; New object; "ownedTrees"; Form.ownedTrees)
  For each ($name; New collection("Wrapper"; "PeerWrapper"))
   OBJECT GET SCROLL POSITION(*; $name; $vertical; $horizontal)
   $state.outerScroll[$name]:=New collection($vertical; $horizontal)
   OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
   $state.containers[$name]:=New collection($left; $top; $right; $bottom)
  End for each
  File("/RESOURCES/root-state.json").setText(JSON Stringify($state))
  If (File("/RESOURCES/close.json").exists)
   CANCEL
  End if
End case
''')
    compiler = methods / "Compiler_Hierarchy.4dm"
    original = compiler.read_text()
    peer_declarations = [line.replace("AXHP_", "AXHQ_") for line in original.splitlines() if "AXHP_" in line]
    compiler.write_text(original + "\n".join(peer_declarations) + "\nC_OBJECT(AXHS_WrapperTick; $0; $1)\n")
