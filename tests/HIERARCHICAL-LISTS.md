# Hierarchical lists

A classic hierarchical list (`New list`, `APPEND TO LIST`, a form object of type `list`) is discovered automatically and published as an outline. It needs no configuration: the label comes from a configured `controls` entry, else the object's help tip, else its name. Items are keyed by their list reference, so references must be unique within the list.

Each visible item is a row with its depth, and each item with a sublist is a group with its expanded state. The list's own selection is reported. Rows follow 4D's display order; children of a collapsed item are omitted until it expands.

Actions use 4D's own keyboard handling, so the list's normal events run and no item geometry is involved:

- **Select**: the visible neighbor is selected without an event, then one Down (or Up) arrow moves to the item. 4D scrolls it into view and runs On Selection Change and On Clicked. If the list does not have focus, `GOTO OBJECT` enters it first, which runs On Getting Focus.
- **Expand or collapse**: the item is selected as above, then Right toggles it, running On Expand or On Collapse. A request for the current state completes without a key.
- **Reveal**: `OBJECT SET SCROLL POSITION` scrolls the item's line into view.

Pointer clicks were rejected for these actions. 4D reports a list's scroll position rounded up to a whole line, while a trackpad can leave the list part of a line further on, so a computed click point can land on the neighboring item.

## Test

```sh
python3 test_hlist_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_hlist_fixture.py --server /path/to/4D\ Server.app --run
python3 test_hlist_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_hlist_fixture.py` builds an area-owned form with nested, expanded and collapsed groups and more items than fit. Its object method records each list event with the selection and expansion. `--baseline` records the same window without the plugin, component or helpers; `--run` then requires an unchanged form before the first action. Add `--compiled` or `--intel` for the other execution modes.

The AX run checks order, depth, state and selection; selection in a partly scrolled list; expansion and collapse of nested groups through the list's own events; an idempotent request; and revealing then selecting an item below the visible lines. The VoiceOver run enters the list on its selected item, reads a collapsed group, expands it with VO-Space and collapses it with VoiceOver's disclosure command, each announced, and selects an item with VO-Space. Posted keys are refused unless 4D is frontmost.

## Limits

Item text only: icons, styles and colors are not described. Editing an item's text (an enterable list reports `hierarchicalListEditingPending`), multiple selection (a multi-selectable list acts as single-selection and reports `hierarchicalListMultipleSelectionPending`) and drag and drop are not supported. A list with duplicate item references is reported as `hierarchicalListDuplicateReferences` and left unavailable. Client/server and very large lists are unvalidated.
