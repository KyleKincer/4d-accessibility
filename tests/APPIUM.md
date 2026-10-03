# Appium Mac2 acceptance

This test uses Appium's Mac2 driver and XCTest against the disposable [classic list-subform fixture](LIST-SUBFORMS.md). It reads the native tree, finds the logical table, ordinary editor and button by their bridge identifiers, then clicks the original inspection button. The fixture independently records the handler count and saved-data read. XCTest's click uses native mouse input, so this is separate from the bridge's AXPress and completion-receipt tests.

## Run sequentially

Use an unlocked macOS desktop with 4D 20.8 at `/Applications/4D/4D.app`, a licensed 4D Server compiler, Xcode and an installed Appium Mac2 driver. Follow [Mac2's setup requirements](https://appium.github.io/appium-mac2-driver/v4/getting-started/), including Accessibility permission for Xcode Helper and Apple's unattended-test authentication setting. The invoking test process also needs Accessibility permission. Close existing 4D, Appium and VoiceOver sessions. Run every desktop fixture and 4D compiler sequentially.

Prepare a fresh synthetic database with the default preparer options and run both modes with the same driver. The report records the measured 4D version, Appium/Mac2 versions and host architecture:

```sh
python3 prepare_list_subform_fixture.py --server '/path/to/4D Server.app'
python3 test_appium_list_fixture.py --run \
  --appium /path/to/node_modules/.bin/appium \
  --appium-home /path/to/appium-home
python3 test_appium_list_fixture.py --run --compiled \
  --appium /path/to/node_modules/.bin/appium \
  --appium-home /path/to/appium-home
```

The test owns a loopback Appium server on port 4725 and WebDriverAgent on port 10125. Both ports must be free. It opens only the prepared fixture, verifies its actual execution mode and package hashes, and closes its session and fixture afterward. Cleanup failures make the report fail. It preserves the XML, request durations and passing or failing reports under ignored `build/`. A full XCTest snapshot includes the logical grid rows and can be large; retain measured lookup times when assessing automation performance.

Completion requires the native XML roles and stable identifiers, successful identifier lookups, unchanged record/selection/modified state during discovery, and exactly one original inspection-handler execution with an independently completed saved-data read. An HTTP success response alone does not satisfy the gate.

The [recorded 0.22.0 gate](../validation/appium-0.22.0.json) passes 18 checks in each execution mode with one unchanged driver and the exact main CI binaries. It records Appium 3.8.0, Mac2 4.3.6, 4D 20.8 and the request durations. Window-scoped identifier queries take roughly 34–36 seconds on this 600-row fixture; this establishes functional acceptance, with larger-form performance still open.

## Scope

This establishes the tested local synthetic parent through Mac2/XCTest. It does not establish grid editing, distant-row actions, save/reopen, locator reacquisition after replacement, real application workflows, QA-Driver or SQUASH runner execution, remote client delivery or acceptable performance on larger forms. The [stable-identifier contract](../skills/4d-accessibility/references/IDENTIFIERS.md) still requires window scoping and fresh element handles after reopen or record changes.
