# Native hierarchy investigation

These synthetic probes establish native command and input behavior before adding hierarchy actions. They do not establish bridge navigation, VoiceOver, editing or a Symphony hierarchy workflow. The separate [0.23.0 grouped adapter](GROUPED-OUTLINES.md) has read-only text/date acceptance; interactive hierarchy and classic trees remain incomplete.

Run compiler and desktop cases sequentially on an unlocked Mac with a licensed 4D Server and desktop installation. The desktop launcher currently uses `/Applications/4D/4D.app`. Read each script's `--help` before running it.

```sh
python3 prepare_hierarchy_probe.py --server /path/to/4D\ Server.app
python3 test_hierarchy_probe.py --run --commands
python3 test_hierarchy_probe.py --run --commands --compiled
```

Preparation copies the probe methods and compiles both ARM and Intel targets. Each desktop run verifies source hashes, its actual execution mode and ordinary close. The fixture contains two representations of one classic list and a grouped array listbox. Negative references, a blank leaf, an empty branch, latent descendants and distant rows remain synthetic data.

The read checks compare both representations before and after inspection, including selection, scrolling and focus, and verify `OK` preservation. Expansion and selection belong to each representation; latent topology alone cannot describe their displayed state. The result of `Selected list items` with the final `*` is a reference, so the report calls it `currentSelectedReference`.

The input probe compares process-targeted `POST KEY` with external native tree arrows. It requires the same resulting rows, selection and original handler sequence while the other representation remains unchanged. Programmatic selection and collapse calls only prepare these synthetic baselines. They are not proposed bridge action implementations. Native grouped disclosure clicks verify the owning process at the actual screen point and require the intended break callback once, plus a positive descendant rectangle after expansion and a nonpositive rectangle after collapse. Their inset is a fixture-specific test point, not automatically discovered disclosure geometry.

## Observe grouped state

The optional grouped cases require Pillow 12.1 or later. Use a Python environment with that dependency, after preparing the fixture as above:

```sh
python3 -m venv build/hierarchy-venv
build/hierarchy-venv/bin/pip install 'Pillow>=12.1'
build/hierarchy-venv/bin/python test_hierarchy_probe.py --run --commands --grouped-states
build/hierarchy-venv/bin/python test_hierarchy_probe.py --run --commands --grouped-states --compiled
build/hierarchy-venv/bin/python summarize_grouped_probe.py
```

The [grouped-state record](../validation/grouped-hierarchy-state-0.22.1.json) covers thirteen checks in each mode, including the earlier eight native checks, and seven cleanup regressions. Source and image hashes match. Two separate publisher regressions reject deleted or renamed canonical methods and invalidate an older passing record before rejecting. These regressions run in CI without Pillow or a desktop session. Independent sentinels verify sampled Boolean selection fields, focus, scrolling and `OK` around the full reader. Synthetic cases include noncontiguous repeated group labels, hidden descendants, blank backing data and an empty list. They do not establish loaded-empty or unloaded lazy branches.

With all four root breaks visible, clearing selection, selecting the first `A` break and selecting the later `A` break produce identical sampled public readbacks. The native images differ only in the intended break-row rectangles: 11,672 pixels for each baseline-to-selected comparison and 23,344 between the two selections. Reset returns to the baseline with zero changed pixels. Each capture matches the selected AX window by owning PID, title and bounds. Focus, scroll and window bounds remain fixed; the sampled selection fields do not change. This leaves complete break-selection reporting unresolved; it does not prove that every public API lacks that information. An expanded break/leaf command-sequence comparison has a separate caveat in the record: retained break highlight after expansion was not independently verified.

Opposite nested-child expansion states also produce identical sampled readbacks while their parent is collapsed. Reopening the parent confirms the child stayed collapsed in one case and expanded in the other. An adapter can retain that latent state as unknown, exclude undisclosed descendants from AX rows, then reread their state when the ancestor opens. Unknown selection or disclosure must not become false, collapsed or leaf. A last-event cache would miss programmatic changes and is not authoritative application state.

The record contains no hierarchy adapter, VoiceOver or Symphony hierarchy workflow acceptance. It records the Python host architecture; the 4D process architecture was not independently sampled. Sorting, stable break identity, arbitrary native targets, clipping, lazy loading and action races remain separate prerequisites.

