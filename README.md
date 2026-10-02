# 4D Accessibility

Expose 4D forms through macOS accessibility so VoiceOver, accessibility tools and AI agents can read and operate them. The bridge discovers supported controls and uses their existing editors, validation and actions.

The initial release supports the controls and integration patterns listed below. Start with a named workflow and validate its whole path, including prompts, editing and save/reopen. Several control families remain unfinished, so installing the bridge does not make an entire application accessible. Read the [support status](skills/4d-accessibility/references/STATUS.md) for the tested scope and open work.

The implementation targets 4D 20.8 on macOS. Native binaries contain Apple Silicon and Intel code; live validation has primarily used Apple Silicon and macOS 26. Windows accessibility is not implemented.

## Recorded examples

Full recordings from synthetic 4D fixtures, with visible accessibility calls, VoiceOver captions and test results. Both videos are silent and play at 1.5× speed. See [recording details and reproduction steps](DEMOS.md).

### Native grids and repeated subforms

Independent subform controls, native popup editing and VoiceOver navigation to a row beyond the viewport.

https://github.com/user-attachments/assets/e2177f60-df66-4fc6-9de6-5e5c382ddec4

### AreaList editing and validation

Text commits, rejected edits, permissions and VoiceOver checkbox activation through the existing form handlers.

https://github.com/user-attachments/assets/710f9760-04cd-4838-93b3-19614d90c61b

## Start with one form

The system has three parts. The native plugin publishes the accessibility tree. The compiled component schedules work in the owning form without replacing its timer. Generated host methods read the form's controls and invoke their existing behavior.

From a release package, copy `Plugins/AccessibilityBridge.bundle` and `Components/AccessibilityBridge.4dbase` beside your application's `Project` folder. Then install the matching host methods:

```sh
python3 install_host_methods.py --project-dir /path/to/MyApp/Project
```

Add `--area-list` if the application uses AreaList Pro. Restart 4D after changing the plugin or component. Download the [release kit](https://github.com/KyleKincer/4d-accessibility/releases), or [build both packages from source](CONTRIBUTING.md). Signed releases use Sweetwater's Developer ID and Apple notarization; each release's notes define its tested scope. Older ad hoc candidates remain separately labeled.

With a matching kit that supports area integration, add the lifecycle area automatically:

```sh
python3 install_host_methods.py --project-dir /path/to/MyApp/Project --form Customer
```

Use `--all-forms` for named project and table forms, or repeat `--form` for selected forms. `--dry-run` lists proposed changes. The area draws nothing and starts after the existing initialization. Its destruction retires that window's bridge. Ordinary forms need no startup or shutdown calls in their business methods.

Complex forms return their existing provider configuration from one optional application-owned `AXB_Configure` method. The [area integration guide](skills/4d-accessibility/references/AREA-INTEGRATION.md) gives the complete installation, configuration, generated-form and migration contract. Check the [availability table](skills/4d-accessibility/references/STATUS.md#availability) for the required kit. For an unpublished version, use its matching [Build and test workflow artifact](https://github.com/KyleKincer/4d-accessibility/actions/workflows/ci.yml) or build the exact source revision. The older 0.19.7 kit retains the [manual lifecycle](skills/4d-accessibility/references/MANUAL-LIFECYCLE.md).

## More complex forms

| Your form | Integration |
| --- | --- |
| Ordinary controls, repeated or nested page subforms | Add an area to the root. Configure child labels under `children`. Invalidate a child before replacing its form or data binding. [Example](skills/4d-accessibility/references/examples/AUTOMATIC-FORM.md). |
| Array, collection or entity-selection list boxes | Add a `grids` entry with stable row identity and loading state. Existing native editors and cell controls handle supported editing. [Native grids](skills/4d-accessibility/references/GRIDS.md#add-a-native-array-list-box-without-replacing-discovery). |
| AreaList Pro grids | Add stable row keys, record scope, loading readiness and descriptions for custom columns. Configure repeated grids within their owning child. [AreaList grids](skills/4d-accessibility/references/AREALIST-GRIDS.md). |
| JSON-generated forms | Add `AXB_AreaForm` at the shared builder; the original method, events and data stay in place. [Generated forms](skills/4d-accessibility/references/examples/DYNAMIC-FORM.md). |
| Existing application alert and confirmation forms | Add the area and labels. Route inaccessible built-in prompts through the application's existing dialog methods when their appearance is acceptable. Preserve returned choices and validation. [Message dialogs](skills/4d-accessibility/references/MESSAGES.md). |
| Custom controls or existing native/web content | Preserve a usable native provider. Use the explicit provider contract for application-specific controls; account for every interactive element. [Extension contract](skills/4d-accessibility/references/FORM-SUPPORT.md). |

For a form combining ordinary fields, editable grids and subforms, follow the [assembled record-editor example](skills/4d-accessibility/references/examples/RECORD-EDITOR.md).

The modern grid adapters expose logical rows beyond the viewport and reveal them for supported actions. The older explicit row-summary adapters are retained for compatibility and expose only a subset. They are not the default for new integrations.

## Stable automation identifiers

The 0.21.0 source adds readable paths such as `axb/Customers/SearchFld`. Reopening repeats the locator while retiring the old element handle. Existing object names supply the defaults; an optional `automationKey` gives a logical screen name. Find controls within the selected live window. See [identifier examples and upgrade rules](skills/4d-accessibility/references/IDENTIFIERS.md).

## Integrate with an agent

The repository includes the [4d-accessibility skill](skills/4d-accessibility/SKILL.md). Copy the entire `skills/4d-accessibility` folder to your agent's skill directory, such as `.agents/skills/4d-accessibility` for project-scoped discovery or `~/.claude/skills/4d-accessibility` for Claude Code. Its references are self-contained. Keep a matching source checkout or release package available for the installer and binaries.

Ask the agent to use the skill to integrate a named form. It should inspect the existing form lifecycle, choose the smallest adapter configuration, preserve business behavior and report live validation and unresolved coverage separately.

## Development

[Build and test](CONTRIBUTING.md) · [Integration reference](skills/4d-accessibility/references/INTEGRATION.md) · [Release process](RELEASING.md) · [Accessibility requirements](skills/4d-accessibility/references/REQUIREMENTS.md)

MIT licensed. The vendored 4D Plugin SDK has its own [MIT notice](vendor/4DPluginAPI/LICENSE.md). 4D and AreaList Pro are separate products; their applications, plugins and licenses are not included.
