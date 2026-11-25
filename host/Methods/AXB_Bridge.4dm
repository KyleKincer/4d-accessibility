// Shared component facade for zero-touch hosts that do not install host/OptionalMethods.
#DECLARE($operation : Text; $arg1 : Variant; $arg2 : Variant) -> $result : Variant
Case of
 : ($operation="form")
  $result:=AXB_Form(String($arg1); $arg2)
 : ($operation="invalidate")
  AXB_Invalidate(String($arg1))
  $result:=True
 : ($operation="pictureEquals")
  $result:=AXB_PictureEquals($arg1; $arg2)
 : ($operation="watcherStatus")
  $result:=AXB_Host("watcher"; New object("op"; "status"; "window"; 0))
 Else
  $result:=New object("ok"; False; "error"; "unknownBridgeOperation")
End case
