# Web areas

Keep the existing web area, rendering engine, HTML and application callbacks. Install the root form's [lifecycle area](AREA-INTEGRATION.md) as usual. The browser supplies its native HTML accessibility tree; the bridge supplies the ordinary 4D controls beside it. No web-specific configuration callback, DOM injection or replacement form is needed for the tested macOS system engine.

This path is tested with a matching 0.22.1 kit. For an older installation, upgrade to that matching kit or pass the same gate with the installed kit before claiming coverage. Leave the native web object out of the bridge's form-control configuration; keep browser control semantics in the HTML. Additional virtual web providers are outside this acceptance.

Inspect the actual window with Accessibility Inspector or an external AX client. It must contain an `AXWebArea` with the HTML controls' names, roles and values, alongside the `axb/<screen>/...` 4D elements. HTML controls retain browser-owned identities; the bridge's stable identifiers apply to its own elements. An AX client can locate browser content by role and accessible name. This fixture does not validate HTML IDs as native AX identifiers or CSS selector access.

## Validate the current engine and content

The [acceptance fixture](../../../tests/WEB-AREAS.md) uses ordinary labeled HTML inputs, a checkbox, reset and submit buttons, a disclosure and a link. Its local endpoint records the browser's submitted values. It checks original 4D handlers and editing after web navigation. The [evidence](../../../validation/native-web-areas.json) distinguishes execution modes, native baselines, VoiceOver, pixels and unresolved cases.

An automation client's AX value setter on an unfocused HTML editor can report success while the browser's submitted data is unchanged. Focus the editor first, confirm the application's focused element and read back the value. Verify the actual submission or application result after any edit, press or navigation.

In the accepted 0.22.0 fixture, VoiceOver reaches the native web content as a sibling of the bridge's ordinary 4D group. It reads the whole 4D group, including controls visually below the web area, before entering the web content. Leave the 4D group and enter the neighboring web content with the normal group interaction commands. The 0.22.1 composition below addresses that gap for eligible native containers. Measure each host form's actual order separately, including nested or multiple web areas.

## Native composition in 0.22.1

Version 0.22.1 puts ordinary bridge controls and browser-owned content under their existing common native container. It requires a visible native `WKWebView`, a common ancestor covering the whole content view, and an ignored `NSView` whose managed accessibility methods retain their inherited implementations. A host drawing subclass or WebKit's observation subclass can remain in place. Custom accessibility providers, managed-property setters and distinct custom navigation orders keep the separate-root path. No physical host view is moved and no browser provider is replaced.

In a composed form, the `axb/<screen>` group remains discoverable for its label and `AXHelp` receipt, but has no children. Find controls independently within the selected window. The controls and empty status group report the native container as their parent. That container's navigation array contains every child once, ordered with the status group last. Parent/child reciprocity and native frame availability are checked before publishing the order. Browser submission and navigation must retain this composition.

Apple requires the [navigation array](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilitychildreninnavigationorder?changes=__6&language=objc) to contain the same elements as `accessibilityChildren`. The empty status group stays in that array, after the visible controls.

Only the container's element flag, role and navigation order are managed. Its Help, label and identifier remain untouched. Detach restores the flag to false, restores an owned group role to the explicit original `AXUnknown` value, and returns an owned navigation order to computed order. A bridge-owned baseline view checks the current default role before composition is allowed. An explicit `AXUnknown` override remains after detach; its public getter matches the tested native default. Later distinct host assignments win. Same-value host assignments cannot be distinguished from bridge-owned values, and an explicit order equal to computed order at attach is treated as computed on restore.

A custom children provider can omit the drawing anchor and make bridge controls unreachable by enumeration; preserving that provider does not complete accessibility. Reading order under a preserved custom navigation provider is unproved. A transient parent/child validation failure disables composition for the rest of that registration. Nested, scrolled and multiple-web reading order needs its own VoiceOver gate. The exact public main-CI kit passes the [149-check live matrix](../../../validation/native-web-composition-0.22.1.json), including individual VoiceOver stops and zero changed pixels. This accepts the scoped fixture; each actual host form still needs its own gate.

Pressing the native details container's `AXGroup` returned success without expanding its content in a baseline probe. Normal pointer, keyboard and VoiceOver disclosure operations pass. Automation must check the expanded content rather than treat that group's `AXPress` response as completion.

Generic discovery currently reports web areas as `providerPending`; it does not assess their browser-owned descendants. Inspect and exercise those descendants separately. Only the macOS system-engine fixture is accepted. Embedded Chromium remains pending. Switching rendering engines changes application behavior and requires its own visual and functional acceptance; this integration does not switch engines.

For an embedded-engine host, first run the [bridge-free fixture probe](../../../tests/WEB-AREAS.md#engines-and-evidence) on that runtime, then inspect the host form's own native tree. On the tested 4D 20.8 installation the fixture still lacks an `AXWebArea` after enabling VoiceOver following page load; prelaunch VoiceOver is untested. If the native tree is absent, deliver the ordinary 4D integration and report the web content as inaccessible. Keep embedded-engine support open until a supported activation route passes the native-tree and action gate. See [engine availability](STATUS.md#native-web-areas) for the version boundary.

## Completion for a host form

Verify the rendered HTML's accessible labels, reading order, focus, enabled states, validation, submission and navigation. Exercise the application's actual scripts and any browser dialogs, then return to ordinary 4D editing and commands. Close and reopen the form and compare the complete rendered window with the native baseline. Semantic HTML in one fixture does not establish accessibility for an arbitrary web application, an opaque canvas, Write Pro, View Pro or another plugin area.

Record the order VoiceOver actually uses on the host form and compare it with its visual order. Report any mismatch as an open gap and keep the form's overall accessibility incomplete, including its navigation. Passing navigation within HTML does not complete navigation across the whole form.
