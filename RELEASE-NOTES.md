This is a development release candidate of 4D Accessibility for macOS and 4D 20.8. The downloads are ad hoc signed and not notarized. The 4D plugin ID remains provisional. Use this candidate for local integration and evaluation; it is not a production distribution.

Selecting an already visible native grid row now confirms without an unnecessary scroll-and-wait cycle. That extra cycle could report a timeout despite the correct selection in a form with expensive callbacks. The regression fails before the fix and passes in interpreted and compiled 4D. No host call or timeout increase is needed.

VoiceOver now reads grid values when they arrive after Loading, including checkbox and popup cells. The native provider preserves the reading position and requires no additional host application code. Eight live VoiceOver cases cover delayed values, navigation, leaving the grid, unrelated AX reads and reloading unchanged data. The compiled 4D regression also verifies the formerly stuck distant checkbox after native popup interaction.

Large forms now leave time for input and VoiceOver between accessibility refreshes. Grid-page reads validate their current grid and containing form without rescanning unrelated ordinary controls. Background pages use normal polling; pending editor operations keep their fast path. The component adapts its idle interval to callback cost. Existing application hooks and form timers stay the same.

Untitled buttons, checkboxes, radio buttons and popups reuse their current 4D help tips as accessible names. Displayed captions and explicit labels take precedence. Empty static captions appear in the tree when the application fills them, avoiding nameless stops for empty placeholders. These defaults reduce application metadata; review the resulting names because a help tip can describe temporary state instead of the control's action.

Button activation now acknowledges dispatch before the existing handler changes record scope. A successful navigation no longer produces a false rejection solely because its old accessibility route retired. The receipt confirms dispatch; callers must still verify the application's result. Stale requests and state-changing checkbox/radio actions retain their checks.

Download the versioned macOS integration kit for the plugin, component, host-method installer, documentation and agent skill. `4d-accessibility.zip` is the component-only archive for 4D Dependency Manager; the plugin and host methods are still required.

Read the included `skills/4d-accessibility/references/STATUS.md` before integrating. Full-UI accessibility remains under development, with known gaps in control families, native header state and assistive-technology behavior. A signed release establishes download provenance, not complete application accessibility.

Active grid-editor actions now survive a delayed backing-cell cache update after Undo/Redo, while changed editor contents and permissions still reject. AreaList supplementary Unicode remains blocked by a reproduced vendor conversion defect. The repository includes a one-cell reproduction without the bridge.

Generated forms opened with mismatched shared, entity or class-instance data now preserve application events without adding bridge properties. The installer rejects duplicate compiler-declaration targets. The integration guide separates ordinary forms from grids and uses the application's existing error reporter.

AreaList Boolean and Integer/LongInt checkbox columns now use their existing vendor editors and callbacks. Non-focusable controls expose activation without an unsafe focus operation; focusable controls expose uncommitted values and preserve normal commit/cancel. The grid configuration needs no additional application callbacks. Refresh the plugin and generated helpers together for the new `cellFocus 1` startup check.
