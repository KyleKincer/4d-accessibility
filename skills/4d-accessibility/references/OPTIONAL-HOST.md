# Optional host API

For application integration, start with [the developer walkthrough](INTEGRATION.md) and its `AXB_Form` lifecycle helper. This page documents the lower-level `AXB_Host` interface that the helper uses. It remains useful for specialized adapters and compatibility tests.

`AXB_Host` is a host method that compiles without either bridge dependency. It calls only two fixed component method names after detecting the native plugin and component. The component reports `hostAPI: 1`; an incompatible component is rejected before dispatch. The native snapshot protocol remains version 1.

## Host installation

Use the installer in [the integration guide](INTEGRATION.md#1-install-once). It installs the wrapper and higher-level helpers and merges declarations. Generated helpers have no application-specific instrumentation dependency.

Install the compiled `AccessibilityBridge.4dbase` component and native `AccessibilityBridge.bundle` together. Calls use this fixed interface:

```4d
$reply:=AXB_Host("start"; New object("poll"; Formula(MyFormPoll)))
If ($reply.ok)
 Form.bridgeSession:=$reply.session
End if
```

The formula is supplied by application code. It is never accepted from an external accessibility request. An unavailable bridge returns an error object; the form's ordinary behavior continues without starting a bridge scheduler.

| Operation | Request | Result |
| --- | --- | --- |
| `info` | Empty object | Native status text and component version, API, and execution-mode metadata. |
| `start` | `poll`, a real `4D.Function` | Starts the existing timer-independent scheduler and returns its session. Requires the current form and a `Form` object. |
| `node` | `objectName`, `id`, `role`, `label`, `value`, `enabled` | Returns `node` with current geometry and visibility/enabled state. Rejects unknown controls on the current/inherited pages. |
| `exchange` | `session` and an `envelope` object | Returns the native exchange result as an object. Requires the active session to belong to the current process and window. |
| `stop` | Empty object, or a captured `session` | Stops and detaches the current window's adapter. A supplied session must match, so stale cleanup cannot stop a replacement. Call during unload and fatal adapter cleanup. |
| `focus` | Empty object | Returns public native input-client geometry and selection for the active window. Does not read editor text; the ordinary provider uses it to distinguish repeated child editors. Requires native-focus capability 1. |

Every request must be a non-null object. Every result has `ok`; failures have `error`. Missing dependencies return `dependencyUnavailable` plus `native` and `component` booleans. Other local errors include `unsupportedOperation`, `invalidRequest`, `incompatibleComponent`, `incompatibleNativePlugin`, `noFormContext`, `invalidPoll`, `invalidNode`, `unknownControl`, `inactiveSession`, and `invalidEnvelope`. Native exchange errors retain their existing names.

When calling `AXB_Host` directly, the host owns snapshot revisions, allowed control descriptions, application validation, action routing, and completion receipts. `AXB_Form` handles the protocol bookkeeping for ordinary integrations. This low-level wrapper does not infer business actions or replace error handlers. `Form.axb` remains reserved for the scheduler. See [the protocol walkthrough](INTEGRATION.md#3-follow-one-action-through-the-form) for the snapshot and receipt contracts.

AreaList adapters remain host methods. Their `AXB_ALPNode` helper constructs the table metadata using ordinary 4D commands, removing their direct reference to the compiled component's control helper. Compile these methods with AreaList installed; neither bridge dependency is needed. Array pointers never cross into the compiled component.

The older component exports remain available for the existing fixtures. Optional application code must use `AXB_Host` instead of direct `AXB_Start`, `AXB_Stop`, `AXB_ControlNode`, `AXB Exchange`, or `AXB Status` references. No general method-execution operation is exposed. This follows [4D's optional component guidance](https://developer.4d.com/4D_Info_Report/docs/reference/09_deployment.html).

## Checks that do not need the AreaList license

With desktop 4D closed, build the component and test the optional host:

```sh
python3 build_component.py --server "/path/to/4D Server.app"
python3 test_optional_loading.py --server "/path/to/4D Server.app"
python3 prepare_host_fixture.py --server "/path/to/4D Server.app"
```

The dependency test compiles the actual host API for ARM and Intel with neither dependency. It also compiles the AreaList host adapters with only AreaList installed. It runs all four dependency combinations in interpreted and compiled Server utility hosts, then two incompatible-component cases whose component deliberately lacks the dispatch method. The ten cases reject unknown operations, null requests, and UI operations outside a form.

The separate `host-api-fixture` contains no AreaList plugin, license, or business data. Its project form and JSON-generated form use the same optional host API and application handlers. Run them separately through external macOS accessibility:

```sh
python3 test_host_ui.py --run --mode interpreted
python3 test_host_ui.py --run --mode interpreted --dynamic
```

The test uses the invoking agent or terminal's existing Accessibility grant through native macOS APIs. It does not rebuild the separately approved `AXB Fixture Tests.app`. It checks the exact disposable window and run identity before editing synthetic values, and closes through the native window close control. It refuses to launch over an existing 4D session.

Interpreted and compiled desktop execution have separate licensing and validation requirements. Add `--mode compiled` in place of `--mode interpreted` to test a licensed compiled host. Server utility compilation and component execution do not establish compiled desktop execution.

The fixture checks ordinary editing, validation, visibility, submission, replacement identity, stale controls, timer preservation and native closure. It does not establish nested subforms, generated tables, vendor editing or a complete application workflow. Record fresh results for the packages being integrated; see [validation scope](VALIDATION.md).
