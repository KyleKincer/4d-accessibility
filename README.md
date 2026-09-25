# 4D Accessibility

Expose 4D forms through macOS accessibility so VoiceOver, accessibility tools and AI agents can read and operate them. The bridge discovers supported controls and uses their existing editors, validation and actions.

**Development preview.** The target is the entire application UI. Several control families and assistive-technology behaviors are still unfinished. Read the [support status](skills/4d-accessibility/references/STATUS.md) before adopting it. There is no stable production release yet. The previously failing distant-checkbox speech case passes in the [signed 0.19.5 candidate](validation/signed-release-0.19.5.json).

The implementation targets 4D 20.8 on macOS. Native binaries contain Apple Silicon and Intel code; live validation has primarily used Apple Silicon and macOS 26. Windows accessibility is not implemented.

## Start with one form

The system has three parts. The native plugin publishes the accessibility tree. The compiled component schedules work in the owning form without replacing its timer. Generated host methods read the form's controls and invoke their existing behavior.

From a release package, copy `Plugins/AccessibilityBridge.bundle` and `Components/AccessibilityBridge.4dbase` beside your application's `Project` folder. Then install the matching host methods:

```sh
python3 install_host_methods.py --project-dir /path/to/MyApp/Project
```

Add `--area-list` if the application uses AreaList Pro. Restart 4D after changing the plugin or component. Download an available [release candidate](https://github.com/KyleKincer/4d-accessibility/releases), or [build both packages from source](CONTRIBUTING.md). Candidates are ad hoc signed and not notarized; their notes define the tested scope.

At the end of an ordinary form's successful On Load initialization:

```4d
var $bridge : Object
$bridge:=AXB_Form("start"; New object("label"; "Customer details"))
If (Not($bridge.ok=True) & ($bridge.error#"dependencyUnavailable"))
 Form.axbError:=$bridge.error
End if
```

In On Unload and the form's existing fatal-error cleanup:

```4d
var $bridge : Object
$bridge:=AXB_Form("stop"; New object)
```

Enable those form events if needed. Existing buttons, fields, object methods and timers stay in place. Add missing labels through configuration, then inspect the [coverage report](skills/4d-accessibility/references/INTEGRATION.md#check-the-forms-coverage) and test the live form. A successful start does not establish complete accessibility.

## More complex forms

| Your form | Integration |
| --- | --- |
| Ordinary controls, repeated or nested page subforms | Start/stop the root. Configure child labels under `children`. Invalidate a child before replacing its form or data binding. [Example](skills/4d-accessibility/references/examples/AUTOMATIC-FORM.md). |
| Array, collection or entity-selection list boxes | Add a `grids` entry with stable row identity and loading state. Existing native editors and cell controls handle supported editing. [Native grids](skills/4d-accessibility/references/GRIDS.md#add-a-native-array-list-box-without-replacing-discovery). |
| Invoice-style form with AreaList Pro | Add its area reference, stable line keys, record scope, readiness and meaningful descriptions for custom columns. Configure repeated grids within their owning child. [Assembled example](skills/4d-accessibility/references/GRIDS.md#put-the-invoice-like-form-together). |
| JSON-generated forms | Wrap the shared builder with `AXB_Dynamic`, preserving the original method and events. Use private form data and explicit cleanup before child replacement. [Generated forms](skills/4d-accessibility/references/examples/DYNAMIC-FORM.md). |
| Custom controls or existing native/web content | Preserve a usable native provider. Use the explicit provider contract for application-specific controls; account for every interactive element. [Extension contract](skills/4d-accessibility/references/FORM-SUPPORT.md). |

The modern grid adapters expose logical rows beyond the viewport and reveal them for supported actions. The older explicit row-summary adapters are retained for compatibility and expose only a subset. They are not the default for new integrations.

## Integrate with an agent

The repository includes the [4d-accessibility skill](skills/4d-accessibility/SKILL.md). Copy the entire `skills/4d-accessibility` folder to your agent's skill directory, such as `.agents/skills/4d-accessibility` for project-scoped discovery or `~/.claude/skills/4d-accessibility` for Claude Code. Its references are self-contained. Keep a matching source checkout or release package available for the installer and binaries.

Ask the agent to use the skill to integrate a named form. It should inspect the existing form lifecycle, choose the smallest adapter configuration, preserve business behavior and report live validation and unresolved coverage separately.

## Development

[Build and test](CONTRIBUTING.md) · [Integration reference](skills/4d-accessibility/references/INTEGRATION.md) · [Release process](RELEASING.md) · [Accessibility requirements](skills/4d-accessibility/references/REQUIREMENTS.md)

MIT licensed. The vendored 4D Plugin SDK has its own [MIT notice](vendor/4DPluginAPI/LICENSE.md). 4D and AreaList Pro are separate products; their applications, plugins and licenses are not included.
