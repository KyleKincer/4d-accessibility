# Maintain the tab adapter

Read [tab integration and coverage](../skills/4d-accessibility/references/TABS.md) for the application contract. This document covers native geometry and reproducible acceptance.

## Native geometry and behavior

The plugin observes public AppKit cell drawing without changing its arguments or output. This supplies the actual unequal segment widths and the compact presentation. It uses no private 4D class or selector. Worker-thread drawing queues immutable geometry; window traversal and reads occur on the main thread. Cached paint has a weak reference to its original canvas and cannot describe a detached replacement. Popup traffic has a separate cache budget so grid repainting cannot evict tab strips. Real AppKit controls retain their native accessibility. The shared helper accounts for 4D's canvas scrolling through the existing subform offsets, so revealing a choice keeps its AX identity and uses its actual visible position.

An intentional restart within the same captured area lifetime can transfer unchanged painted geometry. This matters because 4D can display a cached canvas without drawing its cells again. The transfer requires the same source signature and dimensions, happens once per paint claim, and grants no access while registration is inactive. Ordinary teardown and database shutdown discard the cache. Every old AX element still retires on restart. Applications need no new restart hook.

Tab activation uses the same guarded native mouse delivery as ordinary buttons. VoiceOver selection feedback follows a completed action with changed selection. Dispatch acknowledgement can arrive first; feedback waits briefly for the matching selected value. If page navigation moves focus into an editor, the editor's focus announcement takes precedence. When the whole tab control has zero width or height, it leaves the tree while the rest of the form remains accessible.

Unpainted, ambiguous or unsupported layouts report an entry in the form diagnostics' `.issues` rather than guessed clickable rectangles. `nativeTabLayoutUnavailable` requires the matching native plugin advertising `tabs 1`. `nativeTabLayoutPending` means there is not yet a matching painted layout. `nativeTabOverflowPending` needs further adapter work for that layout. Read [current status](../skills/4d-accessibility/references/STATUS.md) before claiming a whole form accessible.

## Run the acceptance cases

Build the plugin and component using [the build guide](../CONTRIBUTING.md). Prepare and run each fixture sequentially:

```sh
python3 prepare_tabs_fixture.py --server /path/to/4D\ Server.app
python3 test_tabs_fixture.py --run
python3 test_tabs_fixture.py --run --compiled --voiceover
```

Prepare again with `--dynamic` for a generated root, `--narrow` for a compact array control, or `--icons` for list item pictures. `--scroll-icons` supplies twelve icon-bearing choices in a small control; the test follows the presentation 4D actually renders. `--clipped-children` tests tab reveal through a scrolling subform. Object-backed and list-backed compact controls are present in every fixture. The driver checks actual runtime mode and package hashes before sending input. It verifies selected data and original handler counts separately from AX transport responses. Reports and failed-run images stay under ignored `build/`.

`python3 test_tabs_matrix.py --server /path/to/4D\ Server.app --run` runs [the acceptance cases](../test_tabs_matrix.py) sequentially in interpreted 4D and compiled 4D with VoiceOver. It preserves each matching compiler and runtime report and rejects source changes during acceptance. Review its results before updating a host's kit.

After preparing the normal fixture, `python3 test_tabs_fixture.py --run --restart-only` runs the short recovery regression. The full matrix restarts each tabbed form twice after its ordinary editing and presentation tests. Recovery must preserve bindings and business handlers while retiring the previous tree.

`python3 test_tabs_pixels.py --server /path/to/4D\ Server.app --run` compares the complete compiled window against a baseline with no plugin, component or bridge helpers. It also accepts `--narrow` and `--icons`. It requires Pillow and accepts no changed pixels, masks or tolerance. The native provider suite separately checks drawing preservation, normal AppKit controls, shutdown, database reopen and coexistence with another drawing observer.
