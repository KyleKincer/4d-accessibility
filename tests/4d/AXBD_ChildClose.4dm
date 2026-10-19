// Shared application cleanup: called for real On Unload and before replacement.
AXB_DynamicClose
Form.stoppedBeforeUnload:=AXB_FormView(Form)=Null
Form.cleanupSawName:=Form.name
Form.closed:=True
SET TIMER(0)
