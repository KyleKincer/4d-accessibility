# List-subform acceptance

The owned fixture uses 600 synthetic records and a named classic list-row form. Its parent has the lifecycle area; its row and field methods only implement and observe ordinary 4D behavior. Default preparation has no `AXB_Configure` callback. The installer generates layout metadata without changing the row form.

Preparation uses a licensed 4D Server to compile both targets, as described in [building](../CONTRIBUTING.md). Close other 4D applications and run preparation and desktop tests sequentially:

```sh
python3 prepare_list_subform_fixture.py --server /path/to/4D\ Server.app
python3 test_list_subform_fixture.py --run
```

Prepare again before every mutating run to restore synthetic data. Add `--compiled` to the desktop command for compiled execution. Preparation compiles ARM and Intel targets; the driver verifies the actual architecture, compiler input hashes, metadata and matching package hashes. `--intel` runs the desktop under Rosetta.

Prepare with `--selection-mode multiple`, `single`, `none` or `default` to check the corresponding native behavior. `--header --multiline` adds static header captions and taller multiline records. `--configured` supplies central labels and a loading-readiness Formula. `--table-parent` opens a table input parent instead of a project form. `--no-area --auto-modify` prepares the native buffer baseline, without an accessibility registration, for comparison with the application's ordinary repaint behavior.

`--no-primary-key` enables central configuration, removes the table's declared primary key after seeding, and supplies its existing `id` field through central `keyProperty` configuration. The driver checks that the actual datastore lacks that mapping. Its stored-value observer uses an independent private native reader.

`--text-key` enables central configuration with the existing stored `name` field as the key. It checks saved case, accent and `@` changes, exact live locators and rejection of retained old-key handles.

`--horizontal` forces a visible horizontal scrollbar and a wider row definition. The driver verifies that the scrollbar really appears before checking actions.

`--diagnostics-test` deliberately combines missing parent settings with an invalid row key. The driver requires both diagnostics, a disabled public table and a still-usable ordinary editor. It verifies that binding failure does not hide a separate integration problem.

The complete sequential matrix prepares fresh data for both desktop modes and archives every report:

```sh
python3 test_list_subform_matrix.py --server /path/to/4D\ Server.app --run --voiceover --intel --pixels
```

`--case` selects `automatic`, `table-parent`, `single-header-multiline`, `nonselectable`, `native-default`, `configured-header-multiline`, `existing-key-no-primary`, `text-key` `horizontal` or `invalid-identity-diagnostics`. Repeat it to select several cases. `table-parent` also uses a header and an existing key without a declared primary key. `--intel` adds one compiled single-selection header/multiline Rosetta case; `--voiceover` adds one compiled header/multiline spoken case. These additional phases still run when `--case` filters the ordinary matrix. `native-default` omits the parent's `selectionMode` property. The desktop report is `build/list-subform-desktop-report.json`; matrix reports and per-run compiler/desktop files are archived in `build/list-subform-acceptance-<stamp>/`. Source hashes stay fixed throughout each matrix. The matrix stops at the first failed run. Pixel checks compare the complete compiled window with and without registration, with zero tolerance or masking, and verify that the original parent and row-form definitions are unchanged.

Pixel comparisons can also run independently with `test_list_subform_pixels.py --server /path/to/4D\ Server.app --run`, optionally adding `--header --multiline`.

The desktop driver reads first and distant rows, checks stored primary-key locators, reveals a distant record, inspects a modified buffer, edits through the original native field and checkbox, and verifies fresh stored values. It checks original callbacks and native selection including clearing. AX transport success alone never passes an action; each case checks application completion and the actual result. The VoiceOver case also records receipt transitions because a later automatic reveal can replace the latest status message. It navigates to the ordinary inspection button and activates it through VoiceOver, then verifies one original handler call, a completion receipt and independently read saved data. VoiceOver remains the sole input actor during that phase; read-only AX observations can run concurrently.

For a standalone spoken check, prepare its required header/multiline layout:

```sh
python3 prepare_list_subform_fixture.py --server /path/to/4D\ Server.app --header --multiline
python3 test_list_subform_fixture.py --run --compiled --voiceover
```

This checks spoken navigation to the final record and native checkbox activation. VoiceOver and graphical tests must own the desktop exclusively. The VoiceOver phase fails if VoiceOver is already running; an existing session belongs to the user.

Integration, behavior and remaining limits are documented in [classic list subforms](../skills/4d-accessibility/references/LIST-SUBFORMS.md). Keep failed and untested cases in [current status](../skills/4d-accessibility/references/STATUS.md).
