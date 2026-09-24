#DECLARE -> $description : Object
$description:=AXB_Controls(New collection(\
 New object("objectName"; "Replace"; "id"; "replace"; "role"; "button"; "label"; "Replace left"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Rebind"; "id"; "rebind"; "role"; "button"; "label"; "Rebind right"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Misbind"; "id"; "misbind"; "role"; "button"; "label"; "Prepare different data"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Reuse"; "id"; "reuse"; "role"; "button"; "label"; "Reuse unregistered data"; "value"; ""; "enabled"; True)))
$description.subforms:=New collection("Left"; "Right")
AXBD_State(Form)
