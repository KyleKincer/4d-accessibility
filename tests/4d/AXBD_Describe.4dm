#DECLARE -> $description : Object
$description:=AXB_Controls(New collection(\
 New object("objectName"; "Name"; "id"; "name"; "role"; "textfield"; "label"; "Name"; "value"; Form.name; "enabled"; True); \
 New object("objectName"; "Greet"; "id"; "greet"; "role"; "button"; "label"; "Greet"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Status"; "id"; "status"; "role"; "text"; "label"; "Result"; "value"; Form.message; "enabled"; True)))
If (Form.config.axClose#"")
 $description.nodes.push(AXB_Controls(New collection(New object("objectName"; "Close"; "id"; "close"; "role"; "button"; "label"; "Close"; "value"; ""; "enabled"; True))).nodes[0])
End if
AXBD_State(Form)
