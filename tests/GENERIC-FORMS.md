# Forms without a bridge area

An application's own forms that have no bridge area get a baseline description from the native plugin alone, with no host change. An integrated form, with its lifecycle area, keeps the bridge's complete description; the plugin leaves it to the bridge.

4D draws each form object into a layer named after the object, and the plugin reads the text it draws there. When it starts, the plugin indexes the open project's form definitions, `Project/Sources/Forms` and `TableForms`, in the background. A window is matched to the form that holds most of its object layers. Too few objects, or two equally likely forms, leave the window untouched. The plugin then publishes, in reading order:

- **buttons** by their drawn titles, their definition's titles or else their help tips. A button with none of these is not published;
- **captions** as static text;
- **inputs** as text fields with their drawn values and placeholders. Each is labelled by its help tip, or by the caption on its left or just above it;
- **checkboxes and radio buttons** by their titles. Their state is read from the image 4D draws, in the standard style: macOS fills a checked box or chosen button with the accent color. With a gray accent color, or a custom style, the state is not reported;
- **drop-down lists** as pop-up buttons showing their drawn values;
- **list boxes** as tables of their visible rows, labelled by their help tip or caption. 4D draws every visible cell's text into one image; each row is a baseline, and each text belongs to the column that holds it. The visible columns are found between the separator lines 4D draws in the titles' band, since an application can hide and resize columns at run time. Each column's title comes from the definition, matched in order by width; a column drawn at another width than defined, which could be a different column, is left unnamed rather than misnamed. A row's selection is read from the accent color 4D fills it with; pressing or selecting a row is an ordinary click on it. VoiceOver selects the row its cursor reaches, as in AppKit's tables, and a row already selected is not clicked again.

A page subform publishes its own form's objects in its place, in the same way, with identifiers under the subform's name (for example `axb/form/search/btnGo`). Its form can be one of the project's, or a component's: the plugin also indexes the forms of the project's components and of those 4D includes, reading each component's archive (`.4DZ`, a zip) directly. 4D Widgets' search picker, date button and date entry set their prompts from their methods, so the plugin names their search field "Search" and their calendar and step buttons "Choose date", "Increase" and "Decrease" (the date widgets without acceptance yet). Component forms are only used for subforms; they never match a window. An object is published and clicked within the part its subform shows.

Each press is an ordinary click on the object, so 4D runs its own handling exactly as for the mouse. A drop-down opens 4D's native menu. Writing an input's value clicks into it, deletes its text and types each character; focusing an input clicks into it, so typed keys enter it. Typing is announced as text edits.

Picture buttons, group boxes and combo boxes are published as buttons, captions and text fields in the same way, without acceptance yet. Localized and computed titles (`:xliff:…`, `<variable>`) are not used as labels. Only a list box's visible rows are published, and their cells are read-only; tab controls, list subforms, pictures, hierarchical lists, web areas and plugin areas are not yet described this way. Integrate a form through its [lifecycle area](../skills/4d-accessibility/references/AREA-INTEGRATION.md) for its complete description, including grids, values, states and focus.

## Test

```sh
python3 test_generic_form_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_generic_form_fixture.py --server /path/to/4D\ Server.app --run
python3 test_generic_form_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_generic_form_fixture.py` builds a project whose Customer form has no bridge area. The form has captions with inputs, a checkbox, two radio buttons, a drop-down list, a titled button, an untitled button with a help tip, an unlabelled button and Done. It also has a collection list box of four orders, whose selection change is recorded, a page subform with a search field and a Go button, and 4D Widgets' search picker. Its Save button records the form's values. The AX run checks an unchanged window, the published objects, their labels and their states. It then writes both inputs, checks the checkbox, chooses a radio button and a drop-down item, selects a list box row, searches through the subform, types into the search picker, and presses Save. The values Save records must match. The VoiceOver run types into the Name field and checks the checkbox with VO-Space. It reads the list box as a table, enters it and moves to the next row, which is selected once, and presses Save. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/generic-forms-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta. Integrated fixtures keep the bridge's description.

Remaining scope: list box rows beyond those drawn, cell editing, tab controls, list subforms and the other kinds above; the keyboard focus 4D gives a field; 4D Server and remote clients; and 4D on Windows.
