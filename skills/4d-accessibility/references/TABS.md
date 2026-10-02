# Tab controls

Tabs need no extra application hooks. Use a kit with tab support from [the availability table](STATUS.md#availability), install its matching plugin, component and helpers, then add the lifecycle area as described in [area integration](AREA-INTEGRATION.md). The installer includes the tab adapter and its compiler declarations automatically.

Keep the form's existing object method, standard action and initialization. For example, a tab control using `Form.sections` and `gotoPage` retains its existing code:

```4d
// Existing initialization; the bridge reads it as-is.
Form.sections:=New object("values"; New collection("Details"; "History"); "index"; 0)
```

4D owns the selected index and page change. An accessibility press delivers a native click to that choice, preserving the existing handler and standard action.

A custom `describe` replaces automatic discovery, and a custom `apply` replaces automatic action routing, for that form's tabs too. Leave both unset so the shared adapter handles tabs.

Supported sources are Text arrays, objects whose `values` is a Text collection and whose `index` selects a value, and choice lists. Only a choice list's first level supplies tabs. An empty source gives an empty group. With an out-of-range object index, the bridge reports the selection 4D paints. The adapter accepts up to 4096 choices.

## Check your form

1. Check `AXB_Host("info"; New object).nativeStatus` for `tabs 1` and `buttonInput 1`. Missing `tabs 1` means 4D loaded an older plugin. Install plugin, component and helpers from a supporting kit, then restart 4D; refreshing helpers alone cannot add tabs.
2. Give the tab group a name that makes sense when spoken. A configured `controls.<objectName>.label` wins, otherwise the help tip, otherwise the object name. For a tab in a page subform, put the label under `children.<container>.controls`. Add a central label only if the existing name is unclear. Choice names reuse the source's localized text.
3. After the first snapshot, inspect `AXB_Form("diagnostics"; New object)`. Require `ready: True`, and check tab entries in `.issues` against the reasons below. Each entry identifies the subform `path`, `object` and failure `reason`.
4. Use an external AX client and VoiceOver to read every choice and change selection. Check the actual index or page, editor commit and validation. Confirm the existing object and form methods run as they do for one ordinary click, using an existing log or a breakpoint if needed.
5. Repeat at the narrowest supported window size and in each claimed execution mode. A strip can become a native popup. Check its choices, dismissal and selected value too. Follow the skill's [whole-form checks](../SKILL.md#4-validate-the-whole-requested-ui) for repeated children, relabeling, resizing and close.

| Diagnostic reason | What to do |
| --- | --- |
| `nativeTabLayoutUnavailable` | Install the matching plugin advertising `tabs 1`. |
| `nativeTabLayoutPending` | Check again after 4D paints the form or changed labels. A persistent entry needs a bridge fix. |
| `nativeTabOverflowPending`, `tabSourceTypePending` | Record the control as unsupported and leave its layout and binding intact. The shared adapter needs work. |
| `tabCountExceeded` | The source exceeds the adapter's 4096-choice limit. Record the gap. |

## Coverage

[Acceptance evidence](../../../validation/tabs-development.json) records 564 checks in eight runs on native ARM 4D 20.8/macOS 26.7, dated October 2, 2026. Existing controls pass 520 regression checks, including ordinary controls, grids and compiled VoiceOver. Independent source review found no demonstrated defect. This table describes branch work; kit availability is in [the availability table](STATUS.md#availability).

| Presentation or scenario | Status |
| --- | --- |
| Array, object and list tab strips; bottom placement; page changes | Passed interpreted AX and compiled VoiceOver checks. |
| Generated roots and list item icons | Passed interpreted AX and compiled VoiceOver checks. |
| Compact array, object and list controls | Passed native menu selection; the array popup also passed dismissal without mutation. |
| Twelve icon choices in a narrow control | Passed distant-choice selection through the actual native popup. |
| Repeated children and clipped scrolling subforms | Passed independent handlers and retained-element reveal checks. |
| Restarting registration while the form stays open | Passed twice per run, preserving bindings and business handlers while retiring the former tree. |
| Actual native scroll-arrow presentation | Not observed on this runtime. Support is unvalidated. |
| Complete compiled window without changed pixels | Normal and compact/icon forms are pixel-identical to a bridge-free baseline, without masks or tolerance. |

## What clients see

A displayed tab strip is an `AXTabGroup`. Its children use Apple's `AXRadioButton` role with the `AXTabButton` subrole, so assistive tools identify them as tabs. `AXTabs`, `AXSelectedChildren` and the group's `AXValue` identify the actual choices and selected child. A selected strip tab with `gotoPage` links through `AXLinkedUIElements` to the visible page's discovered top-level controls. Popup tabs, page-zero toolbars and nested subform descendants have no direct page links. A tab whose application method loads other content keeps that method; the bridge does not guess a page relationship.

4D can render a narrow tab control as a popup. The bridge then exposes an `AXPopUpButton` and its selected text. `AXPress` opens the original native menu, whose `AXMenuItem` children provide selection and dismissal. The form keeps its dimensions. This behavior is observed on the tested 4D 20.8/macOS installation; [4D's tab documentation](https://developer.4d.com/docs/FormObjects/tabControl) also describes a scroll-arrow variant this runtime did not render.

List references remain private to the host. Repeated child forms keep independent selection and handlers even when their controls have identical names.

Changing the choice labels retires the old bridge tab children. Changing between a strip and a popup retires the previous bridge representation. Native menu lifetimes belong to AppKit; an accepted native-menu AX response still requires checking the application result. Closing the form retires the bridge group and its children.

For adapter internals and reproducible fixture commands, see [maintainer acceptance](../../../tests/TABS.md).
