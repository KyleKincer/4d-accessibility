# Integrate with a lifecycle area

The area owns startup and shutdown. Discovery, grids, editors, validation and actions use the same adapters as the manual interface. This path passes the [area acceptance suite](../../../validation/area-owned-integration.json) and is included in 0.21.0 or later matching kits. The older 0.19.7 kit uses the [manual lifecycle](MANUAL-LIFECYCLE.md).

## Ordinary named form

Install matching plugin, compiled component and host methods as described in [setup](SETUP.md). Add the area while installing methods:

```sh
python3 install_host_methods.py --project-dir /path/to/MyApp/Project --form Customer
```

Repeat `--form` for selected forms, or use `--all-forms` for detail-screen and unspecified-destination forms. Bulk installation reports and skips list and print forms. A table form is addressed as `--form TableForms/1/RecordEditor`. Add `--area-list` for AreaList Pro. Run with `--dry-run` first to list proposed files. Repeating the command is idempotent. A conflicting object, edited generated helper or conflicting area stops preflight before any source is written.

For named inheritance, the installer adds the area once in the shared base, leaving derived definitions unchanged. It resolves project forms and table forms by number or catalog name. Cycles, unresolved external/inline bases, and a local area in a derived form stop preflight. Preflight lists every known form inheriting an affected base, including unselected list/print forms.

Review those other uses too; use central opt-out where another inherited form should remain unregistered. List-screen uses inherited from that base must return `New object("enabled"; False)` from `AXB_Configure`, identified by `Current form name` and, for table forms, `Current form table`. Do not claim their accessibility through this detail-form path.

Printing creates no registration because native area initialization ignores printing and the area is non-printable. Remove only the exact installer-owned area from a previously instrumented derived form before retrying. Never delete an application object to resolve a name conflict.

The installer adds `__AXB_Bridge`, a non-enterable 1×1 `%AXB Area`, at (0,0) on page zero. It draws nothing, has no method or form events, does not take keyboard focus and does not print. Existing object definitions, dimensions, methods and events are preserved. The installer rewrites form JSON using the project's indentation. Keep the area definition installer-owned and review the diff.

