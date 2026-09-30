# Manual lifecycle

Use this interface for a deliberately application-owned registration, or the published 0.19.7 kit. For new integrations with 0.20 matching builds, prefer [the lifecycle area](AREA-INTEGRATION.md). Use one lifecycle owner per window.

1. For a manually owned ordinary form, install the three bridge parts, add start/stop calls, supply missing labels, then check its coverage diagnostics.
2. For an invoice-like form, keep those calls and add a `grids` entry. Identify stable line keys, record `scope`, and loader `ready` state. Add descriptions for visual-only columns and map the existing selection controller only when selection must refresh other UI. The [grid configuration](GRIDS.md) works with either lifecycle owner.

For a form with ordinary inputs, buttons, checkboxes, radio buttons, typed dropdowns, hierarchical popup menus and editable combos:

```4d
var $bridge : Object
// At the end of successful On Load initialization:
$bridge:=AXB_Form("start"; New object("label"; "Customer details"; \
 "onError"; Formula(ReportAccessibilityFailure($1))))
If (Not($bridge.ok=True) & ($bridge.error#"dependencyUnavailable"))
 ReportAccessibilityFailure($bridge)
End if

// On Unload and your existing fatal form-error cleanup path:
$bridge:=AXB_Form("stop"; New object)
```

`ReportAccessibilityFailure` stands for your existing application diagnostic method accepting a failure object. Substitute its actual name and reuse its compiler declaration; this is not a shipped helper or a requirement to add a bridge-specific logger. The callback handles later polling failures; check the returned object for startup failures. This pattern works with plain, entity, class-instance and shared roots.

Keep existing form and object methods. Enable the form's On Load and On Unload events if necessary. The bridge's scheduler leaves the existing form timer intact. Buttons run their ordinary action; text goes through the real editor, keystroke handlers and validation when editing ends. Protected inputs remain write-only. [The complete example](examples/AUTOMATIC-FORM.md) shows labels, coverage and verification.

The scheduler leaves 100 ms to one second idle after a normal refresh, based on its cost. Pending editor operations use a faster interval. No application polling hook is needed. Treat tree updates as asynchronous: after an action, wait for its receipt and verify the application's result instead of relying on a fixed delay.

An ordinary dialog can pass its existing data to `DIALOG` or use the implicit `Form` object. Use application-specific names such as `InvoiceAX_Start` for your configuration methods. Reserve the `AXB_` method prefix, `AXB_PollGuard` and `AXB_FormRoots` for installed bridge helpers. Session ownership is per window, so named roots may share business data. Automatic children may share data too.
