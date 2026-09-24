// Shared application cleanup: called for real On Unload and before replacement.
AXB_DynamicClose
Form.stoppedBeforeUnload:=Form.axbView=Null
Form.cleanupSawName:=Form.name
Form.closed:=True
SET TIMER(0)
