# Standard 4D message accessibility reproduction

This project calls `CONFIRM` and `ALERT` directly. It contains no plugin, component or replacement form. The dialogs keep their original 4D appearance and behavior.

1. Close other 4D instances and open `Project/NativeMessages.4DProject` in 4D on macOS. A 4D development license may be required.
2. Inspect the confirmation with Apple's Accessibility Inspector or VoiceOver. The message is **AX confirmation probe**; its buttons are **Continue** and **Cancel**. Check for readable message text and named, actionable buttons.
3. Press Return to reach the alert if the accessibility controls are unavailable. Its message is **AX alert probe** and its button is **Close**. Inspect it the same way.
4. Close the alert. The project quits 4D. `Resources/phase.json` records progress and contains only synthetic test state.

An automation runner can launch the project with `--dataless --opening-mode interpreted`. Return is diagnostic setup/cleanup when controls are missing; it is not an accessibility pass. Do not use this project in an existing application's process.

The expected accessible result is a readable message and separately named buttons whose actions preserve 4D's normal confirmation result. Missing elements block semantic automation and screen-reader navigation even when a sighted user can use the keyboard.

The [recorded run](../../validation/native-messages.json) reproduces missing message text and buttons on 4D 20.8 build 20.102009/macOS 26.7 in native ARM and Rosetta execution. [Prepared support request](SUPPORT-REQUEST.md). The report remains failed until the original dialogs expose these controls.

## With the native plugin

`test_native_messages.py` copies this project into `build/`, adds the built plugin and opens two CONFIRMs, an ALERT and three Requests in turn. It reads each window and operates every choice through accessibility, then checks 4D's own `OK` and answer:

- `--run` adds AX checks in native ARM; add `--intel` for Rosetta. `--compiled --server /path/to/4D\ Server.app` compiles the copy first.
- `--voiceover` uses VoiceOver navigation, activation and typing echo.
- `--baseline` first records this project's plugin-free windows. A later `--run` then requires the same pixels before any action.

The [provider record](../../validation/native-messages-provider.json) passes all eight combinations. This plugin-free project and its failed record stay unchanged as the vendor reproduction.