The [0.21.1 early-focus and close-during-load tests](../../../validation/compound-form-focus-0.21.1.json) verify area reservation before On Load on the tested runtime, so the existing [focus observer](INTEGRATION.md#repeated-controls-with-ambiguous-focus) can retain early events. Root registration and `AXB_Configure` still wait until the form reaches its ordinary event loop. Closing during On Load retires the reservation without starting a provider.

For an ordinary form with clear existing labels, there is no application method to write. Its form method keeps its existing initialization, timer and business code. The area queues startup after initialization and retires its own captured lifetime when destroyed.

## One optional configuration method

Create application-owned `AXB_Configure` when discovery needs labels or providers. The bridge calls it once in the actual root's form context after initialization. It passes the named root's `Current form name`, or the generated configuration key described below. Return an options object; an omitted label defaults to the window title, then that name/key, then `Application form`. Return Null or an empty object to leave an unconfigured form on automatic defaults. Keep this callback fast, in memory and free of business mutations. Use readiness formulas for asynchronous loading.

```4d
// Application method: AXB_Configure
#DECLARE($formName : Text) -> $options : Object
$options:=New object
Case of
 : ($formName="Customer")
  $options.label:="Customer details"
  $options.controls:=New object("AccountNumber"; New object("label"; "Account number"))
 : ($formName="RecordEditor")
  $options:=RecordEditorAccessibilityOptions
End case
$options.onError:=Formula(ReportAccessibilityFailure($1))
```

`RecordEditorAccessibilityOptions` is an application method returning the configuration built in the [record-editor example](examples/RECORD-EDITOR.md). Use existing object names, stable IDs, formatters, readiness flags and controllers. This callback returns configuration; it does not start a second bridge. Other forms get automatic discovery and the same reporter. `ReportAccessibilityFailure` represents the application's existing logger, not a shipped method; omit that option if no reporter is needed. With no callback at all, startup and later adapter failures remain inspectable in area diagnostics. Production applications that need active reporting can use this one central default.

Distinguish identically named table forms by their actual table context. For a table form called `Input` owned by the existing `Records` table, a configuration case can test `($formName="Input") && (Current form table=->[Records])`. Project forms have a nil table pointer. [4D table-context contract](https://developer.4d.com/docs/commands/current-form-table).

For 4D's explicit-type compiler mode, add these application declarations to the application's compiler method, outside the generated block:

```4d
C_TEXT(AXB_Configure; $1)
C_OBJECT(AXB_Configure; $0)
```

Declare any application configuration method's return type there too. `AXB_Configure` is the application-owned exception to the reserved `AXB_` helper prefix. The installer never creates or overwrites it. Return `New object("enabled"; False)` to opt a form out. All other options use the existing [configuration contract](INTEGRATION.md): `controls`, `children`, `grids`, `scope`, `describe`, `apply` and `onError`. An optional root `automationKey` supplies a [logical screen locator](IDENTIFIERS.md) in supporting kits.

## Repeated and nested children

One root area publishes the root and its supported page subforms. Children need no startup or shutdown calls. If the installer also adds areas to reusable child forms, those instances leave root ownership alone. An area's own dynamic binding distinguishes root and child instances, including identical names, origins and shared business data.

Keep labels and grid configuration under the existing container name, for example `options.children.ShippingAddress`. Keep [replacement invalidation and focus observation](INTEGRATION.md#child-forms) where the application needs them. The area replaces lifecycle hooks; it does not guess record identity, readiness or an application's replacement boundary.

## Generated JSON forms

At the shared builder, prepare the definition before opening it:

```4d
var $prepared; $form; $existingData : Object
var $window : Integer
// At the shared builder, $form already contains generated JSON.
// $existingData is the same application data the existing opener uses.
$prepared:=AXB_AreaForm($form; "RecordEditor")
// Report $prepared.error through existing diagnostics if ok is False.
$form:=$prepared.form
$window:=Open form window($form; Plain form window)
DIALOG($form; $existingData)
CLOSE WINDOW($window)
```

`AXB_AreaForm` copies the definition and adds the same area. It leaves the original definition, method, events, object methods and data untouched. The optional key starts with an ASCII letter and contains at most 64 ASCII letters, digits, underscores or hyphens. It is stored in the area's object name, not the business data. Repeated preparation accepts the same canonical area and key. On failure it returns `ok: False`, `error` and the original `form`, so the application's normal dialog can still open.

Generated roots use the existing `DIALOG` data, including implicit, entity, class-instance or shared data. In the example, `AXB_Configure` receives `RecordEditor`, which also becomes the screen key unless the returned options override `automationKey`. Without a key the callback receives `Current form name`, which is not a useful stable selector for a generated definition. Prefer an explicit key when configuration is needed. A central callback that returns Null or an empty object for an unrecognized form leaves that form on automatic defaults. Ordinary generated children are discovered from the root.

For generated definitions inheriting a named form, install the area in that named base and open the original generated definition unchanged. Do not add another area with `AXB_AreaForm`; it returns `inheritedAreaForm` before mutation because it cannot inspect an external base safely. Inline/external JSON inheritance needs an explicitly prepared base or the [manual interface](MANUAL-LIFECYCLE.md). List and print destinations return `unsupportedAreaDestination`. The advanced `AXB_Dynamic` wrapper remains for explicit per-instance provider registration and its private-data contract; it is not needed for ordinary automatic generated forms.

## Ownership and failures

The area owns the registration it created. An intentional `AXB_Form("start"; newOptions)` in that same root transfers teardown ownership to the replacement session, including recovery after an adapter failure. Keep intentional restart code when migrating. An area that found a pre-existing manual registration reports `existingRegistration` and does not take ownership; that registration still needs its manual stop. Closing a child or a delayed old callback cannot stop another lifetime or window sharing the same data. The area requires native `areaLifecycle 1`, native `buttonInput 1` for automatic controls, and component `capturedStop: 1` from matching builds.

If startup failed before creating a context, a later manual start remains application-owned and needs its manual stop. Close and reopen the form to retry automatic area startup.

From the root, inspect `AXB_Area("diagnostics"; ""; "")` for area states and startup failures, and `AXB_Form("diagnostics"; New object)` for published coverage. Area states include `initializing`, `queued`, `active`, `child`, `ignored`, `existingRegistration`, `disabled`, `stopped` and `failed`. Each record includes `configured`, `configuration`, `registered` and any `failure`. `configured` proves the optional callback returned; check it when a callback is expected. `registered` reports current session activity rather than historical startup success. A later adapter failure leaves `stopped` with a copied failure reason, including for entity/class/shared roots without `onError`. Intentional stop has no failure reason. Configure the central reporter when failures must be logged actively. Startup is asynchronous; wait for an active registration and ready coverage before asserting accessibility.

An empty area list does not prove success or optional absence. Check that the form has the canonical area, that `AXB_Host("info"; New object)` advertises matching versions and `areaLifecycle 1`, and that the form has reached its event loop. A missing/older native plugin cannot deliver area callbacks. With a current native plugin but absent component, the area reports `dependencyUnavailable` and normal form behavior continues.

`onError` reports later adapter failures through the existing form contract and valid configured startup failures with phase `start`. An exception in `AXB_Configure` is retained as `areaCallbackError` with code, method and line in area diagnostics, even if it prevented the callback from returning. The bridge aborts that failing callback and restores the local error handler before ordinary events continue. `onError` receives the existing compact failure contract; inspect area diagnostics for startup exception details. Missing optional dependencies remain explicit in diagnostics.

## Migrate and verify

Add areas and central configuration on an isolated host branch. The installer preserves business methods, including existing manual hooks. If the manual start runs during On Load before queued area startup, the area reports `existingRegistration` until those hooks are removed. A start delayed until after the area has registered instead becomes an intentional restart and retains area ownership. Diagnose the actual ordering; the state alone does not prove manual hooks were removed. After confirming configuration parity, remove the superseded one-shot start/stop calls and unused lifecycle variables. Keep intentional manual restart, explicit registration, invalidation and focus-observer calls where still required.

Require unchanged rendered forms, compiler checks, external AX actions and business results, VoiceOver for claimed workflows, stale-reference rejection, child replacement, record changes, modal windows and repeated open/close cycles. Exercise each claimed desktop mode. Also verify normal behavior with optional packages absent. See [validation](VERIFY.md) and [current scope](STATUS.md). Installing areas does not implement an unsupported control family or intercept built-in `ALERT`/`CONFIRM` commands.
