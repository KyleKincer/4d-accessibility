# Native web-area acceptance

This disposable fixture combines a system or embedded web area with ordinary 4D controls. It uses synthetic HTML without JavaScript and a loopback-only HTTP server. Native browser accessibility owns the HTML operations. The matching plugin, component and installed helpers come from the supplied complete kit. The baseline contains none of those parts.

## Run sequentially

Use an unlocked macOS desktop, 4D 20.8 desktop at `/Applications/4D/4D.app`, a licensed 4D Server compiler and Accessibility/Screen Recording permission for the test host. Choose a complete area-capable kit; the recorded gate uses 0.22.0. Close existing 4D and VoiceOver sessions. Run every compiler, AppKit and graphical test sequentially.

Run the complete seven-case gate in a Python environment with Pillow:

```sh
python3 test_web_matrix.py --run --server '/path/to/4D Server.app' --kit /path/to/complete-kit
```

The matrix also compares the original browser event sequences between baseline and integrated action runs. It rejects reports from an older desktop driver. `--collect` verifies existing reports without launching applications and writes `build/web-system-matrix.json`. To run individual cases while diagnosing a failure, use the following commands.

```sh
python3 prepare_web_fixture.py --server '/path/to/4D Server.app' --kit /path/to/complete-kit
python3 test_web_fixture.py --run
python3 test_web_fixture.py --run --compiled
python3 test_web_fixture.py --run --compiled --read-only --voiceover
```

Preparation checks both ARM and x86 compiler targets and records source, HTML and package hashes. The desktop driver verifies the actual execution mode, fixture process/window and each native mouse target's owning PID. Integrated runs also require one active lifecycle registration, matching loaded plugin/component versions and capabilities, and exactly the expected web-area `providerPending` diagnostic. A floating authentication dialog can cover a target even while 4D is frontmost. Such an obstruction must fail the input guard rather than be mistaken for a control defect.

The action case checks native text replacement, checkbox activation, reset, pointer/keyboard disclosure, invalid email rejection, actual submitted values and browser link navigation. The integrated case then commits an ordinary 4D edit, requires its original button handler exactly once, and returns focus to HTML. It does not assign browser or 4D bindings or call business handlers itself. Native editing establishes actual focus before replacement. After a browser validation prompt, normal Shift-Tab moves to the previous editor.

Run the same browser actions without the bridge:

```sh
python3 prepare_web_fixture.py --server '/path/to/4D Server.app' --kit /path/to/complete-kit --baseline
python3 test_web_fixture.py --run
python3 test_web_fixture.py --run --compiled
```

Compare the whole compiled window, with no masks or tolerance:

```sh
python3 test_web_pixels.py --server '/path/to/4D Server.app' --kit /path/to/complete-kit --run
```

The pixel driver requires Pillow in the current Python environment, and prepares and closes each variant in sequence. Both variants activate the same ordinary button through normal mouse input before capture, avoiding a blinking text caret. It checks the original value and settled rendering before comparing every pixel. VoiceOver and pixel acceptance are compiled-only; action acceptance covers both execution modes. Both compiler targets pass, but these desktop runs do not establish Intel hardware coverage.

## Engines and evidence

Preparation defaults to `--engine system`. Use `--engine embedded` for the Chromium case and begin with `test_web_fixture.py --run --read-only`. A missing `AXWebArea` is a failure, including when its content remains visible. Native system-engine evidence does not cover the embedded engine.

Reproduce the bridge-free post-load VoiceOver probe with:

```sh
python3 prepare_web_fixture.py --server '/path/to/4D Server.app' --kit /path/to/complete-kit --engine embedded --baseline
python3 test_web_fixture.py --run --read-only --voiceover
```

The recorded embedded probe is historical and has its own driver hash. Prelaunch VoiceOver is untested. `--read-only` skips browser editing and submission; adding `--voiceover` still toggles the checkbox and disclosure, then restores both. The integrated fixture's timer polls bridge diagnostics every six ticks as test instrumentation; ordinary host integration needs no such timer calls.

The driver archives each successful or failed report under ignored `build/`, including requests, original handler state, tree observations, source/package hashes and owned-process exit. Rerun the full matrix after changing the driver. Compare `browserEvents` between baseline and bridge action runs before the integrated case's extra 4D editing, and require the same original event sequence for each execution mode. The integrated timer also reads bridge diagnostics and kit information; those calls are absent from the baseline.

[Published evidence](../validation/native-web-areas.json) is the authority for accepted cases and known gaps, including the native web content's sibling reading order. The fixture does not validate arbitrary scripts, browser popups, cross-origin frames, engine switching, remote delivery or third-party plugin editors.
