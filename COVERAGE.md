# Coverage and gaps

What the bridge makes accessible today, what it does not, and what has never been tested. [STATUS.md](skills/4d-accessibility/references/STATUS.md) holds the detailed evidence and each family's page its scope. This page is the summary.

**Accessible** means a macOS accessibility client, such as VoiceOver, Voice Control or a test, can read the control and operate it through the form's own handling. Unless a row says otherwise, each family passes live tests in interpreted and compiled 4D, on Apple Silicon and under Rosetta, with an accessibility client and with VoiceOver.

## Forms with a bridge area

A form gets a bridge area from the installer (`--form` or `--all-forms`), or from `AXB_AreaForm` for a generated form. This is the complete path.

| Family | Accessible | Not yet |
| --- | --- | --- |
| Buttons, texts, inputs, checkboxes, radio buttons, drop-down lists, combo boxes, styled text | Read, edit and press through the form's own editors and events; the bounds of each character of the field being edited, which Zoom and VoiceOver follow | Input methods (IME) and complex scripts, character bounds of a field not being edited, spoken errors and status |
| Tab controls | Named tabs, selection | 4D's tab scroll arrows |
| Rulers, steppers, progress indicators, spinners | Values and increment/decrement | Dials |
| Picture buttons, picture popup menus, editable pictures, button grids | Named cells, presses, Cut/Copy/Paste/Clear | |
| Splitters | Adjustable | |
| Buttons with pop-up menus | Press and Show Menu | Separated menus on the regular and toolbar styles |
| Standard-action menus | | Not implemented |
| List boxes without configuration | The rows 4D draws, column titles, a row press that selects it, focus, paging ([drawn list boxes](tests/DRAWN-LIST-BOXES.md)) | Editing cells, every row without paging |
| Array, collection, entity-selection and current-selection list boxes, configured | Every row, beyond the visible ones; selection, sorting and editing through the native editors | An `AXB_Configure` entry with stable row keys. Styled cells, per-row restrictions, transactions, grids inside grid rows |
| Grouped (hierarchical) list boxes | Read text and date groups; open and close a group through one application formula | Selecting a leaf beyond the keyboard, reveal, editing. Compiled VoiceOver sometimes misses the state announcement after a disclosure |
| Hierarchical lists | Items, depth, expansion and selection, automatically | Editing an item's text, drag and drop, extending a selection through accessibility, icons and styles |
| Page subforms, repeated and nested | Automatic | |
| Classic list subforms | Stored scalar fields of every row, selection and editing | Forms generated from JSON as the parent |
| AreaList Pro | Configured grids: every row, text and checkbox editing | Characters outside the Basic Multilingual Plane (vendor defect), further cell types and layouts |
| Web areas | The system engine beside 4D controls, in reading order | The embedded (Chromium) engine, complete reading order in other layouts |

## Forms without a bridge area

The plugin alone describes an application form that has no area. It reads the project's form definitions. [Details](tests/GENERIC-FORMS.md).

| Accessible | Not yet |
| --- | --- |
| Buttons, picture buttons, texts, inputs, checkboxes, radio buttons, drop-down lists, tab controls, page subforms; list boxes' drawn rows and column titles, paged; 4D's keyboard focus | AreaList Pro, web areas, spinners, progress indicators, splitters, steppers, hierarchical lists, button grids, list subforms, editing a list box cell. Names come from developers' object names where nothing else labels a control |

Add the area to get the complete description.

## 4D's own windows

The plugin publishes these with no application change.

| Window | Accessible | Not yet |
| --- | --- | --- |
| `ALERT`, `CONFIRM`, `Request` | Message, field and buttons, with typing echo | |
| The error window, for a method's error with no handler | Message, description, failing line, Details, and its buttons, announced as it opens | The debugger that Trace opens |
| Progress component | Each progress as an indicator with its message and Stop | Localized titles |
| Query editor (`QUERY`) | Criteria, fields, comparisons, values, buttons | Formula criteria on its second page, related tables' fields |
| Order By editor (`ORDER BY`) | Available and ordered fields, direction, Sort | Ordering by a formula end to end, related tables' fields |
| Formula editor (`EDIT FORMULA`, Order By's Add Formula…) | Lists, disclosure, menus, the formula, buttons | Load… and Save…'s files, routes from other commands |
| Quick Report editor (`QR REPORT`) | Toolbar, panels, fields, the report sheet as an editable table, context menus | Header and footer, the selected column and cell, totals' operators, destination options |
| Import, export, label and chart editors, 4D Write Pro, 4D View Pro | | Not examined |

Lists in 4D's own windows publish the lines they draw. Paging actions reach the rest.

## Never tested

- 4D Server with remote clients on other machines: one test connects a 4D client to 4D Server on the same Mac, and its forms without an area are published from the client's cached archive ([archived projects](validation/archived-projects-development.json)). Remote data volume, latency and clients on other Macs are untested.
- Windows: there is no implementation.
- Binary (`.4DB`) databases: the installer and the description of forms without an area read a project's source files, so a binary database must be converted to a project first. 4D's own windows, such as messages and editors, need only the plugin.
- Voice Control, Switch Control and Full Keyboard Access.
- Physical Intel Macs: Intel code runs only under Rosetta.
- macOS other than 26, 4D other than 20.8, localized 4D.
- Multiple displays.

## Cost to an application

A process that no assistive technology uses runs dormant: its forms do not poll and the providers do not run. [Performance and activation](PERFORMANCE.md) gives the measurements and the switch that controls it.
