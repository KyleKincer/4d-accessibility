# 0.25.0 development, standard messages and VoiceOver corrections

Standard 4D `ALERT`, `CONFIRM` and `Request` windows are accessible with only the native plugin installed. The plugin publishes the message, the Request field and named buttons from the text 4D draws, and presses with an ordinary click. Input is held until a window has been published for half a second, because 4D discards input that arrives before its modal loop starts. `OK` and answers are unchanged, and VoiceOver echoes typing. No host method or component change is needed. Every window is pixel-identical to the plugin-free window. [The acceptance record](validation/native-messages-provider.json) passes 264 checks: interpreted and compiled, native ARM and Rosetta, with and without VoiceOver. Client/server, Request caret movement and other built-in windows remain open.

A host mode change that makes the focused field editable now keeps VoiceOver on that field. The layout change that replaces the field names the newly focused element and precedes the focus change. An owned AppKit fixture announces the editable field in every trial. [Evidence](validation/focus-replacement-speech.json).

Applications can declare `omitOutsideWindow` for a form in a fixed window. Top-level controls parked wholly outside the window then leave the tree; partly visible, focused and subform controls remain. [Evidence](validation/parked-controls.json). An input with 4D's default **Automatic** Multiline setting can be declared with `controls.<name>.multiline` when 4D treats it as multi-line. Accessibility text entry, including whole-value writes, then accepts line breaks.

Polling a large form is about four times cheaper. The form tree is rebuilt after a pending step only when a receipt must be published, and each view copies its clip rectangle instead of sharing it. [Evidence](validation/description-performance.json).

Upgrade the plugin, component and host helpers together. The new snapshot options need matching helpers; the standard message windows need only the plugin. This is a development build; signed distribution is separate.

# 0.24.0 development, application-controlled grouped disclosure

Text/date array hierarchies can use a stable `setExpanded` Formula to collapse or expand a semantic group through the application's targeted native command. The bridge supplies fresh backing-row and break-level coordinates, calls the controller once, and confirms the resulting group and native editor state before reporting completion. Idempotent requests do not call the controller. Scope, membership, readiness, generation and controller changes reject stale authority.

Rows and their disclosure triangles support VoiceOver activation. A receipt-backed English announcement reports the confirmed caption and expanded/collapsed state when stationary value notifications do not speak it. Capability removal permanently retires old triangle handles. Disclosure skips ancestor reveal, preserving scrolling in repeated nested forms and pending text in an unrelated resolved editor.

[The acceptance record](validation/grouped-disclosure-development.json) passes 904 live 4D checks, 37 whole-window comparisons with zero changed RGBA pixels, 37 pure host checks and nine fresh flat-grid speech cases with 135 checks. Read [configuration and gate reproduction](tests/GROUPED-DISCLOSURE.md). Complete break selection, reveal, editing, classic trees and actual Symphony hierarchy workflows remain pending. Upgrade the plugin, component and helpers together; this is a development build, with signed distribution separate.

# 0.23.0 development, read-only grouped arrays

Array listbox hierarchies can expose their text/date groups and disclosed leaves through the parent lifecycle area. Configure `kind: outline` and an existing hidden column of stable row keys. The adapter preserves native arrays, visible layout, handlers and selection. Group identity includes the exact typed caption value, parent and member keys. Changed membership retires old handles.

Selection state is unknown and omitted. Disclosure, selection, reveal, editing and header actions remain unavailable. Caption formats, protected captions and hidden rows fail closed. Classic trees and actual Symphony hierarchy workflows remain separate work.

Cold text values update AX immediately and coalesce a layout notification for one second so stationary VoiceOver can read fast arrivals. Weak references and identity checks discard stale notifications. Checkbox and popup arrivals retain their previous behavior.

The [development gate](validation/grouped-outlines-development.json) records both 4D modes, compiled VoiceOver, 26 zero-difference full-window comparisons and supporting outline/flat speech regressions. See [configuration, reproduction and limits](tests/GROUPED-OUTLINES.md). Upgrade plugin, component and helpers together; signed distribution remains pending.

# 0.22.0 classic list subforms, source and CI kit

A parent lifecycle area can now discover classic list subforms and expose every logical record as an accessible table. Named project and table input parents use the same installer. The repeated row form needs no new accessibility area, row method or field hook. Native layout, editors, key filters, selection and save handlers retain control of application behavior.

