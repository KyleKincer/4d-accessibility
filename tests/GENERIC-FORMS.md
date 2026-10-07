# Forms without a bridge area

An application's own forms that have no bridge area get a baseline description from the native plugin alone, with no host change. An integrated form, with its lifecycle area, keeps the bridge's complete description; the plugin leaves it to the bridge.

4D draws each form object into a layer named after the object, and the plugin reads the text it draws there. When it starts, the plugin indexes the open project's form definitions, `Project/Sources/Forms` and `TableForms`, in the background. A window is matched to the form that holds most of its object layers. Too few objects, or two equally likely forms, leave the window untouched. The plugin then publishes, in reading order:

- **buttons** by their drawn titles, their definition's titles or else their help tips. A button with none of these is not published;
- **captions** as static text;
- **inputs** as text fields with their drawn values and placeholders. Each is labelled by its help tip, or by the caption on its left or just above it;
- **checkboxes and radio buttons** by their titles. Their state is read from the image 4D draws, in the standard style: macOS fills a checked box or chosen button with the accent color. With a gray accent color, or a custom style, the state is not reported;
- **drop-down lists** as pop-up buttons showing their drawn values.

Each press is an ordinary click on the object, so 4D runs its own handling exactly as for the mouse. A drop-down opens 4D's native menu. Writing an input's value clicks into it, deletes its text and types each character; focusing an input clicks into it, so typed keys enter it. Typing is announced as text edits.

Picture buttons, group boxes and combo boxes are published as buttons, captions and text fields in the same way, without acceptance yet. Localized and computed titles (`:xliff:…`, `<variable>`) are not used as labels. List boxes, tab controls, subforms, pictures, hierarchical lists, web areas and plugin areas are not yet described this way. Integrate a form through its [lifecycle area](../skills/4d-accessibility/references/AREA-INTEGRATION.md) for its complete description, including grids, values, states and focus.

## Test

```sh
python3 test_generic_form_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_generic_form_fixture.py --server /path/to/4D\ Server.app --run
python3 test_generic_form_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_generic_form_fixture.py` builds a project whose Customer form has no bridge area. The form has captions with inputs, a checkbox, two radio buttons, a drop-down list, a titled button, an untitled button with a help tip, an unlabelled button and Done. Its Save button records the form's values. The AX run checks an unchanged window, the published objects, their labels and their states. It then writes both inputs, checks the checkbox, chooses a radio button and a drop-down item, and presses Save. The values Save records must match. The VoiceOver run types into the Name field, checks the checkbox with VO-Space and presses Save. Add `--compiled` or `--intel` for the other modes.

[Acceptance](../validation/generic-forms-development.json): the AX run passes interpreted and compiled, in native ARM and Rosetta, with an unchanged window; the VoiceOver run passes interpreted and compiled on ARM and compiled under Rosetta. Integrated fixtures keep the bridge's description.

Remaining scope: list boxes, tab controls, subforms and the other kinds above; the keyboard focus 4D gives a field; 4D Server and remote clients; and 4D on Windows.
