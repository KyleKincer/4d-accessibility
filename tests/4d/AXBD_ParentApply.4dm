#DECLARE($action : Object) -> $result : Object
var $builder : cs.DynamicFormBuilder
var $options : Object
$result:=New object("status"; "rejected"; "message"; "Unsupported")
If ($action.operation="press")
 Case of
  : ($action.node="replace")
   Form.oldLeft:=Form.left
   $options:=New object("label"; "Generated child"; "describe"; Formula(AXBD_Describe); "apply"; Formula(AXBD_Apply($1)))
   $builder:=cs.DynamicFormBuilder.new("Greeting.json").accessibility($options)
   $builder.replaceSubformWithTemplate("Left"; AXBD_ChildData("Replacement"; Form.config); "AXBD_ChildClose")
   Form.oldLeftUnloaded:=(Form.oldLeft.closed=True) & (Form.oldLeft.stoppedBeforeUnload=True) & (Form.oldLeft.axbDynamic.closed=True)
   $result:=New object("status"; "completed"; "message"; "Replaced")
  : ($action.node="rebind")
   // Deliberately violate the documented lifetime to prove fail-closed cleanup
   // and preservation of the original method in the new application context.
   Form.oldRight:=Form.right
   Form.right:=AXBD_ChildData("Rebound"; Form.config)
   Form.right.name:="Rebound"
   Form.right.message:="Rebound"
   $result:=New object("status"; "completed"; "message"; "Rebound")
  : ($action.node="misbind")
   EXECUTE METHOD IN SUBFORM("Right"; "AXBD_ChildClose")
   Form.right:=AXBD_ChildData("Wrong data"; Form.config)
   $options:=New object("label"; "Generated child"; "describe"; Formula(AXBD_Describe); "apply"; Formula(AXBD_Apply($1)))
   $builder:=cs.DynamicFormBuilder.new("Greeting.json").accessibility($options)
   // Deliberately prepare different data than the container is bound to.
   $builder.setSubformWithTemplate("Right"; New object)
   $result:=New object("status"; "completed"; "message"; "Misbound")
  : ($action.node="reuse")
   // No old bridge context exists on this wrong-data fallback. Preparing the
   // same data first must survive the old child's explicit close callback.
   $options:=New object("label"; "Generated child"; "describe"; Formula(AXBD_Describe); "apply"; Formula(AXBD_Apply($1)))
   $builder:=cs.DynamicFormBuilder.new("Greeting.json").accessibility($options)
   $builder.replaceSubformWithTemplate("Right"; Form.right; "AXBD_ChildClose")
   $result:=New object("status"; "completed"; "message"; "Reused")
 End case
End if
AXBD_State(Form)
