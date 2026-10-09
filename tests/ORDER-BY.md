# Order By editor

4D's Order By editor, which `ORDER BY([Table])` opens when it is given no criteria, is published by the native plugin alone. It needs no host change. Without the plugin, macOS publishes only the window's title.

The editor is a form of 4D whose objects are layers, and the plugin reads the text 4D draws in each one. It publishes:

- **Available Fields**, its caption, and each of the table's fields as a button. Pressing a field double-clicks its line, which orders the selection by it, ascending, as with the mouse;
- **Add field**, **Remove field** and **Remove all fields**, the arrow buttons between the lists, which have no titles;
- **Ordered by Fields/Formulas**, its caption, and each field or formula the selection is ordered by, top to bottom, as a button. Pressing one selects it, as a click does, for Remove field;
- after each ordered field, its **Descending** checkbox. 4D ends each line with a triangle that points up for ascending and down for descending, and a click on the triangle reverses it. The plugin reads which way the triangle points from 4D's image, and pressing the checkbox clicks the triangle;
- **Add Formula…**, **Modify…**, **Cancel** and **Sort**, by their titles.

Each list is a list element named by its caption, holding its lines and, in the ordered list, each line's Descending checkbox; VO-Shift-Down enters it. A list longer than its box scrolls by a page as the [formula editor's lists](FORMULA-EDITOR.md) do.

Every press is an ordinary click, so 4D runs its own handling exactly as for the mouse. Add Formula… and Modify… open 4D's [formula editor](FORMULA-EDITOR.md), which is published in turn.

VoiceOver orders this window's elements by their positions: the ordered fields' list, which sits at the top right, comes before the available fields' list below its caption.

## Test

```sh
python3 test_order_by_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_order_by_fixture.py --server /path/to/4D\ Server.app --run
python3 test_order_by_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_order_by_fixture.py` builds a project with an Orders table of text, number, Boolean and date fields and five records. Its startup method opens the Order By editor and records OK and the customers of the sorted selection, in order. The AX run checks an unchanged window, the published controls and the two lists. It orders by Paid, then by Customer, whose Descending checkbox it presses, and adds Amount and removes it again. Sorting must return Customer 5, 3, 1, then 4 and 2. The VoiceOver run enters the available fields' list and orders by Customer with VO-Space, enters the ordered list, reads Customer's direction as an unchecked checkbox, checks it with VO-Space, and sorts with VO-Space on Sort, which returns the customers from 5 to 1. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/order-by-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta.

Remaining scope: an acceptance run that orders by a formula, related tables' fields, localized editors, 4D Server and remote clients, and 4D on Windows.