## Target visible later and nested breaks

After preparing the fixture, run these cases separately from `--grouped-states`. They need no Pillow dependency:

```sh
python3 test_hierarchy_probe.py --run --commands --grouped-inputs
python3 test_hierarchy_probe.py --run --commands --grouped-inputs --compiled
python3 summarize_grouped_inputs.py
```

The [visible native-input record](../validation/grouped-native-inputs-0.22.1.json) covers twelve checks per mode, including the earlier eight native checks. Center clicks select the later `A` break or its nested child. A refreshed public cell address, screen frame, focused window and point owner guard mouse-down. Each click runs one original click handler without disclosure. Right/Left then run one original expansion/collapse handler and change both intended descendants, while retaining the ancestor frame. Other sampled roots stay collapsed; both classic trees and backing data remain unchanged.

Mouse-up runs in `finally`, including an exception during mouse-down. Separate report/image names preserve the grouped-state gate. Two flag regressions reject invalid combinations before input or evidence changes. Both publishers share source-set validation, and four CI fault regressions reject deleted or renamed canonical methods while invalidating old success. Seven cleanup regressions remain separate from the native counts.

This establishes visible fixture targeting followed by native keyboard disclosure. Center clicking changes selection; selection-preserving disclosure remains unvalidated. Complete selection, arbitrary targets, offscreen reveal, clipping, lazy loading, action races and retained latent states still need work. Keyboard event row/column fields are not treated as authoritative target addresses. There is no hierarchy adapter or VoiceOver/Symphony hierarchy acceptance.

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

The earlier [October 3 record](../validation/native-hierarchy-probes-0.22.1.json) covers eight checks in each desktop mode and uniquely mapped diagnostic binaries. The wider inventory contains no usable `NSOutlineView`. The captured cell samples have blank text and no matching window, so they do not supply tree-row geometry. Earlier inventory reports lacked the current sample fields and cannot prove that these hooks captured zero paints.

The [follow-up drawing observation](../validation/hierarchy-public-drawing-observation.json) adds `NSButtonCell` draw, interior and bezel hooks. It records the supplied view's window and converted bounds during each call, plus separate control-view and focus-view associations, drawing destination, bezel style and state. Both modes pass the twelve native-input checks and clean shutdown. Each final snapshot contains 468 disclosure-style samples, but none has a matching draw-time window, current owning window, control view or focus view. Other button paints do retain the owned window. This bounded experiment found no public drawing authority for disclosure targets in the tested runtime. It does not turn raw paint frames into input coordinates.

## Adapter prerequisites

Use the existing logical-grid/provider seam for an outline extension, with distinct host adapters for classic lists and grouped array listboxes. Publish currently disclosed logical rows, including offscreen rows, with stable identity, parent/disclosure relationships and real operation capabilities. Keep collapsed descendants in the internal topology.

Classic lists still need exact row, text and disclosure geometry. [`GET LIST PROPERTIES`](https://developer.4d.com/docs/commands/get-list-properties) returns a minimum line height. It does not justify multiplying a row position by that value. [The hierarchical-list model](https://developer.4d.com/docs/20/FormObjects/listOverview) permits duplicate item references and separates representation state from shared data. Unique references require verification before they can become stable row keys.

Grouped listboxes have public cell rectangles, but their addressing includes break columns. Collapsed descendants return nonpositive rectangles whose midpoint can address a different row. Reject those rectangles before any point round trip. Positive theoretical rectangles may still be clipped or outside the viewport. The grouped cases above establish observed hidden/repeated-group states and expose selection and latent-disclosure gaps. Stable break identity, complete selection/focus state, horizontal scrolling and clipping remain open. [4D's hierarchy documentation](https://developer.4d.com/docs/20/FormObjects/listboxOverview) and [cell-coordinate contract](https://developer.4d.com/docs/commands/listbox-get-cell-coordinates) explain the distinction.

[`POST KEY`](https://developer.4d.com/docs/commands/post-key) supplies a viable tested route for an already focused synthetic tree. It does not solve targeting another row, native geometry, editing, lazy loading or action races. A production adapter must verify identity before input, reread after callbacks and retire stale references after replacement. Do not invoke business handlers manually or stage a programmatic selection as a replacement for native selection.
