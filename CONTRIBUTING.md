# Build and test

Use Python 3.12 or newer, macOS and Xcode Command Line Tools. Source and generated fixtures use synthetic data. Install 4D and any vendor plugins separately for live tests.

```sh
python3 build.py
python3 build_component.py --tool4d /path/to/tool4d.app
```

Alternatively, use `--server /path/to/4D\ Server.app` with a licensed 4D Server. Run 4D compiler drivers sequentially. Build the native plugin before the component; the component compiler loads its commands. Outputs are `build/AccessibilityBridge.bundle` and `build/AccessibilityBridge.4dbase`. Local native builds are ad hoc signed.

The public CI toolchain is pinned in `ci/tool4d.json`. `python3 ci/download_tool4d.py` downloads the official archive, checks its SHA-256 and prints the application path. No 4D license or AreaList key is needed for this headless component build.

## Checks without a live 4D application

```sh
python3 test.py
python3 test_grids.py
python3 test_install_host_methods.py
python3 test_native.py
python3 ci/check_repository.py
```

`test_native.py` compiles the AppKit provider tests. Add `--run` only in an unlocked graphical session. Live fixture scripts also require 4D desktop and appropriate Accessibility permission. Screen recording is needed for visual/VoiceOver probes.

For example, after building the two packages:

```sh
python3 prepare_grid_fixture.py --server /path/to/4D\ Server.app --collection --cell-controls
python3 test_grid_controls_fixture.py --run
```

For native array identities, prepare with `prepare_grid_fixture.py --key-type integer` or `--key-type longint`, plus `--row-states --described`. Run `test_grid_fixture.py --run` and then `--compiled` to exercise both desktop modes. Keep the required `--server` argument when preparing.

For generated repeated/nested children sharing ordinary data, with parent-owned discovery:

```sh
python3 prepare_auto_subforms.py --generated-children --server /path/to/4D\ Server.app
python3 test_auto_subforms.py --run --launch
python3 test_auto_subforms.py --run --launch --compiled
```

The launcher verifies the project and window before sending input and closes only its disposable process. Compiled desktop execution needs the appropriate local 4D license.

Read each script's `--help` before choosing a case. Fixture preparers create disposable projects under ignored `build/`; run one 4D desktop fixture at a time. Synthetic AreaList tests accept `--area-list-plugin /path/to/ALP.bundle`. Use `--license-file /path/to/protected/alp.license` for an existing license file with mode 0600, or keep it in ignored `fixture/Resources/alp.license`. Add `--key-type integer` or `--key-type longint` to exercise existing numeric key arrays; `test_alp_grid_fixture.py --run --text bmp` tests supported text, while the default supplementary case remains a failing requirement. The vendor's license and redistribution terms remain separate.

For the independent AreaList supplementary Unicode crash, see the [bridge-free reproduction](tests/AREA-LIST-UNICODE.md). The adapter rejects these requests before mutation; ordinary native 4D text editing has separate Unicode coverage.

## Source ownership

`src/` contains the macOS provider and action/session model. `host/Methods` contains component methods and AreaList adapters; `host/OptionalMethods` contains the high-level host API. Edit canonical helpers, then reinstall them into test hosts with `install_host_methods.py`. The installer protects application-owned methods and modified generated files.

The full integration reference and examples live under `skills/4d-accessibility/references` so the agent skill can be installed as a self-contained folder. Update that source once. Build checks validate local links and the skill's required files.

When changing a control, test observable behavior against its ordinary native UI: ownership, focus, state, editor/handler callbacks and stale elements. Keep the [status](skills/4d-accessibility/references/STATUS.md) precise about failures and untested modes.
