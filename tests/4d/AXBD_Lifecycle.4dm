var $left; $top; $right; $bottom : Integer
var $name : Text
var $stopped : Boolean
Case of
 : (Form event code=On Load)
  Form.loadCount:=Form.loadCount+1
  Form.closed:=False
  Form.name:="World"
  If (Form.initialName#Null)
   Form.name:=Form.initialName
  End if
  Form.acceptedName:=Form.name
  Form.message:="Ready"
  Form.originalLoad:=True
  Form.bridgeAbsentDuringLoad:=Form.axbView=Null
  Form.timerFirings:=0
  Form.screenCenters:=New object
  For each ($name; New collection("Greet"; "Close"))
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
  If ((Form.loadCount=2) & Form.config.reopen & (Form.timerFirings>=3))
   Form.reopenStarted:=Form.axbDynamic.startResult.ok=True
   CANCEL
  End if
  AXBD_State(Form)
 : (Form event code=On Unload)
  $stopped:=Form.axbView=Null
  AXBD_ChildClose
  Form.stoppedBeforeUnload:=$stopped
  If (Form.config.nonblocking & (Form.kind#"child"))
   CALL WORKER(Current process; "AXBD_Finish"; Form)
  End if
End case
