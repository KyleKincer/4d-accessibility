# Recorded accessibility examples

These are actual 4D 20.8 recordings on macOS, driven by an external accessibility client and VoiceOver. Captions come from timestamped AX calls, application assertions and VoiceOver's caption panel. An AX transport return alone is not counted as application completion.

The videos show only 4D's windows, cropped for readability, at 1.5× playback speed. They have no audio. Data is synthetic. [Video hashes and assertions](validation/recorded-examples.json) identify the exact captures. They were recorded with the signed 0.19.6 draft; 0.19.7 preserves the same provider and host-helper behavior and corrects package wording and a test's asynchronous speech observation.

## Native grids and repeated subforms

https://github.com/user-attachments/assets/e2177f60-df66-4fc6-9de6-5e5c382ddec4

[Download the native-grid video](https://github.com/KyleKincer/4d-accessibility/releases/download/v0.19.7/native-grids.mp4).

Two instances of the same subform keep separate identities and checkbox bindings. VoiceOver activates a checkbox and native popup, reaches the last logical row beyond the viewport, and returns to an ordinary editor. All 39 compiled checks pass.

Reproduce with the matching packages in `build/` and a licensed local 4D installation:

```sh
python3 prepare_grid_fixture.py --server '/path/to/4D Server.app' \
  --collection --row-states --cell-controls --subform --repeated
python3 test_grid_controls_fixture.py --run --compiled --voiceover
```

## AreaList editing and validation

https://github.com/user-attachments/assets/710f9760-04cd-4838-93b3-19614d90c61b

[Download the AreaList video](https://github.com/KyleKincer/4d-accessibility/releases/download/v0.19.7/arealist.mp4).

The existing vendor editor commits complete text before a checkbox action. Rejected text prevents that action; correcting it permits the normal handler. Disabled permissions and retired elements prevent mutation. Sorting preserves row identity. VoiceOver activates a checkbox and returns to an ordinary field. All 37 compiled checks pass.

```sh
python3 prepare_alp_grid_fixture.py --server '/path/to/4D Server.app' \
  --area-list-plugin '/path/to/ALP.bundle' \
  --license-file '/protected/path/alp.license' --controls --key-type longint
python3 test_alp_controls_fixture.py --run --compiled --voiceover
```

Run graphical fixtures sequentially. The license file must have mode `0600`; it is never part of a release. See [build instructions](CONTRIBUTING.md) for machine permissions and prerequisites.

## What these recordings establish

These fixtures demonstrate the listed controls, actions and assertions. They do not establish every application workflow or full UI coverage. The [support status](skills/4d-accessibility/references/STATUS.md) lists remaining families and platform limits. A fixed-delay checkbox speech check initially sampled the prior caption; the corrected bounded observation and its eleven-trial result are recorded in [validation](validation/checkbox-speech-observation.json). No input replay or focus change forces that announcement.
