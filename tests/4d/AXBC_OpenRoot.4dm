var $window : Integer
var $data : Object
$data:=Form
$window:=Open form window("SharedRoot"; Plain form window)
DIALOG("SharedRoot"; $data)
CLOSE WINDOW($window)
Form.rootClosed:=Num(Form.rootClosed)+1
