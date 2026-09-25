# Standard 4D message accessibility reproduction

This project calls `CONFIRM` and `ALERT` directly. It contains no plugin, component or replacement form. The dialogs keep their original 4D appearance and behavior.

1. Close other 4D instances and open `Project/NativeMessages.4DProject` in 4D on macOS. A 4D development license may be required.
2. Inspect the confirmation with Apple's Accessibility Inspector or VoiceOver. The message is **AX confirmation probe**; its buttons are **Continue** and **Cancel**. Check for readable message text and named, actionable buttons.
3. Press Return to reach the alert if the accessibility controls are unavailable. Its message is **AX alert probe** and its button is **Close**. Inspect it the same way.
4. Close the alert. The project quits 4D. `Resources/phase.json` records progress and contains only synthetic test state.

An automation runner can launch the project with `--dataless --opening-mode interpreted`. Return is diagnostic setup/cleanup when controls are missing; it is not an accessibility pass. Do not use this project in an existing application's process.

The expected accessible result is a readable message and separately named buttons whose actions preserve 4D's normal confirmation result. Missing elements block semantic automation and screen-reader navigation even when a sighted user can use the keyboard.

The [recorded run](../../validation/native-messages.json) reproduces missing message text and buttons on 4D 20.8 build 20.102009/macOS 26.7 in native ARM and Rosetta execution. [Prepared support request](SUPPORT-REQUEST.md). The report remains failed until the original dialogs expose these controls.
