# List boxes without a grid adapter

A list box in a form with the bridge's area, and with no entry in `AXB_Configure`'s `grids`, is published as a table of the rows 4D draws. The bridge reads the list box's columns at run time, with their titles, widths and visibility. The native plugin then reads each visible row from the text 4D draws, as it does for a form without an area ([forms without a bridge area](GENERIC-FORMS.md)). The table takes the list box's place in the form's reading order.

- The table is named by the list box's help tip, the caption to its left, or else the words of its object name: `listOrders` is Orders.
- Its columns are titled as 4D shows them, including titles the application changes at run time.
- Its cells are read-only.
- Pressing a row clicks it, so the list box runs its own On Selection Change.
- When the list box holds 4D's focus, the table is the focused element.
- A list box longer than its box scrolls a page with `AXScrollDownByPage` and `AXScrollUpByPage`. VoiceOver lists Scroll down and Scroll up in its actions menu (VO-Command-Space).

A `grids` entry replaces the drawn table with the complete one: every row, beyond the visible ones, with keyed identity and editing. [Grids](../skills/4d-accessibility/references/GRIDS.md).

A button that nothing labels is named the same way, by the words of its object name: `btnRefreshOrders` is Refresh Orders. Before, it was named by the object name itself.

## Test

```sh
python3 test_drawn_listbox_fixture.py --server /path/to/4D\ Server.app --run
python3 test_drawn_listbox_fixture.py --server /path/to/4D\ Server.app --run --compiled
```

The test prepares the [generic form fixture](GENERIC-FORMS.md) with `--area`, so the installer gives its forms the lifecycle area. It then checks:
- the Orders table's name, its rows and its column titles, after the form renames one when it loads;
- a row press, which the list box's On Selection Change records;
- the table's focus;
- paging through the 20 lines of another page's list box to the last.

Remaining scope: editing cells and every row without a page action, which need a `grids` entry; list boxes inside list subforms; two list boxes with the same object name in different subforms of one window, where the first is read; 4D Server and remote clients; and 4D on Windows.
