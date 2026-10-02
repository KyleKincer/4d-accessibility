# Classic-selection reads

Classic current/named-selection list boxes still need a grid adapter. These command checks establish how it can read rows without disturbing the form's record buffer. They do not establish accessible grid navigation or editing.

Run the compiler and desktop checks sequentially, with other 4D instances closed:

```sh
python3 test_classic_selection.py --server /path/to/4D\ Server.app --run
```

On 4D 20.8, both interpreted and compiled desktop execution pass 131 checks. The fixture has five synthetic records and tests saved, modified, unloaded and unsaved-new record states. It compiles both ARM and Intel targets; runtime execution is native ARM.

`LONGINT ARRAY FROM SELECTION` reads current or named selections while preserving the current record, selected-record position, unsaved values, modification state and `OK`. `Create entity selection` and extraction of stored attributes also preserve that state. Entity values reflect persisted data, so an adapter still needs to check what the original list box displays during native editing.

Named selections can be converted in an isolated process: read their physical record numbers in the form process, use `CREATE SELECTION FROM ARRAY` in the private process, then return a shared copy of `Create entity selection`. The fixture verifies reversed named-selection order and the original form's unchanged record state. Physical record numbers can be reused after deletion; the adapter must derive stable row identities from primary keys or an existing application identity.

`SELECTION RANGE TO ARRAY`, `SELECTION TO ARRAY` and `Selection to JSON` unload the modified record in this fixture. They must not run in the form's process to inspect an accessibility grid. A successful export is insufficient if inspection discards unsaved input.

[Command evidence](../validation/classic-selection-commands.json) records the sources, compiler results and before/after states. Live grid, native editor, highlight-set, stale-identity and VoiceOver acceptance remain open in [the family checklist](../skills/4d-accessibility/references/FULL-FORMS.md).
