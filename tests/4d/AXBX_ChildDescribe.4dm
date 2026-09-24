// Deliberate error used to verify recovery from two subform levels deep.
#DECLARE -> $description : Object
var $value : Text
If (Form.injectError=True)
 $value:=File("/RESOURCES/intentional-missing-test-file").getText()
End if
$description:=GreetingAX_Describe
