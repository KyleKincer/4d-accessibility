#DECLARE($failure : Object)
var $metricsRestored : Boolean
$metricsRestored:=True
If (Form.metricsEnabled=True)
 $metricsRestored:=(oMethodMetrics.call_chain.length=1) & (oMethodMetrics.call_chain[0].method_name="AXBX_MetricsRoot") & (oMethodMetrics.current_method.method_name="AXB_FormFailed")
End if
Form.recovering:=True
Form.failures:=1
File("/RESOURCES/runtime-status.json").setText(JSON Stringify(New object("phase"; "caught"; "failure"; $failure; "handlerRestored"; Method called on error(ek local)="AXBX_Error"; "metricsRestored"; $metricsRestored; "rootReached"; Form.record>0; "detached"; Form.axbForm=Null; "nested"; Form.panel.inner.name)))
SET TIMER(120)
