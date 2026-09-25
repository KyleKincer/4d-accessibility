# Exercise an existing window through AX

Run this from the matching checkout or complete kit in an unlocked session. First find the target PID with `pgrep -x 4D`, then use `inspect_ax.py` on its exact window title. Copy the full `AXIdentifier` of the ordinary field or button and of the bridge root beginning `axb.window.` from that report. Use synthetic data in a permitted test window. Bring that window to the foreground through the normal application UI before sending input. The read-only inspector does not activate it; native editor actions require the correct active window.

This Python recipe resolves ordinary controls without expanding logical tables. Replace the four example strings/numbers with the observed values. Keep this local test script out of the host project.

```python
import sys
sys.path.insert(0, "tests")
import mac_ax as ax

pid = 12345
window_title = "Customer details"
root_id = "axb.window.REPLACE_FROM_INSPECTOR"
field_id = "REPLACE_WITH_FULL_FIELD_IDENTIFIER"
app = ax.application(pid)
windows = [w for w in app.slice("AXWindows", 0, 100)
           if w.read("AXTitle") == window_title]
assert len(windows) == 1, "Window title must identify exactly one window"
window = windows[0]


def find(identifier):
    pending = [window]
    seen = []
    while pending and len(seen) < 2000:
        item = pending.pop()
        if any(item.same_as(old) for old in seen):
            continue
        seen.append(item)
        if item.read("AXIdentifier") == identifier:
            return item
        if item.read("AXRole") in {"AXTable", "AXOutline"}:
            continue
        try:
            count = item.count("AXChildren")
        except RuntimeError:
            continue
        assert count <= 100, "Use bounded slices for this larger branch"
        pending.extend(item.slice("AXChildren", 0, count))
    raise AssertionError("Identifier not found within the selected window and bound")


root = find(root_id)
field = find(field_id)
assert field.read("AXRole") == "AXTextField"
assert field.read("AXEnabled") is True
assert field.is_settable("AXValue")
assert field.set_text("Accessibility test") == 0  # Transport accepted only.
ax.wait_for(lambda: field.read("AXValue") == "Accessibility test",
            "Editor did not expose the requested text", timeout=15)
print("Receipt:", root.read("AXHelp"))
```

Next leave the field through its ordinary UI path and verify validation and committed application state. The displayed editor text can still be uncommitted. To test a known ordinary button, resolve its full identifier with `find`, require `AXPress` in `button.actions()`, then call `button.press()`. Verify the specific result, such as a changed synthetic value or the expected dialog, rather than only the return code. Wait for each action's observable outcome before sending another.

For a grid, resolve the table identifier with `find`. Use `table.count("AXRows")` and `table.cell(column, row)` with zero-based logical indices. Read its value. If `"AXScrollToVisible" in cell.actions()`, call `cell.perform("AXScrollToVisible")` and verify the visible rows before separately selecting or editing. Reveal currently requires macOS 26; earlier versions remain unfinished. Keep retained `Element` objects to test stale-reference rejection after replacement; resolving the new element by name would skip that test.

Grid values and cell permissions load on demand. Before editing a cell you expect to be editable, wait with a bounded timeout for `cell.is_settable("AXValue")`. A newly added or distant cell can exist before that becomes true. Send the edit once, then verify the actual editor value and normal commit. If the permission stays false, inspect the cell and application state; a read-only or disabled cell must remain protected.

Read `root.read("AXHelp")` before and after the action. Queued/waiting messages mean the application has not finished. A previous completed receipt can still be present immediately after sending another request. Use the expected control/model change as the completion check, and inspect failures before retrying. A rejected receipt does not prove rollback. For action/receipt correlation during deeper diagnosis, inspect `Form.axbForm.receipt` from the root's existing debugger context only for plain local data roots. Entity, class-instance and shared roots keep that state in the window registry; use the standard `AXHelp` receipt and resulting UI state for any root type.

This recipe exercises standard AX actions. It does not validate VoiceOver speech, keyboard order, native validation or business results by itself. Continue with [the scenario checks](VERIFY.md#scenario-checks).
