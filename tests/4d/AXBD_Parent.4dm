var $builder : cs.DynamicFormBuilder
var $options : Object
var $left; $top; $right; $bottom : Integer
var $name : Text
Case of
 : (Form event code=On Load)
  Form.kind:="parent"
  Form.humanReplacements:=0
  Form.left:=AXBD_ChildData("Left"; Form.config)
  Form.right:=AXBD_ChildData("Right"; Form.config)
  $options:=New object("label"; "Generated child"; "describe"; Formula(AXBD_Describe); "apply"; Formula(AXBD_Apply($1)))
  $builder:=cs.DynamicFormBuilder.new("Greeting.json").accessibility($options)
  $builder.setSubformWithTemplate("Left"; Form.left)
  Form.leftPrepared:=$builder.accessibilityResult.ok
  $builder.setSubformWithTemplate("Right"; Form.right)
  Form.rightPrepared:=$builder.accessibilityResult.ok
  Form.originalLoad:=True
  Form.bridgeAbsentDuringLoad:=Form.axbView=Null
  Form.timerFirings:=0
  Form.screenCenters:=New object
  For each ($name; New collection("Close"; "Replace"))
   OBJECT GET COORDINATES(*; $name; $left; $top; $right; $bottom)
   $left:=($left+$right)/2
   $top:=($top+$bottom)/2
   CONVERT COORDINATES($left; $top; XY Current form; XY Screen)
   Form.screenCenters[$name]:=New collection($left; $top)
  End for each
  SET TIMER(6)
  AXBD_State(Form)
 : (Form event code=On Timer)
  Form.timerFirings:=Form.timerFirings+1
  AXBD_State(Form)
 : (Form event code=On Unload)
  Form.stoppedBeforeUnload:=Form.axbView=Null
  Form.closed:=True
  SET TIMER(0)
  If (Form.config.nonblocking & (Form.kind#"child"))
   CALL WORKER(Current process; "AXBD_Finish"; Form)
  End if
End case
