# Picture-based controls

4D draws button grids, picture buttons, picture popup menus and spinners from pictures, with no text of their own.

- **Button grid**: a group, labeled by its help tip or configured label, containing one button per cell. 4D divides the object evenly into its columns and rows and numbers cells row by row. A press is an ordinary click at the cell's center, so the grid's own On Clicked runs with that cell's value. Name the cells in configuration; otherwise each is numbered after the grid and the grid reports `missingLabel`:

  ```4d
  $options.controls.Align:=New object("cells"; New collection("Left"; "Center"; "Right"))
  ```

  `cells` must list one non-empty label per cell, in 4D's cell order; any other value reports `invalidControlCells`.
- **Picture button**: a button, labeled by its title, help tip or configuration. A press advances its picture through its On Clicked.
- **Spinner**: a progress indicator labeled by its help tip.
- **Picture popup menu**: a popup, labeled by its help tip or configured label, whose value is the chosen cell's label. Name the cells with `cells`, as for a button grid; otherwise each is numbered after the control and it reports `missingLabel`. 4D's own palette is a menu holding one unlabeled picture, with no keyboard navigation. Pressing the popup through accessibility therefore opens a native menu of the cell labels instead, with the current cell checked and highlighted. Choosing one clicks the control, which opens 4D's palette, and the plugin selects that cell in it. 4D then sets the value and runs the control's own On Clicked. The palette appears briefly while that happens. Mouse clicks are unchanged.
- **Splitter**: published and adjustable; see [splitters](SPLITTERS.md).

## Test

```sh
python3 test_picture_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_picture_fixture.py --server /path/to/4D\ Server.app --run
python3 test_picture_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_picture_fixture.py` builds an area-owned form with a configured 3-by-1 grid, an unlabeled 2-by-2 grid, a picture button, a spinner, a configured picture popup menu and a splitter, each recording its events with its value. The AX run checks roles, labels, cell order and layout, stable paths, presses through each control's own On Clicked, choosing a picture popup cell from its menu, and an unchanged form against a plugin-free baseline (the animated spinner excluded). The VoiceOver run reads the grid as a group, moves between cells and presses one with VO-Space. It then opens the picture popup with VO-Space, moves to its last cell with the arrow keys and chooses it with Return. Add `--compiled` or `--intel` for the other modes.
