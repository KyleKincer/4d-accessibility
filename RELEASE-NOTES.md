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
