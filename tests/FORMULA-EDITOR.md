# Formula editor

4D's formula editor is published by the native plugin alone. `EDIT FORMULA` opens it, as do the Order By editor's Add Formula… and Modify… buttons. It needs no host change. Without the plugin, macOS publishes only the window's title.

The editor is a form of 4D whose objects are layers, and the plugin reads the text 4D draws in each one. It publishes:

- the help line above the lists, as text;
- **Tables**, the menu that chooses whether the first list shows the master table's fields, related tables or all tables, then that list. A field is a button; pressing it double-clicks its line, which inserts it into the formula, as with the mouse. A table is a disclosure triangle, expanded while its fields show; pressing it clicks its chevron, which shows or hides them;
- **Operators**, the menu that chooses a kind of operator, then the operators as buttons. Pressing one inserts it;
- **Commands**, the menu that lists the commands by theme or alphabetically, then the list. A theme is a disclosure triangle like a table, and a command is a button that inserts it;
- **Formula**, the formula as a text field. Writing it replaces the formula as a keyboard user types it, and focusing it clicks it, so the keys a user types reach it. While it holds 4D's caret it is the focused element, so VoiceOver echoes typing;
- **Load…**, **Save…**, **Cancel** and **OK**, by their titles.

The three menus are native macOS menus, so they are navigated and chosen with the keyboard, VoiceOver or accessibility. Every press is an ordinary click, so 4D runs its own handling exactly as for the mouse.

The plugin tells a table or theme from a field or command by the chevron 4D draws before it: smaller than any icon, pointing right while collapsed and down while expanded.

Only the lines a list draws are published. A list longer than its box shows the rest once it scrolls, with the mouse or the arrow keys.

## Test

```sh
python3 test_formula_editor_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_formula_editor_fixture.py --server /path/to/4D\ Server.app --run
python3 test_formula_editor_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_formula_editor_fixture.py` builds a project with an Orders table of text, number, Boolean and date fields and five records. Its startup method opens the formula editor with `EDIT FORMULA`, starting from `[Orders]Amount`, and records OK, the formula and its value for each record.

The AX run:
- checks an unchanged window, the published controls and the starting formula;
- clears the formula, inserts the Customer field and the concatenation operator, and expands and collapses the Boolean theme;
- lists the commands alphabetically and inserts Abs;
- lists all tables and expands Orders to show its fields;
- writes `[Orders]Customer+"/"+String([Orders]Amount*2)` and presses OK. The application must evaluate it to `Customer 1/20` through `Customer 5/100`.

The VoiceOver run:
- reads the collapsed Boolean theme and expands it with VO-Space;
- inserts the Customer field with VO-Space;
- moves to the formula and types `String([Orders]Amount*3)`, which VoiceOver echoes;
- presses OK with VO-Space. The values must be `30` through `150`.

Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/formula-editor-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta.

Remaining scope: lines a list has not drawn, Load… and Save…'s files, the Quick Report editor's and other commands' routes to the editor, localized editors, 4D Server and remote clients, and 4D on Windows.
