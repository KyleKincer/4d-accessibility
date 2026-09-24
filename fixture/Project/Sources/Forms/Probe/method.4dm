var $error : Integer
var $mode; $nativeStatus : Text
Case of
 : (Form event code=On Load)
  Form.revision:=0
  Form.lastState:=""
  Form.name:="QA Tester"
  Form.validName:=Form.name
  Form.allowed:=True
  Form.count:=0
  Form.message:="Ready. No business data is loaded."
  Form.lastSource:=""
  Form.reversed:=False
  ARRAY TEXT(aAXBKeys; 3)
  ARRAY TEXT(aAXBItems; 3)
  ARRAY TEXT(aAXBDescriptions; 3)
  aAXBKeys{1}:="line-001"
  aAXBKeys{2}:="line-002"
  aAXBKeys{3}:="line-003"
  aAXBItems{1}:="FA22VSNH"
  aAXBItems{2}:="STRATTEST"
  aAXBItems{3}:="FA22VSNH"
  aAXBDescriptions{1}:="Guitar, first invoice line"
  aAXBDescriptions{2}:="Second fixture item"
  aAXBDescriptions{3}:="Same item, different invoice line"
  $error:=AL_SetArraysNam(vAXBGrid; 1; 1; "aAXBItems")
  $error:=AL_SetArraysNam(vAXBGrid; 2; 1; "aAXBDescriptions")
  $error:=AL_SetArraysNam(vAXBGrid; 3; 1; "aAXBKeys")
  AL_SetHeaders(vAXBGrid; 1; 1; "Item")
  AL_SetHeaders(vAXBGrid; 2; 1; "Description")
  AL_SetWidths(vAXBGrid; 1; 1; 140)
  AL_SetWidths(vAXBGrid; 2; 1; 420)
  AL_SetAreaLongProperty(vAXBGrid; ALP_Area_CompHideCols; 1)
  AL_SetAreaLongProperty(vAXBGrid; ALP_Area_SelType; 0)
  AL_SetAreaLongProperty(vAXBGrid; ALP_Area_SelMultiple; 1)
  AL_SetAreaLongProperty(vAXBGrid; ALP_Area_ReadOnly; 15)
  Form.timerFirings:=0
  $mode:="interpreted"
  If (Is compiled mode)
   $mode:="compiled"
  End if
  $nativeStatus:=AXB Status
  Form.build:=$nativeStatus+"; 4D mode: "+$mode
  SET TIMER(30)
  AXB_Start(Formula(AXB_FixturePoll))
  Form.session:=Form.axb.token.session
  File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "ready"; "compiled"; Is compiled mode)))
 : (Form event code=On Timer)
  Form.timerFirings:=Form.timerFirings+1
  SET TIMER(0)
 : (Form event code=On Unload)
  AXB_Stop
End case
