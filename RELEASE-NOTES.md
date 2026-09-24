This is a development preview of 4D Accessibility for macOS and 4D 20.8.

Download the versioned macOS integration kit for the plugin, component, host-method installer, documentation and agent skill. `4d-accessibility.zip` is the component-only archive for 4D Dependency Manager; the plugin and host methods are still required.

Read the included `skills/4d-accessibility/references/STATUS.md` before integrating. Full-UI accessibility remains under development, with known gaps in control families, native header state and assistive-technology behavior. A signed release establishes download provenance, not complete application accessibility.

Active grid-editor actions now survive a delayed backing-cell cache update after Undo/Redo, while changed editor contents and permissions still reject. AreaList supplementary Unicode remains blocked by a reproduced vendor conversion defect. The repository includes a one-cell reproduction without the bridge.

Generated forms opened with mismatched shared, entity or class-instance data now preserve application events without adding bridge properties. The installer rejects duplicate compiler-declaration targets. The integration guide separates ordinary forms from grids and uses the application's existing error reporter.

AreaList Boolean and Integer/LongInt checkbox columns now use their existing vendor editors and callbacks. Non-focusable controls expose activation without an unsafe focus operation; focusable controls expose uncommitted values and preserve normal commit/cancel. The grid configuration needs no additional application callbacks. Refresh the plugin and generated helpers together for the new `cellFocus 1` startup check.
