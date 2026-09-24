# Generated forms

Generated JSON forms use the same `AXB_Form` options as named forms. With matching packages, ordinary controls need a label and any missing control labels. Existing explicit providers can still supply `describe` and `apply`. Add the bridge where the application opens the form, after generating its JSON and before calling `DIALOG`. Keep the generator's existing object methods and standard actions.

`AXB_Dynamic` prepares one form instance. It copies the JSON template, adds load/unload events, and wraps its form method. The wrapper runs the application's original On Load before starting the bridge. On Unload, it stops the bridge before calling the original method. Programmatic subform replacement needs the explicit close sequence below because it does not deliver that event in the tested runtime. Other subscribed events, including the existing timer, still reach that method. If the template did not subscribe to load or unload, the wrapper does not deliver those newly added events to the application method.

## Add one generated dialog

Install the [host helpers](../INTEGRATION.md). Leave initialization in the application's original form method. Use the wrapper below instead of adding manual `AXB_Form("start")` and `AXB_Form("stop")` calls to that method. The [ordinary-control example](AUTOMATIC-FORM.md) explains automatic discovery and its current coverage.

At the existing opening point:

```4d
var $form; $data; $options : Object
var $window : Integer
// $form is the generated JSON form. $data is its private application data.
$options:=New object("label"; "Generated greeting")
// On failure, form is the original JSON, so a bridge error cannot skip a business dialog.
$form:=AXB_Dynamic($form; $data; $options; "start").form
$window:=Open form window($form; Plain form window)
DIALOG($form; $data)
CLOSE WINDOW($window)
```

Use a fresh data object for each open window, including two windows made from the same template. Pass that exact object to both `AXB_Dynamic` and `DIALOG`. The source JSON template stays reusable. Reserve `axbDynamic`, the other `axb*` data properties and the object name `__AXB_DynamicContext` for the bridge. `AXB_DynamicClose` releases the registration and ownership marker, is safe to call twice, and must run in the child context. It does not call application cleanup or invent an On Unload event. Use fresh data after a failed open or aborted preparation. Preparation returns an error before opening if the data is already in use, the method/events are invalid, or the form is already wrapped. The handler context belongs to a hidden, typed dynamic variable in the form itself, so replacing application data cannot discard its original event method. Leave this reserved object in the form. A template with an original method must declare its `events` collection explicitly; preparation rejects an omitted event list instead of guessing which events the method expects. String event names and numeric 4D event constants are accepted.

Keep the application's existing modal window type. For a nonblocking `DIALOG(...; *)`, omit the immediate `CLOSE WINDOW` shown above and retain the application's existing process lifetime and close handler. The owning process must remain alive and return to its normal event loop. Do not keep it busy with a polling or delay loop while its nonblocking window is open. The wrapper's lifetime follows form events, so a nonblocking call can return while the bridge remains attached. 4D closes the nonblocking window after its accept/cancel action. Keep any existing application close logic. See the [DIALOG lifecycle](https://developer.4d.com/docs/commands/dialog). A modal child window needs its own private data object and root `start`. An automatic page subform can instead use the parent-owned path below.

`AXB_Dynamic` returns `ok`, `error` and `form`. On failure `form` is the caller's original JSON and the failure is reported once through `onError` with `phase: "prepare"`, in the calling context before opening the form. Use an application logger that does not require `Form`. Read `ok` or `error` when the application needs the reason itself; do not report the same result again.

`Form.axbError` and `Form.axbDynamic.startResult` record a failed start, including missing packages. If provided, `onError` also receives this failure with `phase: "start"`; connect it to the application's existing logger. The form and human handlers continue working when packages are absent. Unexpected describe/apply failures use the same `onError` callback after detaching, as described in the integration guide.

## Generated subforms

Choose the path that matches the parent.

**Automatic parent:** prefer parent-owned discovery. Supply the child's labels, controls and grids under `options.children.<container>`. The child needs no `describe`/`apply` provider or bridge registration. Before replacing its generated JSON or data binding, call `AXB_Form("invalidate"; New object("subform"; containerName))` in its current parent context, then run the application's existing cleanup and replacement. This also retires descendant accessibility identities. `options.children` is keyed by container object name and persists across replacement. Invalidation alone does not change metadata. Generate options that cover the child variants before opening the root. For an already open wrapped root, changing the required metadata has no supported in-place restart API yet. Extend that lifecycle in the bridge, or use the application's existing close/reopen flow with newly prepared JSON and private root data. A manual `AXB_Form("start")` bypasses the wrapper's captured session and breaks its cleanup. A plain unwrapped root can stop/start with new options only in its own root form context, never in a child replacement method. A builder generating container names must generate matching child options alongside its JSON. Automatic children may share business data; the root wrapper still needs its own private data object.

