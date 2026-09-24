#!/usr/bin/env python3
"""Download the pinned public compiler; fail if upstream bytes change."""
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    config = json.loads((ROOT / "ci/tool4d.json").read_text())
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("The pinned compiler requires an Apple Silicon macOS runner")
    stage = ROOT / "build/toolchain"
    stage.mkdir(parents=True, exist_ok=True)
    archive = stage / "tool4d.tar.xz"
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != config["sha256"]:
        with urllib.request.urlopen(config["url"], timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != config["sha256"]:
            raise SystemExit("Compiler checksum changed; review and update the pin deliberately")
        archive.write_bytes(data)
    with tarfile.open(archive) as package:
        package.extractall(stage, filter="data")
    app = stage / "tool4d.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.tool" or info.get("CFBundleShortVersionString") != config["version"]:
        raise SystemExit("Compiler identity/version differs from the pin")
    print(app)


if __name__ == "__main__":
    main()
