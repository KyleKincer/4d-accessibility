// Called after each complete snapshot/action cycle in the disposable fixture.
// Never clears AreaList's sticky LastError or changes its TRACE preference.
var $error : Integer
$error:=AL_GetAreaLongProperty(0; ALP_Area_LastError)
If ($error#0)
 File("/RESOURCES/vendor-error.json").setText(JSON Stringify(New object("passed"; False; "compiled"; Is compiled mode; "vendorError"; $error)))
 AXB_Stop
 QUIT 4D
 ABORT
End if
