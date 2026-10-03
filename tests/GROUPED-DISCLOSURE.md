# Application-controlled grouped disclosure

The 0.24.0 development adapter adds explicit disclosure to the text/date array
hierarchies described in [the read-only guide](GROUPED-OUTLINES.md). The owning
application supplies the controller. The bridge resolves and guards the target,
invokes that controller once, then independently confirms the resulting state.
Selection, reveal and editing remain unavailable for these grouped providers.

## Configure the existing listbox

Keep its native hierarchy arrays, objects, handlers and drawing. Supply stable
row keys and a readiness Formula as described in the read-only guide. Add one
stable Formula instance to the grid options:

```4d
$options.grids.Grouped:=New object("kind"; "outline"; "keyColumn"; "RowKey"; \
 "ready"; Formula(Form.rowsReady); "setExpanded"; Formula(My_SetExpanded($1)))
```

The callback receives a new object with exactly these fields:

| Field | Meaning |
| --- | --- |
| `objectName` | Configured native listbox name in the current owning form. |
| `backingRow` | One-based backing-array row identifying this break. |
| `breakLevel` | One-based native hierarchy level. |
| `expanded` | Requested Boolean state. |
| `actionID` | Opaque identifier for this one controller invocation. |

The application should validate its expected form, table and listbox, and use
the targeted native command without recursive expansion:

```4d
If ($request.expanded)
 LISTBOX EXPAND(*; $request.objectName; False; lk break row; $request.backingRow; $request.breakLevel)
Else
 LISTBOX COLLAPSE(*; $request.objectName; False; lk break row; $request.backingRow; $request.breakLevel)
End if
```

Do not derive these coordinates from a caption, select a row, click a header or
transfer focus. A repeated caption can identify several distinct groups. A
Formula replacement or removal changes provider generation and retires queued
authority. Loading, scope, parent or membership changes also invalidate stale
targets. Keep readiness false while replacing or partially filling arrays.

## Actions and completion

A live group row exposes the `AXDisclosing` Boolean setter. Group rows, their
first cells and their disclosure-triangle children support `AXPress`. The child
has the group caption as its label and current expansion as its Boolean value;
the structural cell retains its caption value. The triangle is a virtual
controller-backed element using the known group-cell bounds. It does not claim
a separately discovered physical hit target or change native drawing.

An accepted AX call queues intent. Wait for the root receipt before reporting
application completion. Idempotent requests validate authority and finish
without invoking the callback. Other requests call it once and allow two seconds
for confirmation after it returns. Confirmation checks current controller,
group semantics and native focus/editor ownership. It never retries the callback.

Disclosure bypasses the usual pre-action reveal. Offscreen or clipped targets
therefore do not scroll ancestor subforms. The targeted native command may adjust
the listbox's own scrolling or deselect newly hidden descendants, exactly as an
ordinary native command does. Native grid editing and ambiguous unrelated editor
ownership reject before callback invocation. An exactly resolved unrelated local
editor retains its pending text and highlight.

VoiceOver can activate the triangle or group row with Control-Option-Space.
Value and row notifications retain the standard semantics. When those do not
speak the stationary control's changed state, one receipt-backed bridge
announcement supplies the confirmed English caption and expansion state.
Rejected, expired, replaced or superseded requests cannot announce success.
This does not establish the absence of additional speech from VoiceOver itself.

## Run the gate

Use matching packages and an unlocked graphical session. Run all 4D compiler
drivers and graphical fixtures sequentially.

```sh
python3 build.py
python3 build_component.py --tool4d /path/to/tool4d.app
python3 prepare_hierarchy_probe.py --server '/path/to/4D Server.app' --bridge --disclosure --subforms
python3 test_outline_action_helpers.py --tool4d /path/to/tool4d.app
uv run --with pillow==12.1.0 python3 test_grouped_disclosure.py --run
uv run --with pillow==12.1.0 python3 test_grouped_disclosure.py --run --compiled
uv run --with pillow==12.1.0 python3 test_grouped_disclosure.py --run --compiled --voiceover
uv run --with pillow==12.1.0 python3 test_grouped_disclosure_subforms.py --run
uv run --with pillow==12.1.0 python3 test_grouped_disclosure_subforms.py --run --compiled
python3 test_grouped_outline.py --run --native-baseline
python3 test_grouped_outline.py --run
python3 test_grouped_outline.py --run --compiled --native-baseline
python3 test_grouped_outline.py --run --compiled
python3 test_grouped_outline.py --run --compiled --voiceover
python3 test_grid_value_speech.py --run
python3 tests/test_grouped_disclosure_summary.py
uv run --with pillow==12.1.0 python3 summarize_grouped_disclosure.py
```

One immutable compiled project contains standalone and repeated nested layouts.
The drivers select the layout and whether the standalone configuration supplies
a controller through owned resource files. The read-only baseline temporarily
removes both packages and verifies their exact restoration. No Symphony package
or business data is changed by these commands.

The standalone action gate compares collapse against the ordinary targeted
native command for text, date and nested groups. The repeated fixture starts
both scroll axes at two ancestor levels with nonzero values, checks independent
bindings and duplicate names, preserves sibling data and pending editing, and
rejects requests across scope/readiness changes and native child replacement.
Replacement initializes the new child's own scroll at zero; its parents and
sibling remain unchanged. Cleanup includes the native trees of retired children.

The publisher requires complete action outcomes and callbacks, actual fault
mutations, confirmed VoiceOver state and subsequent navigation, exact source and
artifact sets, normal shutdown and zero changed RGBA pixels across complete
windows. It rejects the narrower `--voiceover-only` debugging run and erases old
success before validating inputs.

This gate covers synthetic array hierarchies. Actual Symphony Alerts/date
workflows, classic trees, other caption types, lazy loading, complete selection,
Voice Control, Switch Control, physical Intel, client/server operation and signed
distribution remain separate requirements.
