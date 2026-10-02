# Find controls by stable identifiers

Version 0.21.0 introduces stable locators. Choose a matching kit from [availability](STATUS.md#availability). Install plugin, component and helpers together. `AXIdentifier` identifies a logical control and repeats when the same form reopens. Find it inside the selected live application's window, then perform its ordinary accessibility action. Two open copies of a screen may have the same locators.

| Element | Example identifier |
| --- | --- |
| Root form | `axb/customers.main` |
| Search field | `axb/customers.main/SearchFld` |
| Field in a repeated subform | `axb/customers.main/Billing/FirstName` |
| Same field in the other subform | `axb/customers.main/Shipping/FirstName` |
| Tab group and first choice | `axb/customers.main/Pages` and `axb/customers.main/Pages/tab/1` |
| Grid row | `axb/customers.main/Items/row/line-42` |
| Grid column and header | `axb/customers.main/Items/column/Description` and `axb/customers.main/Items/header/Description` |
| Grid cell and its text content | `axb/customers.main/Items/cell/line-42/Description` and the same path followed by `/content` |
| Checkbox inside a grid cell | `axb/customers.main/Items/cell/line-42/Approved/checkbox` |
| Popup inside a grid cell | `axb/customers.main/Items/cell/line-42/Status/popup` |
| Grid header group | `axb/customers.main/Items/headers` |
| Combo menu button | `axb/customers.main/Category/choices` |
| Legacy row-summary text | The legacy row's path followed by `/summary` |

## Defaults usually need no configuration

The root screen key uses `automationKey` from `AXB_Configure` first, then the area's configuration name, then the root form's name, then `generated`. Two table forms named `Input` both default to `axb/Input`; a logical key distinguishes them when needed. Subform containers add their object names. Controls use their object names; explicit providers without an object name use their local node ID. Native grid columns use their column object names. AreaList columns use their existing `column.N` IDs unless configured otherwise. Labels and changing window titles do not form locators.

Custom `describe` providers publish their application-owned node IDs. Keep those IDs stable; automatic control metadata overrides do not rename custom nodes.

For a logical screen whose form name is shared or may be renamed, add one property to its existing central configuration:

```4d
$options.automationKey:="customers.main"
```

This is optional. Keep the existing grid, child, scope and controller configuration in that object. No control methods need identifier code. To keep one control's locator across an object-name change, set its existing control metadata's `automationKey`. For a child field, that metadata lives under the root's `children.Container.controls.Field` configuration. A tab-group override also changes its choices' prefix. Grid column metadata accepts the same override; see [column locators](GRIDS.md#describe-custom-native-grid-columns). For AreaList column 5, set `columns["5"].automationKey` to replace its default `column.5` segment.

Generated forms use the logical configuration name passed to `AXB_AreaForm`. That configuration name must match `[A-Za-z][A-Za-z0-9_-]{0,63}`, for example `CustomerDetails`. A dotted screen key such as `customers.main` belongs in the configuration's `automationKey`, not in the `AXB_AreaForm` argument. An intentional `AXB_Form("start"; options)` restart retains the current screen key when the new options omit it. Without one, generated forms use `generated`. Supply a name at the shared builder when several generated screens need distinct automation names. The lower-level native snapshot API defaults to `form` plus the provided node IDs; those IDs must themselves be stable to make a repeatable locator.

Tab choices use a unique hierarchical-list item reference when available, such as `/tab/ref-201`. Arrays, object collections and repeated list references use a one-based choice position, such as `/tab/1`. Reordering those positional choices changes their meaning. Their labels can change without changing the path.

## Lifetime and lookup rules

- Select the application and live window first. A locator alone does not select between two copies of a form.
- Reacquire elements after close, restart, record scope changes, child replacement or grid rebinding. A repeated locator does not revive a retained old handle.
- Grid row segments expose the adapter's existing row key in `AXIdentifier`. Use an opaque, non-sensitive identity rather than personal or confidential data. Sorting preserves the key. A temporary unsaved-row UUID is stable only for that row's lifetime; persistence across reopening needs an existing persistent key.
- Read action receipts and verify the application result as described in [AX actions](AX-ACTIONS.md). A locator does not bypass readiness, permissions, validation or native handlers.

The bridge retains session UUIDs, internal node routes, grid generations and action nonces. Identical locators in two windows never cross-route actions. Invalid host metadata rejects startup with `invalidAutomationKey`, `invalidControlAutomationKey` or `invalidGrids`. An older plugin fails with `stableIdentifiersUnavailable`. Duplicate node paths or column keys reject the whole window snapshot during publication. Check `AXB_Area("diagnostics")` and its area's `.failure`, or the configured `onError` callback, for the cause. After failure detaches registration, `AXB_Form("diagnostics")` can report only `unregisteredWindow`; preserve the original failure report.

Each segment is UTF-8 percent-encoded. `Search/É%` becomes `Search%2F%C3%89%25`; it is one object name, not three containers. A slash in the screen key is encoded the same way. Match the encoded locator exactly, including case.

Screen keys accept 1–128 UTF-16 units; control/column keys and path segments accept 1–256. There are at most 16 segments after the screen key, counting every container, the control key and synthesized tab suffixes such as `tab/1`. Generated grid suffixes do not count toward that limit.

Renaming a form, container, object or key changes its default locator, so update recorded automation. Screen, control and column overrides can preserve their corresponding segments. Container segments always use their actual object names; `children.Container.automationKey` does not rename the container. Renaming it changes every descendant's path.

## Upgrade existing automation

Earlier kits exposed per-session `axb.*`, `axb.window.*` and encoded `axb-grid.*` identifiers. Replace selectors recorded from those versions with the new paths. Install plugin, component and helpers together and restart 4D. `AXB_Host("info"; New object).nativeStatus` must include `stableIdentifiers 1`.

Assertions about session replacement should compare element handles and rejected stale actions, not expect public identifiers to change. Keep window scoping in recording and driver tools. The bridge supplies the locator contract; adopting it in an external automation tool is a separate change to that tool.
