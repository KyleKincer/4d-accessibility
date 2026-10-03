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
