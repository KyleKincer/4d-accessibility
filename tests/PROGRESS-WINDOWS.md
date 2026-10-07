# Progress windows

The windows of 4D's Progress component (`Progress New`, `Progress SET TITLE`, `Progress SET MESSAGE`, `Progress SET PROGRESS`, `Progress SET BUTTON ENABLED`) are published by the native plugin alone. They need no host method, component call or configuration. Without the plugin, macOS publishes only the window's title-bar buttons.

The component draws all current progresses in one window, each in its own subform whose objects are named layers: `Message1` (the title), `ThermoProgress` (the bar), `Message2` (the message) and `StopButton`. It also draws the stored progress, in an object named `ProgressValue` placed outside the window. The plugin reads the text 4D draws in each one and publishes, for each progress, top to bottom:

- an indicator labelled with the title. Its value is the progress as a percentage, from 0 to 100. An indeterminate progress (`-1`) has no value, as AppKit's indicators report it. Its frame includes the title, so VoiceOver reads it before the message, as it is seen;
- the message as static text, when there is one;
- a Stop button, when the progress has one. A press posts an ordinary click at its center, so `Progress Stopped` reports it exactly as for the mouse.

A change in the title, message or progress is announced on its element. A finished progress leaves the tree; the others keep their elements. Recognition is strict: a form context is a progress only when it holds `Message1` and `ThermoProgress`. Any other window is left untouched.

## Test

```sh
python3 test_progress_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_progress_fixture.py --server /path/to/4D\ Server.app --run
python3 test_progress_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_progress_fixture.py` builds a project whose startup method shows a determinate progress, with a message and an enabled Stop button, and an indeterminate one. The AX run checks an unchanged window, the published roles, labels, values and message, then advances the progress and presses Stop. The startup method records `Progress Stopped` and quits. The VoiceOver run reads the indicator, the message and the Stop button, then stops the progress with VO-Space. Add `--compiled` or `--intel` for the other modes. The indeterminate bar animates, so the pixel comparison skips its frame.

[Acceptance](../validation/progress-windows-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with the window pixel-identical to the plugin-free window apart from the animated bar; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta.

Remaining scope: 4D Server and remote clients, localized titles and messages, and 4D on Windows.
