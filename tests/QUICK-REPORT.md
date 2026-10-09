# Quick Report editor

4D's Quick Report editor, which `QR REPORT` opens when it shows the editor (for example `QR REPORT([Table]; Char(1))`), is published by the native plugin alone. It needs no host change. Without the plugin, macOS publishes only the window's title.

The editor is a 4D form whose objects are layers. The plugin reads the text 4D draws in them and publishes:

- the toolbar's buttons by their titles: New, Open…, Save, Destination, Preview, Execute, Clear, Revert, Header, Footer, Options and Fields;
- the panel a toolbar button opens below the toolbar. The Destination panel's File, Print and HTML are radio buttons, the one 4D frames being chosen. Other panels publish their titled objects and their Close button;
- the report's sheet, as a table named Report. Its first column, Row, holds the row titles 4D draws at its left: Title, Format, the totals and subtotals. Each other column is a report column, named by the title in its header button, and each cell holds the text 4D draws in it;
- the record count in the status line.

**Fields** opens a sheet that chooses the report's columns. While it is open, only the sheet is published, since the editor behind it is masked. It has the available fields, the report's columns, a search field, its options, the arrow buttons labelled Add field, Add all fields, Remove column and Remove all columns, and Cancel and OK. The available fields and the report's columns are each a list element, named **Fields** and **Report columns**, that VoiceOver enters with VO-Shift-Down, and a list longer than its box scrolls by a page as the [formula editor's lists](FORMULA-EDITOR.md) do. Pressing an available field double-clicks it, which adds it as a column, as with the mouse. Pressing a column clicks it, which selects it for Remove column.

Every press is an ordinary click, so 4D runs its own handling exactly as for the mouse. Execute to HTML opens macOS's own Save dialog, which is accessible already.

In the sheet, pressing a cell clicks it. **Show Menu** on a cell, a row title or a column's title is a secondary click there, which opens 4D's own context menu: Edit and Clear Contents for a cell, Hide this row for a row, and New column, Duplicate this column, Edit the formula…, Hide this column and Delete this column for a column. That menu is a native macOS menu, so it is navigated and chosen with the keyboard, VoiceOver or accessibility. Writing a report column's cell edits it in place, as a keyboard user would: a double click starts editing, Command-A selects the cell's text, the value is typed and Tab ends editing. That sets a column's title, its format, or a total's text. The sheet reads where the pointer is rather than where a click is, so the pointer moves to each of these clicks and returns to where it was once the action is over, after its menu closes.

The header and footer contents are not yet published, and a column's selection in the sheet and the selected cell are not reported. A report built from fields, its titles and formats edited, and executed to HTML is covered end to end.

## Test

```sh
python3 test_quick_report_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_quick_report_fixture.py --server /path/to/4D\ Server.app --run
python3 test_quick_report_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_quick_report_fixture.py` builds a project with an Orders table, whose twenty note fields make its field list longer than its box, and five records, whose startup method opens the editor. The AX run checks an unchanged window, the toolbar and the record count. It pages the Fields sheet's list of fields down to the last notes and back up, adds two fields, removes one and adds it again, and checks the report's sheet as a table. It renames a column's title and sets the other's format by writing their cells, and opens a column's and a cell's menus with Show Menu. It then chooses the HTML destination and executes the report, saving it through macOS's Save dialog. The saved report must contain every record, with the edited title and the format. The VoiceOver run enters the list of fields, adds a field with VO-Space and confirms it. It reads the sheet as a table, interacts with it to read a row title and a cell, and opens the cell's menu with Show menu from VoiceOver's actions menu (VO-Command-Space). It then reads the destinations as radio buttons. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/quick-report-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta.

Remaining scope: the header and footer, the selected column and cell, totals' operators, the options of each destination, 4D Server and remote clients, and 4D on Windows.
