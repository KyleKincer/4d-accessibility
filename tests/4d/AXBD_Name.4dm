var $reply : Object
Form.humanEvents:=Form.humanEvents+1
$reply:=AXBD_Apply(New object("node"; "name"; "operation"; "setValue"; "value"; Form.name))
