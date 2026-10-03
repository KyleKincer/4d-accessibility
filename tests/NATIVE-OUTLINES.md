# Native outline provider

The production logical-grid model accepts application-owned outline metadata. It publishes an `AXOutline`, structural rows, logical disclosure relationships and group labels. Stable 0.22.1 host adapters reject hierarchical controls. The separate [0.23.0 development grouped gate](GROUPED-OUTLINES.md) adds read-only text/date array capture. Full 4D hierarchy interaction remains unimplemented.

## Descriptor

Keep the logical node's `role` as `table`. Its grid may add `outline`, an object keyed by every currently disclosed row in `rows`. Rows remain in depth-first order. Each entry has `parent`, `level` and `kind`. Roots have an empty parent and level zero; children name an earlier expanded group at the preceding level. Levels range from zero through 31. Groups add `label`, a Boolean `expanded` and a positive logical `frame` with four numbers. Leaves omit those properties.

```json
{
  "rows": ["group/1", "leaf/1"],
  "outline": {
    "group/1": {"parent": "", "level": 0, "kind": "group", "label": "Group", "expanded": true, "frame": [20, 60, 500, 24]},
    "leaf/1": {"parent": "group/1", "level": 1, "kind": "leaf"}
  },
  "selectionKnown": false,
  "actions": {"select": false, "reveal": false, "edit": false}
}
```

The fragment omits the ordinary required grid properties, including generation, order and columns. Group frames are unclipped logical bounds; viewport `frames` remain clipped and use only the first column for groups. A group exposes its label immediately without a value-page request or an editor. In a mixed value page, its first cell must contain that exact label, other cells must be empty, and every group cell must be read-only text.

Use `selectionKnown: false` when complete selection is unavailable. Omit `selected` and disable selection actions. The native provider then omits selected attributes and rejects selection setters, including retained row and cell references. Flat grids retain their existing known-selection contract.

Increment order for topology, label or expansion changes. Geometry updates alone keep order and cached leaf values. Changing a row's kind or parent requires a new key or generation. Replacing the generation retires retained descendants; changing between table and outline also retires the root. Removing a disclosed row retires its native handles, so reopening reacquires fresh descendants. Applications remain responsible for authoritative identity and state.

No disclosure action is implemented. `AXDisclosing` reports supplied state, and `AXDisclosedRows` lists direct children. An unknown hidden descendant state must stay internal until the application can describe it accurately.

## Acceptance

Run sequentially in an unlocked graphical session with the existing Accessibility and screen-recording permissions:

```sh
python3 tests/test_native_outline_driver.py
python3 test_native_outlines.py --run
python3 test_native_outlines.py --run --voiceover
python3 summarize_native_outlines.py --output validation/native-outlines-development.json
```

Omit `--run` to compile only. The owned AppKit fixture uses production Session, Grid, Bridge, GridNative and NativeLayout sources. It has repeated group labels, a nested group, 25 disclosed rows and a ten-row viewport. Plain AX passes 47 checks; the separate VoiceOver run passes 52. [Recorded evidence](../validation/native-outlines-development.json) includes all production source hashes, fixture/driver hashes, normal close and individual speech captions. Missing inputs invalidate old success before compilation or launch.

VoiceOver reads the nested group at level 1 and its leaf at level 2, then reaches the final offscreen row with End. It says `table` on entry despite the exposed `AXOutline` and `outline` role description. External fixture commands change disclosure after VoiceOver stops, so spoken disclosure transitions remain untested. This foundation record claims no 4D adapter, native disclosure action, hierarchy editing, lazy loading, Symphony workflow, unchanged-pixel or signed-distribution acceptance. Its final offscreen value was loaded before VoiceOver End; the separate grouped/cold-value gate checks actual Loading-to-value speech.
