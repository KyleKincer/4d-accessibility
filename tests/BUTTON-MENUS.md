# Buttons with pop-up menus

A button whose **With pop-up menu** property is set (`popupPlacement` in the form) is discovered automatically. Item 11 of its `OBJECT Get format` is 1 for a linked menu and 2 for a separated one. The button is published as a button with both Press and **Show Menu**.

- **Linked:** any click on the button runs its On Alternative Click, and On Clicked does not run. Press and Show Menu are therefore the same ordinary click.
- **Separated:** a click on the button runs its On Clicked; a click on the small arrow that the bevel, custom and rounded bevel styles draw at the button's bottom-right corner runs On Alternative Click. Press clicks the button, and Show Menu clicks the arrow.

Either way, the bridge posts an ordinary click, which 4D handles exactly as for the mouse. The button's own method shows its menu, usually with `Dynamic pop up menu`. That menu is a native macOS menu: it stays open, is published with its items, and is navigated and chosen with the keyboard, VoiceOver or accessibility. The chosen item, or nothing when the menu is dismissed, returns to the method as usual.

The regular and toolbar styles draw no separate arrow; their separated menu opens only with a long click. Such a button keeps Press and is reported as `buttonMenuArrowPending`.

With VoiceOver, VO-Space opens a linked button's menu. A separated button's menu is **Show menu** in VoiceOver's actions menu (VO-Command-Space).

## Test

```sh
python3 test_button_menu_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_button_menu_fixture.py --server /path/to/4D\ Server.app --run
python3 test_button_menu_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_button_menu_fixture.py` builds an area-owned form with a bevel button with a linked menu (Export), a custom button with a separated menu and its own On Clicked (Search), and a regular button with a separated menu (Plain). Each method records its events and the item chosen from the menu it shows. The AX run checks the offered actions, an unchanged form and the coverage report. It then opens Export's menu and chooses an item, opens Search's menu and dismisses it, and presses Search. The VoiceOver run opens Export's menu with VO-Space and Search's with the actions menu, and chooses an item from each with the arrow keys and Return. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/button-menus-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged form; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta.

Remaining scope: separated menus on the regular and toolbar styles, and 4D on Windows.
