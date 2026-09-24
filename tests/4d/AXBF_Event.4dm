var $name : Text
$name:=OBJECT Get name(Object current)
Form.events.push(New object("object"; $name; "event"; Form event code))
If ($name="Name")
 Case of
  : ((Form event code=On Before Keystroke) & (Keystroke="#"))
   FILTER KEYSTROKE("")
  : ((Form event code=On After Keystroke) & (Get edited text="!"))
   GOTO OBJECT(*; "Notes")
  : ((Form event code=On After Keystroke) & (Get edited text="$"))
   OBJECT SET ENTERABLE(*; "Name"; False)
  : (Form event code=On Data Change)
   If (Form.name="")
    Form.name:=Form.validName
    Form.validationError:="Name is required"
   Else
    Form.validName:=Form.name
    Form.validationError:=""
   End if
 End case
End if
If ((Form event code=On Clicked) & ($name="Save"))
 Form.saved:=Form.saved+1
 OBJECT SET ENTERABLE(*; "Name"; True)
End if
AXBF_State
