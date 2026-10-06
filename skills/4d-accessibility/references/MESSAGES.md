# Alerts and confirmations

Inspect the dialog that actually opens. An application method named `Alert_Custom` may still call 4D's built-in `ALERT`.

## Built-in ALERT, CONFIRM and Request

Without the native plugin, these windows expose only an empty accessibility element on 4D 20.8/macOS 26.7. The [plugin-free reproduction](../../../tests/native-messages/README.md) records native ARM and Rosetta results.

With the native plugin installed, it publishes them without any host change. It needs no component, host method or `CALL FORM`. The original window stays in place and keeps its keyboard behavior. Each is an internal 4D form whose objects are named layers (`main`, `comment`, `additional`, `box`, `ok`, `cancel`). The plugin reads the text 4D draws in each one. It publishes:

- the message as static text;
- the Request answer as an editable text field, which starts focused, including when empty;
- the buttons by their drawn titles, cancel before default. Without a Request field, focus starts on the default button.

A press posts an ordinary click at the button's center, so 4D sets `OK` exactly as for the mouse. 4D discards input queued before its modal loop starts, just after the window is drawn, so a press or value write is held until the window has been published for half a second. An automation client may therefore press as soon as the elements appear. The field's selection is 4D's own caret, read from its editor, so Left/Right and mouse moves are reported. Writing the field's value replaces the whole answer, then types each character into 4D's own editor. If the caret has moved, it first goes to the end of the answer and deletes it, as a keyboard user would. Line breaks are rejected because they would end entry. Typing, from the keyboard or through AX, is announced as text edits, so VoiceOver echoes characters and words.

Recognition is strict. A window is published only if every object in its form is a known message object and both `main` and `ok` are present. Any other window is left untouched. A window that already has a bridge session is also left untouched.

[Acceptance](../../../validation/native-messages-provider.json): `test_native_messages.py` covers three CONFIRMs, one pressed the moment it appears, an ALERT and three Requests, one with no default answer. It passes interpreted and compiled, in native ARM and Rosetta, with and without VoiceOver. Every window is pixel-identical to the plugin-free window before any action. Each choice returns 4D's normal `OK` and answer.

Remaining scope:

- 4D Server and remote clients;
- VoiceOver speech for caret moves: the published caret follows 4D's, but VoiceOver does not yet read the characters a Left/Right move passes;
- long, wrapped and localized messages;
- other built-in windows.

4D's own empty title element remains. Continue to integrate application dialog forms as below; those integrations do not depend on this recognition.

## Use an existing application dialog

If the application already has suitable alert and confirmation forms, integrate those forms through the [ordinary lifecycle](examples/AUTOMATIC-FORM.md). This keeps their layout, message bindings, button titles, standard actions and keyboard shortcuts. Add a [lifecycle area](AREA-INTEGRATION.md) to the shared dialog form. Startup runs after its existing code has set titles and resized the form. One integration in a shared dialog form covers its existing callers.

Identify message fields with labels such as `Message` and `Help`. Static text with a variable reference must expose its resolved message; verify the actual AX value. A warning picture may be decorative when the same meaning is already conveyed by the message. Preserve any meaningful severity description.

Replacing a built-in prompt with an application dialog requires a call-site change. With the plugin installed, it is not needed for accessibility. First establish that the application's appearance requirements allow its existing dialog style. Keep the original message, choice labels, default choice, cancellation and control-flow branch. Capture the dialog method's return value explicitly where the caller previously read `OK`. Preserve batch/server suppression rules in any shared wrapper.

Trace each wrapper before changing it. A three-choice dialog may return the chosen label; a two-choice dialog may return an integer. An alert may accept Escape while a confirmation cancels. Keep those contracts and test them. Do not change business decisions to get past an inaccessible prompt.

## Validate the complete path

Run the existing dialog methods with synthetic messages in each supported execution mode. Read the complete message and every visible choice through AX and VoiceOver. Activate each choice and assert the caller's actual return value. Exercise long messages and any sizing behavior used by the application.

Then run the real workflow through the integrated prompt and check its business result. A dialog test alone does not prove that its caller handles nested form ownership, acceptance or cancellation correctly. Retain the original form's visual properties and compare rendered output when a form is replaced or its layout changes.

This approach supports an application that routes its prompts through accessible forms. With the native plugin installed, direct built-in calls are published as described above. Validate them in the application's own workflow and execution modes.
