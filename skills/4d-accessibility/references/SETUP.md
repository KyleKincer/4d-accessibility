# Obtain and verify matching parts

The source repository is https://github.com/KyleKincer/4d-accessibility. The skill works when copied on its own, but its installer and binaries come from a matching checkout or release.

For a published release, download the complete versioned macOS kit from that repository's Releases page and verify `SHA256SUMS`. The component-only `4d-accessibility.zip` is for Dependency Manager; it still needs the plugin and host methods from the same release. Check current status before selecting a version. At this development checkpoint, there is no production release.

For source development:

```sh
git clone https://github.com/KyleKincer/4d-accessibility.git
cd 4d-accessibility
python3 build.py
python3 ci/download_tool4d.py
python3 build_component.py --tool4d build/toolchain/tool4d.app
```

The downloader uses a checksum-pinned public Apple Silicon tool4d. Builds need macOS, Xcode Command Line Tools and Python 3.12+. An Intel developer can instead build the component with `--server /path/to/4D\ Server.app` and an installed licensed 4D Server. Live 4D desktop tests need the desktop product and its appropriate license.

Copy `build/AccessibilityBridge.bundle` to the host's `Plugins`, and `build/AccessibilityBridge.4dbase` to `Components`. Both are siblings of `Project`. From the checkout or extracted kit, run `python3 install_host_methods.py --project-dir /path/to/MyApp/Project`, adding the documented options. Restart the entire 4D host after package changes.

In the host's normal debugger or development method:

```4d
var $info : Object
$info:=AXB_Host("info"; New object)
```

Require `ok=True`. See [the optional host API](OPTIONAL-HOST.md) when debugging dependency detection or dispatch. Compare `$info.componentInfo.version` and the version at the beginning of `$info.nativeStatus` with the kit's `VERSION`. `$info.componentInfo.compiled` must be True. Then start the actual form: startup checks the capabilities needed by the installed helpers. Matching version text alone is insufficient.

Host methods have a generated body-SHA marker. Run the matching installer again with the same options and compiler target to refresh/verify those sources. It refuses to overwrite unmarked or locally edited files. Keep application configuration outside generated helpers.

Record the source commit or release tag and the package manifest's hashes with validation. The SHA marker protects a generated file's contents; it is not a release number.
