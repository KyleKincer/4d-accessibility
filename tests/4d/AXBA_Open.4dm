ON ERR CALL("AXBA_Error")
var $config; $data : Object
var $i; $window; $registration : Integer
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
If ($config.licenseMode="registered")
 $registration:=AL_Register(File("/RESOURCES/alp.license").getText(); 1; "")
 If ($registration#0)
  File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "failed"; "registration"; $registration)))
  QUIT 4D
  return
 End if
End if
ARRAY TEXT(aLeftLineKey; 200)
ARRAY TEXT(aLeftItem; 200)
ARRAY TEXT(aLeftDescription; 200)
ARRAY TEXT(aRightLineKey; 200)
ARRAY TEXT(aRightItem; 200)
ARRAY TEXT(aRightDescription; 200)
For ($i; 1; 200)
 aLeftLineKey{$i}:="line-"+String($i; "000")
 aRightLineKey{$i}:=aLeftLineKey{$i}
 aLeftItem{$i}:="DUPLICATE-SKU"
 aRightItem{$i}:="DUPLICATE-SKU"
 aLeftDescription{$i}:="Left line "+String($i)
 aRightDescription{$i}:="Right line "+String($i)
End for
$data:=New object("config"; $config; "left"; New object("side"; "Left"; "recordID"; "left-invoice"; "loadedRecordID"; "left-invoice"; "gridReady"; True); "right"; New object("side"; "Right"; "recordID"; "right-invoice"; "loadedRecordID"; "right-invoice"; "gridReady"; True); "humanEvents"; 0; "timerFirings"; 0)
$window:=Open form window("Parent"; Plain form window)
DIALOG("Parent"; $data)
CLOSE WINDOW($window)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $config.runId; "closed"; True; "stopped"; $data.axbView=Null)))
QUIT 4D
