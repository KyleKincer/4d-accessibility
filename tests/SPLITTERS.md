# Splitters

A splitter is published as a splitter: vertical when it is taller than wide, labeled by its help tip or configuration (else "Splitter"). Its value is its position in the window (left edge for a vertical splitter, top for a horizontal one), within 0 and the window's width or height.

- **Increment and decrement** move it by one step, 10 points unless `controls.<name>.step` sets another positive number.
- **Writing a value** moves it to that position. VoiceOver adjusts splitters this way: VO-Right and VO-Left while interacting with it.

The bridge assigns the offset to the splitter, as 4D's own splitter handling does after a drag: the same limits apply and the same attached objects move or resize. 4D's drag tracker follows the physical pointer, so posted mouse events cannot drive it; consequently an accessibility adjustment does not run the splitter's On Clicked, which 4D sends at each step of a mouse drag. Do not rely on that event to persist a layout.

VoiceOver introduces the splitter as "collapsed on left", because 4D's panes are not grouped as a split view. The position itself is correct.

## Test

```sh
python3 test_splitter_fixture.py --server /path/to/4D\ Server.app --baseline
python3 test_splitter_fixture.py --server /path/to/4D\ Server.app --run
python3 test_splitter_fixture.py --server /path/to/4D\ Server.app --run --voiceover
```

`prepare_splitter_fixture.py` builds an area-owned form with a vertical splitter whose left pane resizes with it. The AX run checks role, orientation, label, range and an unchanged form, then increments, decrements, writes a position, writes the current position, and writes past the limit, checking the splitter and pane each time. The VoiceOver run reads the splitter, interacts with it and moves it with VO-Right and VO-Left. Add `--compiled` or `--intel` for the other modes.
