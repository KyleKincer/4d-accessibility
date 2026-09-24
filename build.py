#!/usr/bin/env python3
"""Build the native plugin; deployment requires an explicit fixture-only flag."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
BUILD = ROOT / "build"
SDK = ROOT / "vendor" / "4DPluginAPI"
BUNDLE = BUILD / "AccessibilityBridge.bundle"
VERSION = (ROOT / "VERSION").read_text().strip()


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-fixture", action="store_true", help="Install only into the disposable fixture; requires 4D to be closed")
    parser.add_argument("--alp", type=pathlib.Path, help="Local licensed AreaList Pro bundle to copy into the fixture; requires --install-fixture")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", VERSION):
        parser.error("VERSION must contain a numeric three-part version")
    if args.alp and not args.install_fixture:
        parser.error("--alp requires --install-fixture")
    if args.install_fixture:
        processes = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True, check=True).stdout.splitlines()
        if any(line.rstrip().endswith("/4D.app/Contents/MacOS/4D") for line in processes):
            parser.error("Close 4D before installing. Closing and reopening only the project does not reliably reload native code.")
    BUILD.mkdir(exist_ok=True)
    if BUNDLE.is_symlink():
        parser.error("Build destination must not be a symlink")
    if BUNDLE.exists():
        shutil.rmtree(BUNDLE)
    (BUNDLE / "Contents/MacOS").mkdir(parents=True)
    (BUNDLE / "Contents/Resources").mkdir()
    binaries = []
    for arch in ("arm64", "x86_64"):
        common = ["-arch", arch, "-mmacosx-version-min=11.0", "-g", "-O1", "-fvisibility=hidden", "-I", SDK]
        run("xcrun", "clang", *common, "-std=c11", "-c", SDK / "4DPluginAPI.c", "-o", BUILD / f"sdk-{arch}.o")
        objects = []
        for source in ("Plugin", "Session", "Grid", "Bridge", "GridNative"):
            obj = BUILD / f"{source}-{arch}.o"
            run("xcrun", "clang++", *common, "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", f'-DAXB_VERSION="{VERSION}"', "-c", ROOT / "src" / f"{source}.mm", "-o", obj)
            objects.append(obj)
        binary = BUILD / f"AccessibilityBridge-{arch}"
        run("xcrun", "clang++", "-arch", arch, "-mmacosx-version-min=11.0", "-bundle", BUILD / f"sdk-{arch}.o", *objects, "-framework", "Cocoa", "-framework", "CoreGraphics", "-o", binary)
        binaries.append(binary)
    executable = BUNDLE / "Contents/MacOS/AccessibilityBridge"
    run("xcrun", "lipo", "-create", *binaries, "-output", executable)
    info = {
        "CFBundleExecutable": "AccessibilityBridge",
        "CFBundleIdentifier": "io.github.kylekincer.4d-accessibility",
        "CFBundlePackageType": "4DCB",
        "CFBundleSignature": "4D20",
        "CFBundleVersion": VERSION,
        "CFBundleShortVersionString": VERSION,
        "CFBundleDevelopmentRegion": "en",
    }
    (BUNDLE / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    shutil.copy2(ROOT / "manifest.json", BUNDLE / "Contents/Resources/manifest.json")
    shutil.copytree(ROOT / "resources/en.lproj", BUNDLE / "Contents/Resources/en.lproj")
    run("codesign", "--force", "--sign", "-", BUNDLE)
    run("codesign", "--verify", "--strict", BUNDLE)
    sources = sorted((ROOT / "src").glob("*")) + sorted((ROOT / "host/Methods").glob("*.4dm")) + sorted((ROOT / "resources/en.lproj").glob("*")) + [ROOT / "manifest.json", ROOT / "VERSION"]
    report = {
        "version": VERSION,
        "architectures": ["arm64", "x86_64"],
        "signing": "ad hoc, verified; not notarized",
        "binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "sources_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
    }
    (BUILD / "build-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Built and signature-verified: {BUNDLE}")
    if args.install_fixture:
        for directory in ("Resources", "Data"):
            (ROOT / "fixture" / directory).mkdir(parents=True, exist_ok=True)
        destination = ROOT / "fixture/Plugins" / BUNDLE.name
        if destination.is_symlink():
            parser.error("Fixture destination must not be a symlink")
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(BUNDLE, destination)
        for source in (ROOT / "host/Methods").glob("*.4dm"):
            shutil.copy2(source, ROOT / "fixture/Project/Sources/Methods" / source.name)
        if args.alp:
            alp = args.alp.resolve()
            metadata = plistlib.loads((alp / "Contents/Info.plist").read_bytes())
            if metadata.get("CFBundleExecutable") != "ALP":
                parser.error("--alp must identify the actual AreaList Pro bundle")
            target = destination.parent / "ALP.bundle"
            if target.is_symlink():
                parser.error("AreaList fixture destination must not be a symlink")
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(alp, target)
        print(f"Installed into disposable fixture: {destination}")


if __name__ == "__main__":
    main()
