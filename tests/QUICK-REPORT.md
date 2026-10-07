# Quick Report editor

4D's Quick Report editor, which `QR REPORT` opens when it shows the editor (for example `QR REPORT([Table]; Char(1))`), is published by the native plugin alone. It needs no host change. Without the plugin, macOS publishes only the window's title.

The editor is a 4D form whose objects are layers. The plugin reads the text 4D draws in them and publishes:

- the toolbar's buttons by their titles: New, Open…, Save, Destination, Preview, Execute, Clear, Revert, Header, Footer, Options and Fields;
- the panel a toolbar button opens below the toolbar. The Destination panel's File, Print and HTML are radio buttons, the one 4D frames being chosen. Other panels publish their titled objects and their Close button;
- the report's columns, by the titles drawn in its first row, read-only;
- the record count in the status line.

**Fields** opens a sheet that chooses the report's columns. While it is open, only the sheet is published, since the editor behind it is masked. It has the available fields, the report's columns, a search field, its options, the arrow buttons labelled Add field, Add all fields, Remove column and Remove all columns, and Cancel and OK. Pressing an available field double-clicks it, which adds it as a column, as with the mouse. Pressing a column clicks it, which selects it for Remove column.

Every press is an ordinary click, so 4D runs its own handling exactly as for the mouse. Execute to HTML opens macOS's own Save dialog, which is accessible already.

The report's cells, such as their formats, totals and the header and footer contents, are not yet published, and a column's selection in the sheet is not reported. A report built from fields and executed to HTML is covered end to end.

## Test

```sh
python3 test_quick_report_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_quick_report_fixture.py --server /path/to/4D\ Server.app --run
python3 test_quick_report_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_quick_report_fixture.py` builds a project with an Orders table and five records, whose startup method opens the editor. The AX run checks an unchanged window, the toolbar and the record count. It adds two fields in the Fields sheet, removes one and adds it again, and checks the report's columns. It then chooses the HTML destination and executes the report, saving it through macOS's Save dialog. The saved report must contain every record. The VoiceOver run adds a field with VO-Space, confirms it, and reads the destinations as radio buttons. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/quick-report-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta.

Remaining scope: the report's cells and its header and footer, the selection of a column, the options of each destination, 4D Server and remote clients, and 4D on Windows.