**Registered child:** when a reusable child carries its own options or uses an explicit provider, prepare it with `"register"` and the same private data object used by its container. An automatic parent discovers that registration without a `subforms` list. An explicit-provider parent must list the container in its description's `subforms`, with registration at each explicit intermediate parent. Use label/controls/grids alone for an automatic child; add describe/apply only for an intentionally explicit provider.

The sequence below is for registered children. A changed registration retires the old child, so this path does not need a second invalidation call. The root window alone uses `"start"`.

When replacing a child, call its shared cleanup method inside the old subform **before** changing the container's data binding. In the 4D 20.8 fixture, `OBJECT SET SUBFORM` replaces generated content without delivering the old form's On Unload event. Do not rely on that event to clean up a programmatic replacement.

For example, put the application's existing cleanup in a child method:

```4d
// Details_Close, called in the child context.
AXB_DynamicClose
// Run this child's existing cleanup here, using its current Form data.
```

If the replaced child owns wrapped descendants, its existing shared cleanup must close those instances deepest-first in their own form contexts before closing itself. `AXB_DynamicClose` closes one instance; it does not invent descendant Unload events. Parent invalidation retires AX identities but does not perform application resource cleanup.

Call `Details_Close` from the child's original On Unload branch. If it has no form method, add one and subscribe it to `"onUnload"`. Call the close method explicitly from the parent's replacement handler:

```4d
var $form; $options; $newData : Object
// $options contains child metadata; describe/apply are only for an explicit provider.
// $newData is fresh application data; $form is the replacement's JSON.
// A failed preparation shows the replacement without accessibility.
$form:=AXB_Dynamic($form; $newData; $options; "register").form
EXECUTE METHOD IN SUBFORM("Details"; "Details_Close")
Form.details:=$newData
OBJECT SET SUBFORM(*; "Details"; $form)
```

The container's data source is `Form.details`. Enable On Load and On Unload in the parent too, as required by [4D subform events](https://developer.4d.com/docs/Events/onUnload). Never call the original form method with a fabricated event. Do not copy old `axb*` state. The replacement receives a new identity, and retained accessibility elements cannot act on it. See [subform routing and clipping](../FORM-SUPPORT.md#subforms-and-repeated-instances).

Changing the generated JSON before opening a form does not change an already open form. Describe reads live geometry, visibility, pages and allowed values. When the application changes the represented record, change fields on its existing private data object and return the record ID from describe, for example `$description.scope:=String(Form.recordID)`. Call the application's existing dependent-control refresh logic too. Replacing the entire bound data object is a new lifetime: the wrapper detaches the old bridge and records `dynamicDataReplaced`, while continuing the original form method. Use the close-then-replace sequence above with a fresh instance to reconnect it.

The wrapper handles the generated form's lifecycle. Automatic discovery respects actual visibility, enabled and editable state; its actions use the existing controls. Custom providers must enforce their own application permissions. Native object methods and standard actions stay in place; never forward an accessibility request by inventing a native form event.

## Accept and Cancel buttons

With automatic controls, keep each button's existing object method and standard action. No parallel accessibility handler is needed. The following explicit-handler example applies only to the older custom describe/apply path.

Keep the application's standard action on the human button. Its object method and the accessibility apply method call the same application cleanup or validation. For example, a Cancel button's object method calls `Greeting_CancelCleanup`; 4D then performs its existing cancel action. The matching apply branch is:

```4d
: (($action.node="cancel") & ($action.operation="press"))
 Greeting_CancelCleanup
 $result:=New object("status"; "completed"; "message"; "Closing")
 CANCEL
```

For Accept, run the existing validation first and call `ACCEPT` only when it succeeds. A rejected validation leaves the form open and returns a rejected result. Never invoke the object method with an invented click event. Closing destroys the bridge session, so the client may lose the final receipt; verify that the window closed and inspect the application's normal outcome. Do not retry the closing action because a receipt disappeared.
