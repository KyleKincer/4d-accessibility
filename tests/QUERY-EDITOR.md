# Query editor

4D's Query editor, which `QUERY([Table])` and the standard query command open, is published by the native plugin alone. It needs no host change. Without the plugin, macOS publishes only the window's title.

The editor is the `QUERY` form of 4D's internal runtime component, with a `QUERY_LINE` subform for each criterion. Its objects are layers named as in those forms, and the plugin reads the text 4D draws in each one. It publishes, in reading order:

- **Query options** (the gear), **Recent queries** when shown, and the **Destination** of the found records, as pop-up buttons that open 4D's own menus;
- for each criterion, top to bottom: its **Conjunction** (And, Or, Except) from the second criterion on, its **Field**, its **Comparison**, then its **Value**, or **From** and **To** for a range, as text fields or pop-up buttons by the field's type; then **Remove line** and **Add line**;
- **Cancel** and **Query**.

Every press is an ordinary click on the object, so 4D runs its own handling exactly as for the mouse. The comparison, conjunction and destination menus are native macOS menus, which VoiceOver and accessibility clients read and choose from. An empty value draws its placeholder, such as "Value" or "Date", which is published as the field's placeholder and not as its value.

The **Field** pop-up opens 4D's field list, a separate borderless window whose items are drawn as a whole into one layer. The plugin finds each item's line from where 4D draws its text and publishes each item as a button over it. VoiceOver starts on the criterion's current field, and pressing an item chooses it, as clicking it does. The items stay the window's own elements, since VoiceOver, starting on a line nested in a list in this window, cannot move on from it. A table longer than the list's box adds the list's scroll bar after the items, as **Fields**: it reports where its thumb is, and Increment and Decrement scroll a page down and up. Each item offers VoiceOver's Scroll down and Scroll up too, as the [formula editor's lists](FORMULA-EDITOR.md) describe. A field name typed into the field itself is completed on each keystroke, so the field is not editable through accessibility; it is chosen from the list.

Writing a value clicks inside its field, as the mouse focuses it, deletes the current text and types each character as an ordinary key. Focusing a value field through accessibility, as VoiceOver does when its cursor reaches it, gives the field 4D's keyboard focus the same way, so typed keys enter it. Typing is announced as text edits, so VoiceOver echoes it.

Recognition is strict: a window is the Query editor only when its form holds Query and Cancel buttons and at least one criterion line. Only the objects listed here are published; notes and offscreen copies in the form are not.

## Test

```sh
python3 test_query_editor_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_query_editor_fixture.py --server /path/to/4D\ Server.app --run
python3 test_query_editor_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_query_editor_fixture.py` builds a project with an Orders table of text, number, Boolean and date fields, twenty note fields after them so the field list is longer than its box, and five records. Its startup method opens the Query editor and records OK and the customers found. The AX run checks an unchanged window and the published controls. It then chooses a field from the list, pages the list down to the last notes with its scroll bar and back up, and chooses again, a comparison and conjunction from their menus, writes values, adds and removes a criterion, and queries. The query (Customer starts with "Customer 3", or Amount greater than 40) must find Customer 3 and Customer 5. The VoiceOver run chooses the field with VO-Space, the comparison with the arrow keys and Return, types the value, and presses Query with VO-Space. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/query-editor-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta. Standard messages, which now share the same overlay, pass interpreted, compiled and under Rosetta, and with VoiceOver.

Remaining scope: the formula criteria of the editor's second page, the field list's related tables, localized editors, 4D Server and remote clients, and 4D on Windows. The Order By editor is described in [its own page](ORDER-BY.md).
