var $reply; $state; $command; $options; $metadata : Object
var $name; $text : Text
var $ref; $sublist : Integer
var $expanded : Boolean
Case of
 : (Form event code=On Load)
  OBJECT SET ENABLED(*; "Disabled"; False)
  OBJECT SET LIST BY REFERENCE(*; "ValueChoice"; Choice list; DropdownList)
  OBJECT SET LIST BY REFERENCE(*; "ReferenceChoice"; Choice list; DropdownList)
  OBJECT SET FORMAT(*; "Numbers"; "0.0")
  OBJECT SET FORMAT(*; "NumberChoice"; "0.0")
  Form.valueChoice:="Red"
  Form.referenceChoice:=101
  $metadata:=New object
  For each ($name; New collection("Numbers"; "Integers"; "Dates"; "Times"; "ObjectChoice"; "NumberChoice"; "ValueChoice"; "ReferenceChoice"; "Hierarchical"; "Placeholder"; "Disabled"; "Unhandled"; "Note"))
   $metadata[$name]:=New object("label"; $name)
  End for each
  $options:=New object("label"; "Dropdown controls"; "controls"; $metadata)
  Form.start:=AXB_Form("start"; $options)
  SET TIMER(6)
 : (Form event code=On Timer)
  If (File("/RESOURCES/command.json").exists)
   $command:=JSON Parse(File("/RESOURCES/command.json").getText())
   File("/RESOURCES/command.json").delete()
   Case of
    : ($command.action="replace")
     Form.objectChoice:=New object("values"; New collection("Oak"; "Birch"); "index"; 1; "private"; "still-private")
    : ($command.action="close")
     CANCEL
   End case
   Form.sequence:=$command.sequence
  End if
  $state:=New object("ready"; True; "start"; Form.start; "sequence"; Form.sequence; "events"; Form.events; "bridgeError"; Form.axbError; "failure"; Form.axbFailure; "note"; Form.note)
  $state.diagnostics:=AXB_Form("diagnostics"; New object)
  $state.objectIndex:=Form.objectChoice.index
  $state.referenceValue:=Form.referenceChoice
  $state.textValue:=Form.valueChoice
  $state.numberIndex:=DropdownNumbers
  GET LIST ITEM(DropdownHierarchy; *; $ref; $text)
  $state.hierarchy:=New object("reference"; $ref; "text"; $text)
  GET LIST ITEM(DropdownHierarchy; 1; $ref; $text; $sublist; $expanded)
  $state.hierarchy.expanded:=$expanded
  $state.privateValue:=Form.objectChoice.private
  File("/RESOURCES/status.json").setText(JSON Stringify($state))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
