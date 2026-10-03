# Classic list subforms

This adapter is development work for a matching 0.22.0 kit. It is absent from published releases. Build the kit using [CONTRIBUTING.md](../../../CONTRIBUTING.md). Require `listSubforms 1` in `AXB_Host("info"; New object).nativeStatus`, then check [current acceptance](STATUS.md#classic-list-subforms-in-development).

A classic list subform repeats a table form for each record. The bridge exposes those records as one accessible table, including rows outside the viewport. The parent lifecycle area discovers the list. The repeated row form needs no accessibility area, row method or field hook.

## Install a parent form

Install the matching plugin, component and helpers using [area installation](AREA-INTEGRATION.md). Keep your existing `--compiler-method` and `--area-list` options when updating. For a table input form, select its table number and form name:

```sh
python3 install_host_methods.py --project-dir /path/to/MyApp/Project \
  --form TableForms/2/RecordEditor --dry-run
```

For a project form, use `--form RecordEditor`. Review the preview, rerun without `--dry-run`, and commit the changed form definition, the parent or its shared base, generated helpers/compiler declarations and generated resource. The installer preserves existing objects, layout, events and methods. It adds no area to the repeated row form. If an older bulk install added one there, follow the [bulk ownership migration](AREA-INTEGRATION.md#ordinary-named-form); that migration removes only the old canonical area.

The installer owns `<application>/Resources/AXB.FormMetadata.json`, next to `Project`. Commit and ship it unedited with the application's normal Resources folder. It records row markers and parent selection/entry settings from project and table form definitions, including forms outside the selected installation set. 4D cannot query the required markers from a named compiled row form at runtime.

Rerun the installer with your existing options to keep generated metadata current:

- After adding, renaming or deleting a form, changing header/body markers, or changing a parent's `selectionMode` or `enterableInList`, refresh the helpers and existing resource. Reopen affected forms to discard cached metadata.
- When upgrading an area integration that has no resource, add `--form-metadata`. This creates metadata without adding areas.
- An edited or non-generated resource stops every installation before writes, including method-only refreshes. Delete that file, then regenerate with your existing options plus `--form-metadata`.
- In CI, use your normal options plus `--form-metadata --dry-run`. A dry run exits zero even with pending changes; fail the check if output includes `../Resources/AXB.FormMetadata.json`. An edited resource causes a nonzero exit. Metadata covers all named forms, so unrelated form work can require regeneration too. Runtime schema checks do not detect stale form metadata.

## What works automatically

A named table list form with stored scalar fields and a stored text or integer primary key supplies its own rows, column bindings and stable record keys. Column names reuse aligned header captions or checkbox titles, then field/object names. The table's name defaults to the parent subform object name. Supply a central `label` if that name is unclear.

Text, numeric, date and time fields expose formatted scalar values. Boolean and integer checkboxes expose their checked state. Password fields remain unreadable and uneditable. Unsupported controls produce diagnostics rather than invented values or actions.

Selection follows the parent's `selectionMode`. When it is absent, the tested native default is `none`. Editing also requires the parent's **Enterable in list** property, `enterableInList`, plus the native row field's permissions. The adapter does not enable either setting on behalf of the application.

Inspection reads stored entities in a private process, preserving the form's current selection, record buffer and unsaved values. A loaded record and active native editor supply live values. The application's normal repaint still applies. Changes made to a loaded row outside its editor may be discarded by 4D's repaint, with or without the bridge.

Actions use the original UI. Selection sends verified row clicks and Command-clicks, preferring a read-only field. If all fields are enterable, a selection click may enter the clicked field's native editor. Keep an existing read-only body field when selection must avoid entering an editor. Text editing uses `EDIT ITEM`, verifies the row and field, then uses the native text editor. Checkbox activation clicks the actual checkbox directly. Original key filters, validation, selection handlers and save behavior remain authoritative. The bridge does not assign fields or save records.

Stable [window-scoped locators](IDENTIFIERS.md) contain the parent path, stored record key and row-form object name. Reacquire handles after replacement or reopen. A retained handle cannot act on a hidden, rebound or retired list.

## A table without a primary key

4D leaves a table without a primary key out of `ds`. Set `keyProperty` to an existing stored Alpha, Text, Integer or Longint field inside an explicit `grids.<object>` entry with `"kind"; "listSubform"`, as in the configuration example below. Integer 64 fields are not supported by this fallback. The field name is case-sensitive; its values must be unique and nonempty. This adds no database field or row method.

For mapped ORDA tables, stored string or number attributes can identify rows. Numeric values must be whole 32-bit integers. `keyProperty` can override a declared primary key too, for example to use an existing stable text key.

The private reader takes scalar snapshots of the displayed fields and key. Native editing and selection use the same UI path. Check acceptance for this mode before claiming support. A missing or invalid key reports `classicIdentityRequired`; invalid or duplicate row values leave the table unavailable. This fallback is for list subforms. Classic listboxes retain their documented ORDA requirement.

## Add only missing application knowledge

In the existing central `AXB_Configure`, add a branch that names the parent list or describes unclear columns. Merge it into the options you already return:

```4d
If ($formName="RecordEditor")
 If ($options.grids=Null)
  $options.grids:=New object
 End if
 $options.grids.RelatedRecords:=New object("kind"; "listSubform"; "label"; "Related records"; "columns"; New object("DescriptionField"; New object("label"; "Description")))
End if
```

An explicit grid entry must include `"kind"; "listSubform"`. It replaces automatic discovery for that object. `label` is optional and defaults to its object name. `RelatedRecords` names the parent's subform object. `DescriptionField` names an input in the repeated row form. Preserve existing grid entries, controls, readiness and error reporting when merging this branch. Add `keyProperty` here when choosing an existing identity field. Distinguish table forms with identical names by their table as described in [central configuration](INTEGRATION.md).

Column `automationKey`, `decorative` and `value` follow the [grid metadata contract](GRIDS.md#describe-custom-native-grid-columns). Mark visual-only body objects `decorative: True`. A `value` Formula receives a stored entity or scalar snapshot and the request; reuse a side-effect-free display formatter. Its result is read-only, even if the object also has a field binding. A `ready` Formula can gate a yielding loader.

The list owns its current selection and native events. `selection`, `onSelection` and `meta` are not valid list-subform options. An invalid option for any visible grid fails the entire form description with `invalidGrids`; no automatic table or control appears. Check diagnostics after editing the configuration.

## Verify a record form

1. Open the actual parent with its matching kit and generated metadata. In the root form's process, check `AXB_Area("diagnostics"; ""; "")` for an active registration, then `AXB_Form("diagnostics"; New object)` after the first snapshot. Each required list must have an enabled table, no unsupported entries for that list, and a row count matching its native parent selection. `ok: True` alone is insufficient; missing parent metadata can leave a read-only table.
2. Inspect every page, nested form, loading state and required control. A readable table alone does not establish whole-form accessibility.
3. Read the first and last records externally. Inspect a modified record and confirm that inspection preserves its buffer and selection.
4. Select and edit through accessibility, then leave the original editor and inspect saved values independently. Verify native callbacks and rejected input.
5. Hide, disable, rebind or replace the list. Retained elements must reject actions. Restore it and reacquire live elements.
6. Test VoiceOver navigation and actions in every execution mode and layout being claimed. Record failures and untested cases separately.

The [owned fixture](../../../tests/LIST-SUBFORMS.md) provides reproducible commands. It covers synthetic project/table parents, not acceptance of an application's complete record workflow. Automatic relations, lists on nonzero pages, page-nested lists and several lists in one parent need their own live checks.

## Diagnose a missing or incomplete table

| Reason | Meaning and next step |
| --- | --- |
| `nativeListSubformUnavailable` | Native capability missing. Install matching packages. |
| `listSubformDefinitionRequired` | Row metadata missing, or the row form has no valid header/body markers. Check the row definition, then regenerate and ship the resource. |
| `listSubformParentMetadataRequired` | Parent settings missing. Selection/editing remain unavailable. Regenerate named-form metadata. JSON-generated parents have no parent metadata path yet; their selection and editing remain unavailable. |
| `listSubformBodyUnavailable` | Invalid header/body markers in a hand-built or edited resource. Restore installer ownership and regenerate it. |
| `listSubformUnavailable` | The object is hidden, not a list subform or has no valid row form. |
| `listSubformPending` | List reached through explicit child registration. Use parent discovery. |
| `classicIdentityRequired` | No declared primary key and no `keyProperty`, or the chosen key is missing, not stored, or has an unsupported type. Select a supported existing identity field as described above. |
| Disabled label `Classic row identity is unavailable` | Empty or missing row key. Correct the data or choose another stored identity field. |
| Disabled label `Classic row identity must be text or a 32-bit integer` | Unsupported key value, including fractional or out-of-range numbers. Correct the data or choose another identity field. |
| Disabled label ending in `row keys must be unique nonempty text` | Duplicate row key, or a text key longer than 254 characters. There is no separate reason code. Correct the existing data or select another identity field. |
| Disabled label `Classic selection is loading` | No current table selection is available yet. Wait for the normal loader and inspect again. |
| `gridValueDescriptionRequired` | No usable scalar value. Supply a description or mark a visual-only object decorative. |
| `listSubformControlPending` | Body control type needs an adapter. |
| `listSubformStyledTextPending` | Styled row editor needs an adapter. |
| `listSubformEditingPending` | Enterable body object has no direct field binding. Describe it read-only or implement its native editor path. |
| `listSubformHeaderFooterControlPending` | Interactive header/footer control needs an adapter. |
| `invalidGrids` | Invalid central grid options fail the entire automatic form description. Correct the configuration. |

Adapter-level table failures keep a disabled label with the reason. Empty or disabled output is not successful coverage.

Horizontal scrolling away from the initial position, per-row appearance/permission methods, very large selections and record sets, dynamic row definitions, grouped/break layouts, related-table expressions, styled grid editors, embedded children, record creation/deletion, transactions and client/server delivery remain separate work. A calculated description does not implement an interactive editor. Preserve the existing detail opener and business actions. Use the [full-form checklist](FULL-FORMS.md) for all other families.
