# Example: a name field and a button

This example documents an explicit custom provider. For ordinary controls, start with [automatic discovery](AUTOMATIC-FORM.md); it avoids these per-form description/action methods and uses existing editors and handlers.

`ReportAccessibilityFailure` below stands for the existing application diagnostic reporter accepting a failure object. Substitute its name and reuse its declaration. Use `onError` in root start options for later failures, as shown in [the ordinary-form recipe](AUTOMATIC-FORM.md). The example's application state uses plain local form data; with entity, class-instance or shared roots, keep that state in the application's existing UI controller.

This example displays a greeting. It writes no records. A human and an accessibility client use the same name validation and button handler. Once this works, replace the greeting operation with your application's existing action.

Complete [the one-time installation](../INTEGRATION.md#1-install-once) first. The names beginning with `Greeting` below are application methods to create, not bridge exports.

You will create one form, its form method, two object methods, a describe method, a shared action method, and two compiler declarations. The `AX_Describe` suffix marks bridge-only code; `Greeting_Apply` is deliberately shared with human events.

## Make the form

Create a project form named `Greeting` with these objects, and enable its `On Load` and `On Unload` events:

| Object name | Type | Data source | Object event |
| --- | --- | --- | --- |
| `Name` | Input, enterable | `Form.name` | `On Data Change` |
| `Greet` | Button, title `Greet` | None | `On Clicked` |
| `Status` | Input, not enterable | `Form.message` | None |

Give the objects ordinary, nonzero bounds. Open the form with its data object:

```4d
var $window : Integer
$window:=Open form window("Greeting"; Plain form window)
DIALOG("Greeting"; New object)
CLOSE WINDOW($window)
```

## Connect its lifetime

Use this form method. Existing initialization belongs before bridge registration; existing cleanup belongs alongside the stop call. A failed registration leaves the greeting form usable.

```4d
var $bridge : Object
Case of
 : (Form event code=On Load)
  Form.name:="World"
  Form.acceptedName:=Form.name
  Form.message:="Ready"
  $bridge:=AXB_Form("start"; New object(\
   "label"; "Greeting"; \
   "describe"; Formula(GreetingAX_Describe); \
   "apply"; Formula(Greeting_Apply($1))))
  If (Not($bridge.ok=True) & ($bridge.error#"dependencyUnavailable"))
   ReportAccessibilityFailure($bridge)
  End if
 : (Form event code=On Unload)
  $bridge:=AXB_Form("stop"; New object)
End case
```

## Describe the controls

Create `GreetingAX_Describe`. The object name finds the 4D control; the short `id` is the stable name used by your action handler. `AXB_Controls` reads geometry and visibility from the live form and also checks the actual enabled state. You provide the value, label, and application permission.

```4d
#DECLARE -> $description : Object
$description:=AXB_Controls(New collection(\
 New object("objectName"; "Name"; "id"; "name"; "role"; "textfield"; "label"; "Name"; "value"; Form.name; "enabled"; True); \
 New object("objectName"; "Greet"; "id"; "greet"; "role"; "button"; "label"; "Greet"; "value"; ""; "enabled"; True); \
 New object("objectName"; "Status"; "id"; "status"; "role"; "text"; "label"; "Result"; "value"; Form.message; "enabled"; True)))
```

The `textfield` role allows `setValue`; the `button` role allows `press`. See the [field types and limits](../INTEGRATION.md#the-description-and-action-contract) when replacing these example values.

This is the complete description. The reusable helper creates the session, assigns instance identities, advances revisions when state changes, schedules polling, and acknowledges completed actions.

## Share the action logic

Create `Greeting_Apply`. Requests use your local control IDs, even when this form is embedded as a subform. Application handlers must still check their own permissions and validation.

```4d
#DECLARE($action : Object) -> $result : Object
$result:=New object("status"; "rejected"; "message"; "Action unavailable")
Case of
 : (($action.node="name") & ($action.operation="setValue"))
  If (OBJECT Get enabled(*; "Name") & OBJECT Get visible(*; "Name"))
   If (Value type($action.value)=Is text)
    If ((Length($action.value)>0) & (Length($action.value)<=40))
     Form.name:=$action.value
     Form.acceptedName:=Form.name
     $result:=New object("status"; "completed"; "message"; "Name accepted")
    Else
     Form.name:=Form.acceptedName
     $result.message:="Use 1 to 40 characters"
    End if
   End if
  End if
 : (($action.node="greet") & ($action.operation="press"))
  If (OBJECT Get enabled(*; "Greet") & OBJECT Get visible(*; "Greet"))
   $result:=New object("status"; "completed"; "message"; "Hello, "+Form.acceptedName)
  End if
End case
Form.message:=$result.message
```

The `Name` object's `On Data Change` method calls that same handler:

```4d
var $result : Object
$result:=Greeting_Apply(New object("node"; "name"; "operation"; "setValue"; "value"; Form.name))
```

The `Greet` object's `On Clicked` method also calls it:

```4d
var $result : Object
$result:=Greeting_Apply(New object("node"; "greet"; "operation"; "press"))
```

Add these declarations to an application compiler method. Use the application's usual tracing conventions for its methods.

```4d
C_OBJECT(GreetingAX_Describe; $0)
C_OBJECT(Greeting_Apply; $0; $1)
```

In Xcode, choose **Open Developer Tool > Accessibility Inspector** and inspect the controls beneath the 4D window. Completion: enter a Unicode name through AX, press Greet, and read the actual greeting. Submit an empty name and confirm rejection preserves the accepted value. Disable the button with `OBJECT SET ENABLED(*; "Greet"; False)` and confirm it cannot greet, then check hidden state too. Close/reopen and confirm a retained old control cannot change the new form. Repeat with the bridge packages absent to verify the human event handlers still work.

For an existing save form, keep its validation and save transaction in the shared handler. Report completion only after that transaction's normal success result. If the action closes the form, stop the bridge during unload; closing a form is not a reason to replay an unacknowledged save.
