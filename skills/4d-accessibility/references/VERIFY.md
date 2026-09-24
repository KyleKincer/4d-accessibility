# Verify an integrating application

Use a permitted non-production window and its real UI state. Desktop and assistive-technology checks require a graphical session; a headless build cannot substitute for them.

## Read the public accessibility tree

The complete release kit and source checkout provide a read-only inspector for arbitrary host windows:

```sh
python3 inspect_ax.py --pid 12345 --window-title "Customer details" --output /host-local/ignored/customer-ax.json
```

Use the actual process ID and exact window title, and a fresh `--output` path for each run. The inspector refuses to overwrite an existing file. The invoking app needs normal macOS Accessibility permission. The script sends no actions, focus changes, mouse events or keystrokes. It reports roles, identifiers, names, state, geometry, offered actions, logical table counts and the bridge root's receipt. It reads bounded slices and records truncation. Use `--row-start 590` to sample distant logical rows and `--include-values` when the test requires field values. Use an existing ignored host-local output directory. Reports are private mode-0600 files; labels and identifiers can also contain application data. Keep them outside source control.

A truncated sample does not establish entire-UI coverage. Traverse omitted branches and logical row ranges with a suitable AX client. A native provider can coexist with the bridge; inspect both. `AXHelp` on the root whose identifier begins `axb.window.` is the action receipt, not the internal coverage diagnostics.

For coverage reasons such as `providerPending`, obtain `AXB_Form("diagnostics"; New object)` in the root's debugger context or through a temporary development-only export. Record every issue's path/object/reason, then remove the export. Inspect every runtime page and state, not only source form definitions.

## Exercise actions and VoiceOver

Use [the external action recipe](AX-ACTIONS.md) to resolve a known identifier in one selected window, set an ordinary field or press a control, and inspect the receipt and result. The recipe uses `tests/mac_ax.py`, included in the complete kit. It requires no host test method.

For VoiceOver, bring the permitted test window forward and turn VoiceOver on. With the default modifiers, VO means Control-Option. Use VO-Right/Left to traverse controls, VO-Shift-Down to enter a group or table, and VO-Shift-Up to leave it. Use VO-Space to activate the current item. These are [Apple's interaction commands](https://support.apple.com/guide/voiceover/interaction-commands-cpvokys07/mac) and [navigation commands](https://support.apple.com/guide/voiceover/navigation-commands-cpvokys04/mac).

Read an ordinary field, edit synthetic text and leave it to trigger native validation. Enter each grid, navigate beyond the initial viewport, read a distant cell, then activate it separately with VO-Space. Leave the grid and reach the next ordinary control. Repeat for sibling children, other pages, transient menus and validation failures. Record what VoiceOver actually speaks, including stale Loading announcements, along with the resulting UI state. Knowing the intended label from the AX tree is not evidence that it was spoken.

## Scenario checks

| Scenario | Observable pass criterion |
| --- | --- |
| Ordinary edit | A named `AXTextField` or appropriate typed role exposes the expected readable value, enabled state and permitted actions. Edit through the real editor, leave the field, and verify native validation and committed model state. Protected text remains undisclosed. |
| Logical grid | `AXRows` count matches the complete displayed logical dataset, while `AXVisibleRows` matches the viewport. Read a distant cell by logical row/column, reveal it, and activate it separately. Selection and any existing refresh handler must refer to the original stable row key. |
| Repeated children | Equal object names/row keys have distinct AX identities in each child. Reading or acting on one instance uses its own data, viewport and handlers. Shared plain bindings retain their intentional sharing. |
| Child replacement or record change | A newly published element gets the new identity/scope. An old retained element cannot edit or activate the replacement, even if labels or keys are reused. Repeat inside nested children. |
| Asynchronous load | While readiness is false, the grid is unavailable and diagnostics report loading. A late response for an old record never exposes its rows under the new record's scope. The correct completion publishes the current rows and meaningful status. |
| Action receipt | AX transport accepts or rejects the request. A bridge root may then report queued/waiting and a final message. Verify actual control/model state after callbacks settle. An unsuccessful receipt can follow an already-delivered action; do not replay automatically. |
| Entire workflow | VoiceOver can reach every meaningful active control, open/dismiss transient UI, edit, recover from a validation error and finish the business operation. Verify resulting application state through its ordinary UI or authorized data checks. |

Use `AXIdentifier` to retain elements for stale-reference tests. Ordinary control IDs can remain stable through scrolling; replacement and scope changes must retire prior actionable identities. Sorting keeps a row attached to its original key, not its old index.

Run the same scenario in each claimed execution mode. Record the version/hash, macOS/4D/vendor versions, mode, expected result, observed result and any blocking prerequisite. If live tests cannot run, deliver the source changes and exact test debt while keeping accessibility completion pending.
