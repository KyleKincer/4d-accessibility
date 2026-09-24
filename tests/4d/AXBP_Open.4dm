ON ERR CALL("AXBP_Error")
var $config; $data : Object
var $row; $window; $registration : Integer
var $icon : Picture
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
If ($config.licenseMode="registered")
 $registration:=AL_Register(File("/RESOURCES/alp.license").getText(); 1; "")
 If ($registration#0)
  File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "registration"; $registration)))
  QUIT 4D
  return
 End if
End if
ARRAY TEXT(aLeftKey; 600)
ARRAY TEXT(aLeftItem; 600)
ARRAY TEXT(aLeftDescription; 600)
ARRAY REAL(aLeftAmount; 600)
ARRAY TEXT(aLeftStyled; 600)
ARRAY TEXT(aLeftSpacer; 600)
ARRAY PICTURE(aLeftPicture; 600)
ARRAY TEXT(aRightKey; 600)
ARRAY TEXT(aRightItem; 600)
ARRAY TEXT(aRightDescription; 600)
ARRAY REAL(aRightAmount; 600)
ARRAY TEXT(aRightStyled; 600)
ARRAY TEXT(aRightSpacer; 600)
ARRAY PICTURE(aRightPicture; 600)
READ PICTURE FILE(File("/RESOURCES/ready.png").platformPath; $icon)
For ($row; 1; 600)
 aLeftKey{$row}:="line-"+String($row; "0000")
 aRightKey{$row}:=aLeftKey{$row}
 aLeftItem{$row}:="SKU"
 aRightItem{$row}:="SKU"
 aLeftDescription{$row}:="Left line "+String($row; "0000")
 aRightDescription{$row}:="Right line "+String($row; "0000")
 aLeftAmount{$row}:=$row+0.25
 aRightAmount{$row}:=$row+0.50
 aLeftStyled{$row}:="<c blue><b>Left styled "+String($row; "0000")+"</b></c>"
 aRightStyled{$row}:="<c blue><b>Right styled "+String($row; "0000")+"</b></c>"
 aLeftPicture{$row}:=$icon
 aRightPicture{$row}:=$icon
End for
$data:=New object("registration"; Choose($config.licenseMode="registered"; $registration; Null); "runId"; $config.runId; "timerTicks"; 0; "left"; New object("side"; "Left"; "scope"; "left-invoice"; "ready"; True; "note"; "Left note"); "right"; New object("side"; "Right"; "scope"; "right-invoice"; "ready"; True; "note"; "Right note"))
AXBP_LeftData:=$data.left
AXBP_RightData:=$data.right
var $bar; $menu : Text
var $item : Object
$bar:=Create menu
$menu:=Create menu
For each ($item; New collection(New object("label"; "Undo"; "action"; ak undo; "key"; "Z"); New object("label"; "Redo"; "action"; ak redo; "key"; "Z"); New object("label"; "Cut"; "action"; ak cut; "key"; "X"); New object("label"; "Copy"; "action"; ak copy; "key"; "C"); New object("label"; "Paste"; "action"; ak paste; "key"; "V")))
 APPEND MENU ITEM($menu; $item.label)
 SET MENU ITEM PROPERTY($menu; -1; Associated standard action name; $item.action)
 SET MENU ITEM SHORTCUT($menu; -1; $item.key; Command key mask+Choose($item.label="Redo"; Shift key mask; 0))
End for each
APPEND MENU ITEM($bar; "Edit"; $menu)
SET MENU BAR($bar; Current process)
$window:=Open form window("Grid"; Plain form window)
DIALOG("Grid"; $data)
$data.accepted:=(OK=1)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.runId; "accepted"; $data.accepted; "leftValue"; aLeftDescription{600}; "rightValue"; aRightDescription{600}; "left"; $data.left; "right"; $data.right)))
CLOSE WINDOW($window)
QUIT 4D
