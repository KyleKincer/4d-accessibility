ON ERR CALL("AXBD_Error")
var $config; $data; $options : Object
var $closeAction : Text
var $base : cs.BaseForm
var $builder : cs.DynamicFormBuilder
$config:=JSON Parse(File("/RESOURCES/launch.json").getText())
$data:=New object("config"; $config; "closed"; False; "calls"; 0; "humanEvents"; 0; "closeCleanupCalls"; 0; "loadCount"; 0)
If ($config.prepareFailure)
 $data.axbDynamic:=New object("closed"; False)
End if
$closeAction:=ak cancel
If ($config.axClose="accept")
 $closeAction:=ak accept
End if
$data.Name:=Formula(AXBD_Name)
$data.Greet:=Formula(AXBD_Click)
$data.Close:=Formula(AXBD_CloseAction)
$options:=New object("label"; "Generated greeting"; "describe"; Formula(AXBD_Describe); "apply"; Formula(AXBD_Apply($1)); "onError"; Formula(AXBD_Failed($1)))
If ($config.subforms)
 $options.describe:=Formula(AXBD_ParentDescribe)
 $options.apply:=Formula(AXBD_ParentApply($1))
 $builder:=cs.DynamicFormBuilder.new("Parent.json").accessibility($options)
 $builder.dialogWithTemplate($data; $config.nonblocking)
Else
If ($config.builder="base")
 $base:=cs.BaseForm.new().title("AX bridge generated forms").formMethod("AXBD_Lifecycle").bottomMargin(20).rightMargin(20)
 $base._events:=New collection("onLoad"; "onUnload"; "onTimer")
 If ($config.numericEvents)
  $base._events:=New collection(On Load; On Unload; On Timer)
 End if
 $base.addObjectsToPage(1; New collection(\
  cs.FormObjectInput.new("Name").datasource(Formula(Form.name)).left(20).top(20).width(300).height(25).event("onDataChange"); \
  cs.FormObjectButton.new("Greet").title("Greet").left(20).top(60).width(100).height(26).event("onClick"); \
  cs.FormObjectInput.new("Status").datasource(Formula(Form.message)).enterable(False).left(20).top(100).width(380).height(25); \
  cs.FormObjectButton.new("Close").title("Close").standardAction($closeAction).event("onClick").left(280).top(60).width(100).height(26)))
 If ($config.modal)
  $base.type(Movable form dialog box)
 End if
 If (Not($config.withoutOptIn=True))
  $base.accessibility($options)
 End if
 $base.display($data; $config.nonblocking)
Else
 $builder:=cs.DynamicFormBuilder.new("Greeting.json")
 If (Not($config.withoutOptIn=True))
  $builder.accessibility($options)
 End if
 If ($config.modal)
  $builder.modalWithTemplate($data)
 Else
  $builder.dialogWithTemplate($data; $config.nonblocking)
 End if
End if
End if
// The startup method runs in the persistent main UI process. Returning lets
// that process service the nonblocking form; a busy wait would starve it.
If ($config.nonblocking)
 $data.returnedBeforeClose:=Not($data.closed)
 return
End if
$data.dialogOK:=OK
If ($config.reopen)
 $data.closed:=False
 If ($config.builder="base")
  $base.display($data; False)
 Else
  $builder.dialogWithTemplate($data; False)
 End if
End if
AXBD_Finish($data)
