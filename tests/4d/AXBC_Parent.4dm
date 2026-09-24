var $reply; $options : Object
Case of
 : (Form event code=On Load)
  Form.shared:=New object("name"; "Shared"; "clicked"; 0)
  Form.left:=Form.shared
  Form.right:=Form.shared
  Form.panel:=New object("inner"; New object("name"; "Nested"; "clicked"; 0))
  Form.record:="first"
  Form.ticks:=0
  Form.hidden:=False
  Form.disabled:=False
  AXBC_Events:=New collection
  AXBC_UnboundName:="Unbound"
  AXBC_UnboundClicks:=0
  $options:=New object("label"; "Automatic child forms"; "scope"; Formula(Form.record))
  $options.children:=New object("Left"; New object("label"; "Shipping"); "Right"; New object("label"; "Billing"))
  Form.start:=AXB_Form("start"; $options)
  SET TIMER(6)
 : (Form event code=On Timer)
  Form.ticks:=Form.ticks+1
  AXBC_State
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