The installer also generates `Resources/AXB.FormMetadata.json` beside `Project`. Commit and ship this resource, and regenerate it after form-definition changes. Updating an existing area integration can add it with `--form-metadata`, keeping the application's existing installer options. Until that resource is present, an existing list subform appears as a disabled table with `listSubformDefinitionRequired`, replacing the earlier one-row child description. See [installation, configuration and limits](skills/4d-accessibility/references/LIST-SUBFORMS.md).

Stored scalar fields and a stored primary key provide automatic columns and row identity. A table without a declared primary key can use an existing unique text or integer field through central `keyProperty` configuration. Inspection uses a private read-only process and preserves the current record buffer and selection. Actions use verified native clicks and editors; they never assign or save fields directly. Unsupported row controls remain explicit diagnostics.

Confirmed grid-checkbox feedback now survives a follow-up reveal of the same cell while its changed value loads. Rejected requests, retired controls and unrelated actions still cancel success feedback. This uses the shared provider and adds no application hooks.

The [current acceptance gate](skills/4d-accessibility/references/STATUS.md#classic-list-subforms-in-0220) records scoped acceptance and unresolved layouts. Upgrade the plugin, component, helpers and generated resource together. The adapter requires native `listSubforms 1`. Signed distribution remains subject to the exact-download gate; source and ad hoc CI artifacts are identified separately.

# 0.21.1 compound-form focus

Generated nonblocking forms can have identically named parent/child editors. Version 0.21.1 fixes initial focus, intentional restart and child replacement through the existing form observer. Native editors, business handlers, timers and layout retain their behavior.

Most forms still need only the lifecycle area. Add a focus observer only when testing shows wrong or ambiguous editor focus, then complete the affected descendant branch. A parent-only call can make a same-named parent editor ambiguous. Unique native pointers continue to work without child observers. See the [decision and integration recipe](skills/4d-accessibility/references/INTEGRATION.md#repeated-controls-with-ambiguous-focus).

Upgrade the plugin, component and helpers together. [Candidate acceptance](validation/compound-form-focus-0.21.1.json) records the exercised layouts; hierarchy, classic list subforms and advanced embedded editors remain follow-up work. CI kits are development builds. Signed distribution follows acceptance of the exact signed download.

# 0.21.0

This release combines area-owned form integration with stable automation identifiers and broader native-control support. Install the native plugin, compiled component and host helpers from the same versioned macOS kit. The release workflow signs the packages as Sweetwater and notarizes the ZIP and DMG. Publication requires live checks of those exact downloads.

## What changes

- Ordinary forms need one invisible lifecycle area. The installer preserves existing objects and methods; generated forms use a prepared copy. One optional central configuration supplies application knowledge such as row identity and loading readiness.
- Public identifiers now use readable paths such as `axb/CustomerSearch/SearchFld`. They repeat across form openings. Internal session UUIDs still reject actions against closed forms. Find the selected live window first and reacquire its elements; identifiers are not globally unique handles. Optional screen, control and column keys let an application preserve locators through renames.
- Native tabs, ordinary styled fields and flat classic current/named-selection grids use their existing UI, editors, validation and business handlers. Static tabs with repeated reference values receive distinct choice identifiers. Styled edits preserve formatting. Classic grids read through a private entity selection without changing the form's current record buffer.
- A changed column alias retires cached grid cells even if no column header was previously inspected. Public locator changes cannot leave an old cell usable.

## Validation and scope

Local candidate acceptance includes 628 tab checks, 164 classic-selection checks, 388 existing native-grid action checks, 116 styled-field checks and 121 AreaList checks. Four whole-window comparisons are pixel-identical. The native provider passes 276 checks. [Candidate evidence](validation/stable-identifiers-0.21.0.json) records actual run hashes and distinguishes the earlier tab matrix from final native corrections. Signed-download evidence is attached to the release after its acceptance gate passes.

The tested host is 4D 20.8 on macOS 26.7, with native Apple Silicon fixtures. The plugin and component contain both ARM and Intel code; this does not establish Intel hardware, Windows accessibility or remote-client delivery. Support is defined by the [family checklist](skills/4d-accessibility/references/FULL-FORMS.md). Hierarchical grids, list subforms and advanced embedded/custom editors remain separate work. AreaList supplementary-Unicode editing retains its documented vendor restriction.

See [installation and migration](skills/4d-accessibility/references/AREA-INTEGRATION.md), [stable identifier rules](skills/4d-accessibility/references/IDENTIFIERS.md) and [the integration skill](skills/4d-accessibility/SKILL.md). Earlier recordings demonstrate the workflows, but are not acceptance evidence for this version.

# 0.20.0 integration history

The new integration path adds an invisible, non-focusable plug-in area to each form. The area starts the existing accessibility adapters after ordinary initialization and releases its captured session when the form closes. Most ordinary forms need no bridge code in their form method. One optional `AXB_Configure` method supplies names, grid providers and other application-specific metadata.

The installer adds the area to page zero, resolves shared named bases, reports affected descendants, and protects existing methods and conflicting areas before writing anything. Generated forms use `AXB_AreaForm`, which returns a prepared copy without wrapping application events or changing form data. Root registration supports plain data, entities, class instances and shared objects. Existing manual lifecycle APIs remain available for integrations that need them.

This branch also fixes duplicate-named root/child text selection and ordinary button dispatch into nested modal loops. Actions still use native editors and existing handlers. An AX receipt acknowledges dispatch; the application must confirm its business result.

Database close/reopen now reinitializes the native bridge through 4D's plugin callbacks. Sessions from the closed database remain retired; newly opened forms get fresh identities. The regression fixture exercises the complete controls workflow after a real reopen in interpreted and compiled mode.

Version 0.20.0 introduced this integration path on main. Version 0.21.0 includes it in the matching release kit. The native plugin, component and helpers must be installed together. See [area integration](skills/4d-accessibility/references/AREA-INTEGRATION.md) for setup and migration. The supported control families and vendor restrictions are unchanged.

# 0.19.7 published release

4D Accessibility 0.19.7 is the initial release for integrating supported 4D forms with macOS accessibility. The plugin, compiled component, host helpers and agent skill ship together under the MIT license. Download the versioned macOS kit; the smaller `4d-accessibility.zip` contains only the component.

The ZIP and DMG are Developer ID signed by Sweetwater and notarized by Apple. The DMG includes a stapled notarization ticket. Check `SHA256SUMS` before installation. Install both runtime packages and the matching host helpers, then restart 4D.

## Included behavior

- Ordinary fields, buttons, choices, dropdowns and supported adjustable controls expose names, values and actions through the standard accessibility tree.
- Native array, collection and entity-selection grids and AreaList Pro expose logical rows beyond the viewport. Supported editors preserve application validation, Undo/Redo and existing handlers. Stable keys and record scopes reject stale requests.
- Repeated and nested page subforms and JSON-generated forms use the same lifecycle, with documented ownership and replacement rules.
- Existing application alert and confirmation forms can use the ordinary-form adapter. Applications can route inaccessible built-in prompts through those forms without designing another dialog system.

This release includes the validated helper corrections made after 0.19.5: complete timed-search input, calculated AreaList values, complete editor commits during cell transitions, legacy Boolean hidden-row arrays, overlapping button layers and bounded confirmation after slow selection callbacks. They require no new application hooks beyond the documented configuration. The native VoiceOver distant-checkbox speech correction from 0.19.5 is retained.

## Scope and limits

The target is 4D 20.8 on macOS. The plugin contains Apple Silicon and Intel code; live checks cover native Apple Silicon fixtures and interpreted/compiled application workflows under Rosetta. This does not establish Intel hardware or Windows accessibility support. Client/server delivery has a separate validation gate.

This release is ready to prove out the documented form families in an application. It does not make every existing form accessible automatically. Tabs, hierarchy, classic table-backed subforms and advanced custom/vendor editors still need implementation or validation. Voice Control and Switch Control are unvalidated. Read the [support status](https://github.com/KyleKincer/4d-accessibility/blob/main/skills/4d-accessibility/references/STATUS.md) before choosing a workflow.

Standard 4D `CONFIRM` and `ALERT` remain inaccessible on the tested installation without an application-owned dialog path. AreaList supplementary-Unicode editing remains blocked before mutation because of a reproduced vendor defect. Ordinary 4D text editors are unaffected. Both limitations have small standalone reproductions in the repository.

The exact signed 0.19.7 download passes 39 compiled VoiceOver checks and 127 interpreted action checks in native ARM 4D 20.8 on macOS 26.7. Manifest checks, matching helpers, code signatures, the stapled ticket and Gatekeeper acceptance also pass. [Asset hashes and checks](https://github.com/KyleKincer/4d-accessibility/blob/main/validation/signed-release-0.19.7.json).

[Watch the recorded examples](https://github.com/KyleKincer/4d-accessibility/blob/main/DEMOS.md) for native grids and AreaList, with visible AX calls, VoiceOver captions and completion assertions. The videos use the signed 0.19.6 draft; this release preserves the same provider and helper behavior. `DEMO-SHA256SUMS` covers the videos separately from the installation kit. Signing establishes provenance; the recorded live checks establish the supported behavior.
