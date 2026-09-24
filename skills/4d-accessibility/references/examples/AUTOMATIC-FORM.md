# Ordinary controls without per-control callbacks

Build the host helpers, component and native plugin from the same source commit. The version number alone does not identify the working capabilities. See the [current support status](../STATUS.md) before opting a form in; full accessibility implementation is still underway.

For an ordinary form, keep its existing initialization and object methods. Start the bridge after initialization and stop it when the form unloads:

```4d
var $accessibility : Object
Case of
 : (Form event code=On Load)
  // Keep the form's existing initialization here.
  $accessibility:=AXB_Form("start"; New object("label"; "Contact details"))
  If (Not($accessibility.ok=True) & ($accessibility.error#"dependencyUnavailable"))
   Form.axbError:=$accessibility.error
  End if
 : (Form event code=On Unload)
  $accessibility:=AXB_Form("stop"; New object)
End case
```

Enable the form's `On Load` and `On Unload` events. Add these calls to the existing event branches; do not replace the form method. Check the start result and send errors through the application's existing diagnostic handling. `dependencyUnavailable` is expected when the optional packages are absent. An incompatible package returns an error before starting. The current source supports an object passed to `DIALOG` and the implicit `Form` object when that argument is omitted.

This provider needs no `describe` or `apply` callback. It enumerates visible controls, reads their current geometry and state, and routes accessibility actions through the real controls. Buttons retain their object method and standard action. Text edits use the editor, keystroke handlers, undo, and normal validation when editing ends. A request being accepted does not mean the application's validation accepted the resulting value.

## Names that discovery cannot infer

Buttons use their displayed titles. Inputs can use a nearby, vertically aligned static label to their left. An object name is a diagnostic fallback, so inspect the resulting names before shipping. Supply an explicit label for an icon button or an input whose visible label is arranged differently:

```4d
var $controls; $options; $accessibility : Object
$controls:=New object
$controls.SaveIcon:=New object("label"; "Save contact")
$controls.AccountNumber:=New object("label"; "Account number")
$options:=New object("label"; "Contact details"; "controls"; $controls)
$accessibility:=AXB_Form("start"; $options)
```

Keys in `controls` are the form's existing object names. Labels should describe the user-visible purpose, in the application's language. They are not method names or expressions to execute.

Read `AXB_Form("diagnostics"; New object)` from the running root form to find unsupported objects and missing labels, including the exact path to a nested child. It needs no added event hook. See [coverage checks](../INTEGRATION.md#check-the-forms-coverage) for the report fields and limits.

Masked inputs using 4D's `%password` font are detected before their value is read. For an application-specific protected input, add `"protected"; True` to its metadata. Protected inputs support write-only entry; their text and selection are not published.

## Repeated and nested page subforms

The current source discovers ordinary controls inside visible page subforms recursively. Keep the same start/stop calls on the root. The child forms need no bridge calls or extra events. Their existing data bindings and object methods continue to run in the child context. Offscreen controls remain discoverable; see [scrolling and reading order](../INTEGRATION.md#scrolling-and-reading-order) for reveal behavior and root-window requirements.

For example, an order form contains `ShippingAddress` and `BillingAddress`, both instances of the same address form. Name the two instances in the root's options:

```4d
var $options; $accessibility : Object
$options:=New object("label"; "Order details")
$options.children:=New object(\
 "ShippingAddress"; New object("label"; "Shipping address"); \
 "BillingAddress"; New object("label"; "Billing address"))
$options.scope:=Formula(String(Form.orderID))
$accessibility:=AXB_Form("start"; $options)
```

The resulting fields are named `Shipping address: Name` and `Billing address: Name`. Each has its own accessibility identity and frame, even when both children intentionally bind the same business object. Child labels default to container object names; supply readable labels where those names would be confusing. A child's options can contain another `children` object for nested instances and `controls` for missing control labels.

The `scope` formula reads the current record identity. When that value changes, retained controls from the previous record stop accepting actions. It should read existing form state, without performing a query or changing the UI.

At a shared child-replacement point, invalidate that container before replacing it:

```4d
var $accessibility : Object
$accessibility:=AXB_Form("invalidate"; New object("subform"; "ShippingAddress"))
// Keep the application's existing cleanup and rebinding sequence here.
OBJECT SET SUBFORM(*; "ShippingAddress"; "AlternateAddress")
```

This single boundary call is necessary even when the replacement uses the same form name and data object. Polling cannot observe a replacement that starts and finishes between polls. Call it in the owning parent; the same code works inside a nested parent. It changes bridge identity only and does not run application cleanup. Ignore its result when no bridge is running; `unregisteredWindow` must not block the ordinary replacement. The replacement is discovered automatically on the next poll. Generated-form builders can put this call in their shared replacement method.

Automatic discovery also supports scalar-bound children with an implicit `Form` object and process-bound controls in children whose `Form` is Null. The bridge keeps automatic child state outside their business data. Existing explicit child registrations still use the separate [custom-provider contract](../FORM-SUPPORT.md#explicit-child-providers).

## Current coverage and verification

The mixed-control fixture exercises static labels, ordinary and standard-action buttons, checkboxes, radio buttons, Text-array dropdowns, single-line and multiline inputs, read-only inputs, and protected inputs. Number, date and time inputs use their display formats. Separate live fixtures cover three-state checkboxes, editable combos, group boxes, numeric/busy progress, described images, rulers and numeric/date/time steppers. Separate dropdown tests cover typed arrays, object-backed choices, choice lists and hierarchical popup menus. Their bridge nodes publish the displayed selection; pressing one opens the real 4D menu and its native accessibility provider.

The external tests check existing handlers, Unicode editing, partial replacement, validation rejection, undo, focus redirection, a field becoming read-only during typing, and retained references after capability changes. See [validation](../VALIDATION.md) for the exact build and execution scope. ARM and Intel compilation does not establish licensed compiled desktop execution.

For complete flat native array, collection, entity-selection and AreaList grids, add [`options.grids`](../INTEGRATION.md#add-a-native-array-list-box-without-replacing-discovery) alongside ordinary discovery. Other grid families, additional ordinary control families, text glyph geometry and whole-workflow assistive-technology validation remain required work. Existing explicit `describe`/`apply` integrations continue to use their callbacks. Installing the new provider does not silently combine those descriptions with automatic discovery.

The integration goal is one shared form lifecycle hook plus declarative labels and special-control adapters where needed. These adapters belong in the reusable bridge. An application should not have to reproduce its validation, business actions, or ordinary control descriptions to become accessible.
