#DECLARE -> $description : Object
var $definitions : Collection
var $name : Text
$definitions:=New collection
For each ($name; New collection("Sort"; "Hide"; "Disable"; "Replace"; "Identity"; "Reload"; "BadKey"; "Loaded"))
 $definitions.push(New object("objectName"; $name; "id"; Lowercase($name); "role"; "button"; "label"; $name; "value"; ""; "enabled"; True))
End for each
$description:=AXB_Controls($definitions)
$description.subforms:=New collection("Left"; "Right")
// Record the previous cycle's receipt before the bridge acknowledges it.
// A timer alone can miss that short-lived state.
AXBA_State(Form)
