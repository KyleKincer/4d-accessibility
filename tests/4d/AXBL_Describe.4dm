#DECLARE -> $description : Object
var $array; $collection : Object
var $definitions; $selection : Collection
var $name : Text
var $i : Integer
$definitions:=New collection
For each ($name; New collection("Sort"; "Bottom"; "Top"; "Hide"; "Duplicate"; "Reset"; "Single"; "Format"; "Rebind"; "CaseKeys"; "Scope"; "CaseLabel"; "CancelPending"; "Fault"; "Filter"; "EntityLimits"; "EntityWrong"; "EntityWrongClass"; "EntityNull"; "EntityNumeric"; "EntityComputed"; "EntityNullLabel"; "RejectSelection"; "ScopeSelection"))
 $definitions.push(New object("objectName"; $name; "id"; Lowercase($name); "role"; "button"; "label"; $name; "value"; ""; "enabled"; True))
End for each
$description:=AXB_Controls($definitions)
$array:=AXB_Listbox(Form.arrayOptions)
$collection:=AXB_Listbox(Form.collectionOptions)
$description.nodes:=$description.nodes.concat($array.nodes).concat($collection.nodes)
$description.scope:=Form.scope
$description.subforms:=New collection("LeftPicker"; "RightPicker")
If (Form.entity=True)
 Form.bufferPreserved:=([AXBItem]name="Unsaved record buffer sentinel") & Modified record([AXBItem]) & (Record number([AXBItem])=0)
End if
$selection:=New collection
For ($i; 1; Size of array(aListSelected))
 If (aListSelected{$i})
  $selection.push(aListID{$i})
 End if
End for
// Fixture-only receipt recorder; production describe callbacks remain read-only.
If ((Value type(Form.axbForm.receipt)=Is object) & (Form.axbForm.receipt#Null))
 Form.lastReceipt:=Form.axbForm.receipt
End if
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "runId"; Form.runId; "compiled"; Is compiled mode; "entity"; Form.entity; "bufferPreserved"; Form.bufferPreserved; "bridgeError"; Form.axbError; "arraySelected"; $selection; "collectionSelected"; Form.selected.extract("id"); "arrayFirst"; aListID{1}; "collectionFirst"; Form.rows[0].id; "arrayNodes"; $array.nodes; "collectionNodes"; $collection.nodes; "lastResult"; Form.lastResult; "hooks"; Form.hooks; "nativeEvents"; Form.nativeEvents; "keyTest"; Form.keyTest; "receipt"; Form.lastReceipt; "revision"; Form.axbForm.revision; "leftSelected"; Form.leftPicker.selectedItems.extract("id"); "rightSelected"; Form.rightPicker.selectedItems.extract("id"); "leftSummary"; Form.leftPicker.selectionSummary; "rightSummary"; Form.rightPicker.selectionSummary)))
