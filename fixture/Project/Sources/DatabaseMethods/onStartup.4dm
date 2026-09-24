// Disposable fixture, using synthetic data only.
ON ERR CALL("AXB_FixtureError")
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "starting"; "compiled"; Is compiled mode)))
// Optional local license; never include its value in source, diagnostics, or AX.
var $license : Text
var $registration : Integer
If (File("/RESOURCES/alp.license").exists)
 $license:=File("/RESOURCES/alp.license").getText()
 $registration:=AL_Register($license; 1; "")
 $license:=""
 File("/RESOURCES/alp-registration-status.txt").setText(String($registration))
End if
var $window : Integer
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe")
CLOSE WINDOW($window)
QUIT 4D
