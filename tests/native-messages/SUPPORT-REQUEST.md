# macOS: CONFIRM and ALERT expose no accessible message or buttons

In 4D 20.8 build 20.102009 on macOS 26.7, the standard `CONFIRM` and `ALERT` dialogs expose an `AXWindow` containing one empty `AXStaticText`. Their visible messages and buttons are missing from the accessibility tree. We reproduced this on Apple Silicon in both native ARM and x86_64/Rosetta execution.

The attached standalone project contains no plugin, component or replacement form. Its startup method calls:

```4d
CONFIRM("AX confirmation probe"; "Continue"; "Cancel")
ALERT("AX alert probe"; "Close")
```

Open `Project/NativeMessages.4DProject` and inspect the confirmation with Accessibility Inspector. After pressing Return, inspect the alert. The messages are visible on screen, but neither their text nor their named buttons appears in the AX tree. The project exits after the alert closes. The adjacent README gives the full steps. Progress files contain only synthetic test state.

Expected: readable message text and separately named buttons with normal accessibility activation, while preserving the existing dialog appearance and `OK` result. This is needed for screen readers and semantic automation. Keyboard-only acceptance cannot tell an agent or screen-reader user what the dialog asks.

Could you confirm whether this is fixed in a supported 4D build? If not, is there a supported plugin API that can enumerate the original dialog's message/buttons, obtain their actual bounds and activate them while it is open? We need to preserve the original rendering rather than substitute a visually different dialog.

The complete AX observations and environment are in [the validation report](../../validation/native-messages.json). There is no application data, credential or licensed binary in the reproduction.
