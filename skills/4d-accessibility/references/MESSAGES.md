# Alerts and confirmations

Inspect the dialog that actually opens. An application method named `Alert_Custom` may still call 4D's built-in `ALERT`. The bridge can discover a named project or table form after its lifecycle starts; it cannot attach that lifecycle inside a built-in `ALERT` or `CONFIRM`.

On the tested 4D 20.8/macOS 26.7 installation, both built-in commands expose an empty accessibility element without their message or buttons. The [plugin-free reproduction](../../../tests/native-messages/README.md) records native ARM and Rosetta results. That vendor behavior remains unresolved.

## Use an existing application dialog

If the application already has suitable alert and confirmation forms, integrate those forms through the [ordinary lifecycle](examples/AUTOMATIC-FORM.md). This keeps their layout, message bindings, button titles, standard actions and keyboard shortcuts. Add On Unload if needed, and start discovery after the existing On Load code has set titles and resized the form. One integration in a shared dialog form covers its existing callers.

Identify message fields with labels such as `Message` and `Help`. Static text with a variable reference must expose its resolved message; verify the actual AX value. A warning picture may be decorative when the same meaning is already conveyed by the message. Preserve any meaningful severity description.

For a built-in prompt, using an application dialog requires a call-site change. First establish that the application's appearance requirements allow its existing dialog style. Keep the original message, choice labels, default choice, cancellation and control-flow branch. Capture the dialog method's return value explicitly where the caller previously read `OK`. Preserve batch/server suppression rules in any shared wrapper.

Trace each wrapper before changing it. A three-choice dialog may return the chosen label; a two-choice dialog may return an integer. An alert may accept Escape while a confirmation cancels. Keep those contracts and test them. Do not change business decisions to get past an inaccessible prompt.

## Validate the complete path

Run the existing dialog methods with synthetic messages in each supported execution mode. Read the complete message and every visible choice through AX and VoiceOver. Activate each choice and assert the caller's actual return value. Exercise long messages and any sizing behavior used by the application.

Then run the real workflow through the integrated prompt and check its business result. A dialog test alone does not prove that its caller handles nested form ownership, acceptance or cancellation correctly. Retain the original form's visual properties and compare rendered output when a form is replaced or its layout changes.

This approach supports an application that routes its prompts through accessible forms. Remaining direct built-in calls still need migration or a vendor fix; installing the plugin does not intercept them.
