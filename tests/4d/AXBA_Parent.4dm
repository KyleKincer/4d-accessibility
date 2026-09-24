var $reply : Object
var $left; $top; $right; $bottom : Integer
var $name : Text
Case of
 : (Form event code=On Load)
  Form.screenCenters:=New object
  For each ($name; New collection("Sort"; "Hide"; "Disable"; "Replace"; "Identity"; "Reload"; "BadKey"; "Loaded"; "Close"))
   OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
   $left:=($left+$right)/2
   $top:=($top+$bottom)/2
   CONVERT COORDINATES($left; $top; XY Current form; XY Screen)
   Form.screenCenters[$name]:=New collection($left; $top)
  End for each
  SET TIMER(6)
  $reply:=AXB_Form("start"; New object("label"; "AreaList subforms"; "describe"; Formula(AXBA_ParentDescribe); "apply"; Formula(AXBA_ParentApply($1)); "onError"; Formula(AXBA_Failed($1))))
 : (Form event code=On Timer)
  Form.timerFirings:=Form.timerFirings+1
  AXBA_State(Form)
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
