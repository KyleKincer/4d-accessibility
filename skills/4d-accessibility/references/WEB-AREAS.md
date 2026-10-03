# Web areas

Keep the existing web area, rendering engine, HTML and application callbacks. Install the root form's [lifecycle area](AREA-INTEGRATION.md) as usual. The browser supplies its native HTML accessibility tree; the bridge supplies the ordinary 4D controls beside it. No web-specific configuration callback, DOM injection or replacement form is needed for the tested macOS system engine.

This path is tested with a matching 0.22.0 kit. Leave the native web object out of the bridge's form-control configuration; keep browser control semantics in the HTML. Additional virtual web providers are outside this acceptance.

Inspect the actual window with Accessibility Inspector or an external AX client. It must contain an `AXWebArea` with the HTML controls' names, roles and values, alongside the `axb/<screen>/...` 4D elements. HTML controls retain browser-owned identities; the bridge's stable identifiers apply to its own elements. An AX client can locate browser content by role and accessible name. This fixture does not validate HTML IDs as native AX identifiers or CSS selector access.

## Validate the current engine and content

The [acceptance fixture](../../../tests/WEB-AREAS.md) uses ordinary labeled HTML inputs, a checkbox, reset and submit buttons, a disclosure and a link. Its local endpoint records the browser's submitted values. It checks original 4D handlers and editing after web navigation. The [evidence](../../../validation/native-web-areas.json) distinguishes execution modes, native baselines, VoiceOver, pixels and unresolved cases.

An automation client's AX value setter on an unfocused HTML editor can report success while the browser's submitted data is unchanged. Focus the editor first, confirm the application's focused element and read back the value. Verify the actual submission or application result after any edit, press or navigation.

VoiceOver reaches the native web content as a sibling of the bridge's ordinary 4D group. It reads the whole 4D group, including controls visually below the web area, before entering the web content. Leave the 4D group and enter the neighboring web content with the normal group interaction commands. This is a known reading-order gap; the fixture does not establish visual interleaving of HTML and 4D controls.

Pressing the native details container's `AXGroup` returned success without expanding its content in a baseline probe. Normal pointer, keyboard and VoiceOver disclosure operations pass. Automation must check the expanded content rather than treat that group's `AXPress` response as completion.

Generic discovery currently reports web areas as `providerPending`; it does not assess their browser-owned descendants. Inspect and exercise those descendants separately. Only the macOS system-engine fixture is accepted. Embedded Chromium remains pending. Switching rendering engines changes application behavior and requires its own visual and functional acceptance; this integration does not switch engines.

For an embedded-engine host, run the bridge-free probe first. On the tested 4D 20.8 installation it still lacks an `AXWebArea` after enabling VoiceOver following page load; prelaunch VoiceOver is untested. If the native tree is absent, deliver the ordinary 4D integration and report the web content as inaccessible. Keep embedded-engine support open until a supported activation route passes the native-tree and action gate. See [engine availability](STATUS.md#native-web-areas) for the version boundary.

## Completion for a host form

Verify the rendered HTML's accessible labels, reading order, focus, enabled states, validation, submission and navigation. Exercise the application's actual scripts and any browser dialogs, then return to ordinary 4D editing and commands. Close and reopen the form and compare the complete rendered window with the native baseline. Semantic HTML in one fixture does not establish accessibility for an arbitrary web application, an opaque canvas, Write Pro, View Pro or another plugin area.

When 4D controls sit visually after or beside the web area, report the group-then-web VoiceOver order as an open gap and keep that form's navigation incomplete. Passing navigation within HTML does not complete navigation across the whole form.
