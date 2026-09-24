#DECLARE($name : Text; $config : Object) -> $data : Object
$data:=New object("config"; $config; "kind"; "child"; "initialName"; $name; "closed"; False; "calls"; 0; "humanEvents"; 0; "timerFirings"; 0; "loadCount"; 0; "closeCleanupCalls"; 0)
$data.Name:=Formula(AXBD_Name)
$data.Greet:=Formula(AXBD_Click)
$data.Close:=Formula(AXBD_CloseAction)
