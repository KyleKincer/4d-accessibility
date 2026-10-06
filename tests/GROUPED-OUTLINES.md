# Grouped listboxes

The 0.23.0 development adapter maps native array listbox hierarchies to the outline provider. This gate covers reading text/date groups and their disclosed leaves, and selecting a leaf from the keyboard through the list box's own events. Disclosure, reveal, editing and actual Symphony hierarchy workflows remain separate work. The stable Symphony runtime pin remains 0.22.1.

Use the ordinary parent lifecycle area and supply a hidden column with unique, nonempty text or integer row keys. Keys must remain attached to the same backing rows through every application insertion, deletion and sort. Configure the existing listbox:

```4d
$options.grids:=New object("Grouped"; New object("kind"; "outline"; "keyColumn"; "RowKey"; "label"; "Grouped items"))
```

Keep the original hierarchy arrays, form objects, handlers and visible geometry. The adapter reads them in the owning form. It does not evaluate a value Formula for a virtual group or invoke a business handler. Selecting a leaf uses the list box's own keyboard handling and events; a group row is unselectable. A one-pointer hierarchy preserves the native blank first-column leaf value; its group caption occupies the complete logical row.

Native geometry determines group membership and current disclosure. Group identity includes the parent, level, exact typed value and exact member-key set. Repeated captions can therefore have different identities. Date tokens use full year/month/day components even when the native short caption shows less information. A membership or parent change retires the affected identities. Collapsed nested groups leave the published tree; reopening requires fresh descendant references.

The accepted caption domain is deliberately narrow. Text and date arrays must match the backing row count. Hidden rows, formatted text and protected captions fail closed. Distinct values sharing one native group cannot supply an unambiguous caption. Numeric/time captions, styled caption rules, ancestor clipping, shared-array display authorities and lazy branches need their own live gates.

Complete break selection cannot be recovered from the ordinary Boolean leaf-selection array. The descriptor uses `selectionKnown: false`; selected attributes and selection actions are absent. The host still reports `groupedActionsPending`. No row disclosure setter, header press or reveal action is advertised in this slice.

Cold text pages expose their values immediately when they arrive. The native provider coalesces the accompanying layout notification for one second because fast arrival can otherwise leave a stationary VoiceOver cursor saying Loading. Pending records contain weak cells and identity tokens; replacement, retirement and eviction cancel stale notifications. A second arriving value updates the pending notification. Checkbox and popup arrivals keep their previous immediate notification behavior. The delay is an observed workaround, not a claimed Apple timing guarantee.

## Run the gate

Use matching development source and packages in an unlocked graphical session. Run every 4D compiler and graphical fixture sequentially. These commands operate disposable projects under `build/` and leave Symphony packages alone.

```sh
python3 build.py
python3 build_component.py --server '/path/to/4D Server.app'
python3 prepare_hierarchy_probe.py --server '/path/to/4D Server.app' --bridge
python3 test_grouped_outline.py --run
python3 test_grouped_outline.py --run --compiled
python3 test_grouped_outline.py --run --compiled --voiceover
python3 test_grouped_outline.py --run --native-baseline
python3 test_grouped_outline.py --run --compiled --native-baseline
python3 test_grouped_single_level.py --run
python3 test_grouped_single_level.py --run --compiled
python3 test_outline_rows.py --server '/path/to/4D Server.app'
python3 test_outline_host_helpers.py --server '/path/to/4D Server.app'
python3 test_outline_value_speech.py --run --output build/outline-value-speech-current
python3 test_grid_value_speech.py --run
python3 tests/test_grouped_outline_summary.py
uv run --with pillow==12.1.0 python summarize_grouped_outlines.py
```

The grouped driver checks one-pointer text/date and nested groups, exact levels and direct parents, immediate captions, offscreen values, omitted selection/actions, collapse/reopen retirement and native A/a partition changes. It applies format/password changes to the second hierarchy array and hides backing rows, requiring rejection, retained-handle retirement and recovery. Ten stale/incomplete binding cases preserve sampled OK, focus, selection and scrolling. Fixture commands change expansion; they are not accessibility actions.

The speech diagnostic starts each final page cold and records the Loading caption before arrival. It covers delayed onscreen/offscreen pages, fast arrival, a second update, leaving before and after arrival, and an unrelated AX inspection. It observes stationary speech and checks the next navigation position. The separate flat-grid suite retains its nine text/checkbox/popup cases.

The publisher invalidates old success before inspecting inputs. It matches canonical helpers, prepared source, compiled host artifacts, plugin, complete component package, imported test helpers and fixture binaries. It pairs each baseline image with the same native command/case in the integrated run, verifies the captured window's PID/title/bounds and requires zero changed RGBA pixels across the complete window. No masks or tolerance apply.

This gate does not accept native disclosure targeting, background-window speech, broader hierarchy families, physical Intel, client/server operation, signed distribution or Symphony workflows. Those remain requirements for the full project.
