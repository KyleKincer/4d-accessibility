#!/usr/bin/env python3
"""Build native provider tests. --run requires an unlocked interactive desktop."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--run", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parent
(root / "build").mkdir(exist_ok=True)
binary = root / "build/NativeProviderTests"
subprocess.run([
    "xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
    "-include", str(root / "tests/NotificationProbe.h"),
    "-I", str(root / "src"), str(root / "tests/NativeProviderTests.mm"),
    str(root / "src/Session.mm"), str(root / "src/Grid.mm"), str(root / "src/Bridge.mm"), str(root / "src/GridNative.mm"), str(root / "src/NativeLayout.mm"),
    str(root / "src/DrawnText.mm"), str(root / "src/InternalForms.mm"), str(root / "src/InternalTable.mm"), str(root / "src/MessageDialogs.mm"), str(root / "src/ProgressWindows.mm"), str(root / "src/QueryEditor.mm"), str(root / "src/QuickReport.mm"), str(root / "src/OrderByEditor.mm"), str(root / "src/GenericForms.mm"), "-framework", "CoreText", "-framework", "QuartzCore", "-lz",
    "-framework", "Cocoa", "-o", str(binary),
], check=True)
print("Built native provider tests; an unlocked desktop is required to run them.")
if args.run:
    # A component archive (.4DZ is a zip) holding one deflated and one stored form definition.
    import json, os, zipfile
    archive = root / "build/native-test-component.4DZ"
    with zipfile.ZipFile(archive, "w") as zip:
        zip.writestr(zipfile.ZipInfo("Project/Sources/Forms/Picker/form.4DForm"), "\ufeff" + json.dumps({"pages": [None, {"objects": {"go": {"type": "button", "text": "Go"}}}]}),
                     compress_type=zipfile.ZIP_DEFLATED)
        zip.writestr(zipfile.ZipInfo("Project/Sources/Forms/Plain/form.4DForm"), json.dumps({"pages": [None, {"objects": {"note": {"type": "text", "text": "Note"}}}]}),
                     compress_type=zipfile.ZIP_STORED)
        zip.writestr("Project/Sources/Methods/Other.4dm", "// not a form")
    subprocess.run([str(binary)], check=True, timeout=45, env={**os.environ, "AXB_TEST_COMPONENT_ARCHIVE": str(archive)})
