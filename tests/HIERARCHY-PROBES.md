# Native hierarchy investigation

These synthetic probes establish native command and input behavior before adding a hierarchy adapter. They do not establish bridge navigation, VoiceOver, editing or a Symphony hierarchy workflow. The bridge still reports hierarchical controls as unsupported.

Run compiler and desktop cases sequentially on an unlocked Mac with a licensed 4D Server and desktop installation. The desktop launcher currently uses `/Applications/4D/4D.app`. Read each script's `--help` before running it.

```sh
python3 prepare_hierarchy_probe.py --server /path/to/4D\ Server.app
python3 test_hierarchy_probe.py --run --commands
python3 test_hierarchy_probe.py --run --commands --compiled
```

Preparation copies the probe methods and compiles both ARM and Intel targets. Each desktop run verifies source hashes, its actual execution mode and ordinary close. The fixture contains two representations of one classic list and a grouped array listbox. Negative references, a blank leaf, an empty branch, latent descendants and distant rows remain synthetic data.

The read checks compare both representations before and after inspection, including selection, scrolling and focus, and verify `OK` preservation. Expansion and selection belong to each representation; latent topology alone cannot describe their displayed state. The result of `Selected list items` with the final `*` is a reference, so the report calls it `currentSelectedReference`.

The input probe compares process-targeted `POST KEY` with external native tree arrows. It requires the same resulting rows, selection and original handler sequence while the other representation remains unchanged. Programmatic selection and collapse calls only prepare these synthetic baselines. They are not proposed bridge action implementations. Native grouped disclosure clicks verify the owning process at the actual screen point and require the intended break callback once, plus a positive descendant rectangle after expansion and a nonpositive rectangle after collapse. Their inset is a fixture-specific test point, not automatically discovered disclosure geometry.

## Inspect native views and drawing

The optional observer copies committed production source into an ignored directory, adds public AppKit diagnostics and builds separate binaries. It never changes production source or installs into Symphony.

```sh
python3 prepare_hierarchy_observer.py
python3 prepare_hierarchy_probe.py --server /path/to/4D\ Server.app \
  --diagnostic-plugin build/hierarchy-observer/build/AccessibilityBridge.bundle
python3 test_hierarchy_probe.py --run --commands
python3 test_hierarchy_probe.py --run --commands --compiled
```

The observer inventories the content view's highest ancestor in the same verified window, then its descendants. It classifies public AppKit types without recognizing private 4D classes. Public `NSCell`, `NSBrowserCell` and `NSTextFieldCell` drawing wrappers call the original implementations unchanged. Samples retain weak views, raw frames, graphics transforms, phase and text, with bounded storage and explicit counters. Main-thread reads record whether a view survives and belongs to the queried window. A raw drawing frame without verified ownership is not a control rectangle.

The executed [October 3 record](../validation/native-hierarchy-probes-0.22.1.json) covers eight checks in each desktop mode and uniquely mapped diagnostic binaries. The wider inventory contains no usable `NSOutlineView`. The captured cell samples have blank text and no matching window, so they do not supply tree-row geometry. Earlier inventory reports lacked the current sample fields and cannot prove that these hooks captured zero paints.

## Adapter prerequisites

Use the existing logical-grid/provider seam for an outline extension, with distinct host adapters for classic lists and grouped array listboxes. Publish currently disclosed logical rows, including offscreen rows, with stable identity, parent/disclosure relationships and real operation capabilities. Keep collapsed descendants in the internal topology.

Classic lists still need exact row, text and disclosure geometry. [`GET LIST PROPERTIES`](https://developer.4d.com/docs/commands/get-list-properties) returns a minimum line height. It does not justify multiplying a row position by that value. [The hierarchical-list model](https://developer.4d.com/docs/20/FormObjects/listOverview) permits duplicate item references and separates representation state from shared data. Unique references require verification before they can become stable row keys.

Grouped listboxes have public cell rectangles, but their addressing includes break columns. Collapsed descendants return nonpositive rectangles whose midpoint can address a different row. Reject those rectangles before any point round trip. Further probes must establish break identity, selection/focus state, hidden rows, repeated groups, horizontal scrolling and clipping. [4D's hierarchy documentation](https://developer.4d.com/docs/20/FormObjects/listboxOverview) and [cell-coordinate contract](https://developer.4d.com/docs/commands/listbox-get-cell-coordinates) explain the distinction.

[`POST KEY`](https://developer.4d.com/docs/commands/post-key) supplies a viable tested route for an already focused synthetic tree. It does not solve targeting another row, native geometry, editing, lazy loading or action races. A production adapter must verify identity before input, reread after callbacks and retire stale references after replacement. Do not invoke business handlers manually or stage a programmatic selection as a replacement for native selection.
