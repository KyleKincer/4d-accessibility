#!/usr/bin/env python3
"""Package matching build outputs; optionally sign and notarize downloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

from build_component import verify_package

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def archive(folder, target):
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as output:
        for path in sorted(folder.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Unexpected package symlink: {path}")
            if path.is_file():
                output.write(path, path.relative_to(folder))


def verify_inputs():
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid VERSION")
    native = json.loads((BUILD / "build-report.json").read_text())
    component = json.loads((BUILD / "component-build-report.json").read_text())
    plugin = BUILD / "AccessibilityBridge.bundle"
    package = BUILD / "AccessibilityBridge.4dbase"
    verify_package(package)
    info = plistlib.loads((plugin / "Contents/Info.plist").read_bytes())
    if not component.get("passed") or native["version"] != version or component["version"] != version or info["CFBundleVersion"] != version:
        raise ValueError("Build outputs do not match VERSION")
    binary = plugin / "Contents/MacOS/AccessibilityBridge"
    if sha(binary) != native["binary_sha256"] or sha(binary) != component["native_sha256"]:
        raise ValueError("Native build differs from the component's dependency")
    architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise ValueError("Native plugin must contain both supported architectures")
    for report in [native, component]:
        for relative, digest in report["sources_sha256"].items():
            if sha(ROOT / relative) != digest:
                raise ValueError(f"Source changed since build: {relative}")
    for relative, digest in component["package_sha256"].items():
        if sha(package / relative) != digest:
            raise ValueError(f"Component changed since build: {relative}")
    return version, plugin, package


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign", help="Developer ID Application identity; requires --keychain and --notary-profile")
    parser.add_argument("--keychain", type=Path)
    parser.add_argument("--notary-profile")
    args = parser.parse_args()
    if any([args.sign, args.keychain, args.notary_profile]) and not all([args.sign, args.keychain, args.notary_profile]):
        parser.error("Signing requires all three signing options")
    version, plugin, component = verify_inputs()
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-", dir=BUILD) as temporary:
        stage = Path(temporary)
        kit = stage / "kit"
        kit.mkdir()
        shutil.copytree(plugin, kit / "Plugins/AccessibilityBridge.bundle")
        shutil.copytree(component, kit / "Components/AccessibilityBridge.4dbase")
        for folder in ["host", "skills"]:
            shutil.copytree(ROOT / folder, kit / folder, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        for name in ["install_host_methods.py", "inspect_ax.py", "inventory_forms.py", "LICENSE", "VERSION"]:
            shutil.copy2(ROOT / name, kit / name)
        (kit / "tests").mkdir()
        shutil.copy2(ROOT / "tests/mac_ax.py", kit / "tests/mac_ax.py")
        notices = kit / "Components/AccessibilityBridge.4dbase/Resources"
        notices.mkdir(exist_ok=True)
        shutil.copy2(ROOT / "LICENSE", notices / "LICENSE")
        shutil.copy2(ROOT / "vendor/4DPluginAPI/LICENSE.md", kit / "4D-SDK-LICENSE.md")
        (kit / "README.md").write_text(
            f"# 4D Accessibility {version}\n\n"
            "Read `skills/4d-accessibility/references/STATUS.md` before adopting this development preview.\n\n"
            "1. Close the entire 4D host. Copy the included `Plugins/AccessibilityBridge.bundle` and "
            "`Components/AccessibilityBridge.4dbase` beside your application's `Project` folder.\n"
            "2. Run `python3 install_host_methods.py --project-dir /path/to/MyApp/Project`. Add `--area-list` for AreaList Pro. "
            "Use the same `--compiler-method` as earlier installations.\n"
            "3. Reopen 4D and follow `skills/4d-accessibility/references/INTEGRATION.md` for form hooks and live validation.\n\n"
            + ("Developer ID signed and submitted for notarization by the release workflow.\n" if args.sign else
               "Development build: ad hoc signed, not notarized. Do not treat this artifact as a production release.\n"))
        if args.sign:
            for path in [kit / "Components/AccessibilityBridge.4dbase/Libraries/lib4d-arm64.dylib", kit / "Plugins/AccessibilityBridge.bundle"]:
                run("codesign", "--force", "--timestamp", "--options", "runtime", "--keychain", args.keychain, "--sign", args.sign, path)
                run("codesign", "--verify", "--strict", path)
        manifest = {
            "version": version, "architectures": ["arm64", "x86_64"],
            "signing": "Developer ID" if args.sign else "ad hoc; not notarized",
            "files": {str(p.relative_to(kit)): sha(p) for p in sorted(kit.rglob("*")) if p.is_file()},
        }
        (kit / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        full = dist / f"4d-accessibility-{version}-macos.zip"
        component_zip = dist / "4d-accessibility.zip"
        archive(kit, full)
        archive(kit / "Components", component_zip)
        outputs = [full, component_zip]
        if args.sign:
            dmg = dist / f"4d-accessibility-{version}-macos.dmg"
            run("hdiutil", "create", "-ov", "-format", "UDZO", "-volname", "4D Accessibility", "-srcfolder", kit, dmg)
            run("codesign", "--timestamp", "--keychain", args.keychain, "--sign", args.sign, dmg)
            for path in [full, component_zip, dmg]:
                result = subprocess.run(["xcrun", "notarytool", "submit", str(path), "--keychain-profile", args.notary_profile,
                                         "--keychain", str(args.keychain), "--wait", "--timeout", "20m", "--output-format", "json"], check=True, capture_output=True, text=True)
                response = json.loads(result.stdout)
                if response.get("status") != "Accepted":
                    raise RuntimeError(f"Notarization rejected {path.name}: {response.get('id')}")
            run("xcrun", "stapler", "staple", dmg)
            run("xcrun", "stapler", "validate", dmg)
            outputs.append(dmg)
        (dist / "SHA256SUMS").write_text("".join(f"{sha(p)}  {p.name}\n" for p in outputs))
    print(f"Packaged {len(outputs)} downloads in {dist}")


if __name__ == "__main__":
    main()
