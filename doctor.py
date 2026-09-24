#!/usr/bin/env python3
"""Read-only inventory for moving bridge development to another Mac.

This does not activate licenses, query their contents, or change permissions.
--require checks file/tool prerequisites, not runtime licensing or TCC approval.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import stat
import subprocess

ROOT = Path(__file__).resolve().parent
EXPECTED_4D = "20.8 build 20.102009"


def command(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return {"available": result.returncode == 0, "detail": result.stdout.strip()[:700]}
    except (OSError, subprocess.TimeoutExpired):
        return {"available": False, "detail": "Unavailable or timed out"}


def application(path, identifier):
    path = path.expanduser().resolve()
    try:
        info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
        version = info.get("CFBundleShortVersionString", "")
        return {"path": str(path), "present": True, "identifierMatches": info.get("CFBundleIdentifier") == identifier,
                "version": version, "matchesTestedVersion": version == EXPECTED_4D}
    except (OSError, ValueError, plistlib.InvalidFileException):
        return {"path": str(path), "present": False, "identifierMatches": False, "matchesTestedVersion": False}


def desktop_access():
    """Query existing grants only; never request consent or modify TCC."""
    report = {"scope": "Invoking process only; the external AX test app needs its own Accessibility grant"}
    if platform.system() != "Darwin":
        return {**report, "available": False}
    try:
        accessibility = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        accessibility.AXIsProcessTrusted.restype = ctypes.c_bool
        graphics = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        graphics.CGPreflightScreenCaptureAccess.restype = ctypes.c_bool
        return {**report, "available": True,
                "accessibilityTrusted": accessibility.AXIsProcessTrusted(),
                "screenCaptureAllowed": graphics.CGPreflightScreenCaptureAccess()}
    except (OSError, AttributeError):
        return {**report, "available": False}


def desktop_session():
    """Report only the invoking user's lock state and relevant setup settings."""
    report = {"unlocked": None, "restoreMachineState": None, "managedIdleSeconds": None}
    if platform.system() != "Darwin":
        return report
    try:
        data = subprocess.check_output(["/usr/sbin/ioreg", "-a", "-n", "Root", "-d1"], timeout=10)
        roots = plistlib.loads(data)
        if isinstance(roots, dict):
            roots = [roots]
        for root in roots:
            for session in root.get("IOConsoleUsers", []):
                if session.get("kCGSSessionUserIDKey") == os.getuid() and session.get("kCGSSessionOnConsoleKey"):
                    report["unlocked"] = not session.get("CGSSessionScreenIsLocked", False)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    for path, source_key, result_key in [
        ("/Library/Preferences/com.apple.RemoteManagement.plist", "RestoreMachineState", "restoreMachineState"),
        ("/Library/Managed Preferences/com.apple.screensaver.plist", "idleTime", "managedIdleSeconds"),
    ]:
        try:
            report[result_key] = plistlib.loads(Path(path).read_bytes()).get(source_key)
        except (OSError, ValueError):
            pass
    return report


def external_ax_client():
    installed = Path.home() / "Applications/AXB Fixture Tests.app"
    binary = Path("Contents/MacOS/AXFixtureTests")
    built = ROOT / "build/AXB Fixture Tests.app"
    try:
        installed_hash = hashlib.sha256((installed / binary).read_bytes()).hexdigest()
    except OSError:
        installed_hash = None
    try:
        built_hash = hashlib.sha256((built / binary).read_bytes()).hexdigest()
    except OSError:
        built_hash = None
    return {"path": str(installed), "executablePresent": installed_hash is not None,
            "matchesLocalBuild": installed_hash == built_hash if installed_hash and built_hash else None,
            "accessibilityGrant": "Verify by running the installed app through LaunchServices with --no-build"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path("/Applications/4D/4D.app"))
    parser.add_argument("--server", type=Path, default=Path.home() / "Applications/4D Server 20.8 Dev.app")
    parser.add_argument("--alp", type=Path, help="AreaList Pro bundle to use in the fixture")
    parser.add_argument("--require", choices=("none", "build", "fixture"), default="none")
    args = parser.parse_args()
    staged_alp = Path.home() / "Library/Application Support/4D Accessibility Bridge/Dependencies/ALP.bundle"
    candidates = [args.alp] if args.alp else [ROOT / "fixture/Plugins/ALP.bundle", staged_alp]
    alp = next((p.expanduser().resolve() for p in candidates if p and (p.expanduser() / "Contents/Info.plist").is_file()), None)
    alp_info = {}
    if alp:
        alp_info = plistlib.loads((alp / "Contents/Info.plist").read_bytes())
    license_file = ROOT / "fixture/Resources/alp.license"
    license_present = license_file.is_file() and not license_file.is_symlink()
    protected = license_present and stat.S_IMODE(license_file.stat().st_mode) == 0o600
    clang = command(["xcrun", "clang++", "--version"])
    sdk = command(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    client = application(args.client, "com.4D.4D")
    server = application(args.server, "com.4D.4DServer")
    native_ready = platform.system() == "Darwin" and clang["available"] and sdk["available"] and bool(shutil.which("codesign"))
    fixture_ready = native_ready and client["identifierMatches"] and server["identifierMatches"] and client["matchesTestedVersion"] and server["matchesTestedVersion"] and alp_info.get("CFBundleExecutable") == "ALP" and protected
    report = {
        "platform": platform.platform(), "architecture": platform.machine(), "python": platform.python_version(),
        "compiler": clang, "sdk": sdk, "client": client, "server": server,
        "areaList": {"path": str(alp) if alp else None, "present": alp is not None,
                     "version": alp_info.get("CFBundleShortVersionString"), "executableMatches": alp_info.get("CFBundleExecutable") == "ALP"},
        "areaListLicense": {"present": license_present, "mode0600": protected, "registrationVerified": False},
        "desktopAccess": desktop_access(), "desktopSession": desktop_session(), "externalAXClient": external_ax_client(),
        "nativeBuildPrerequisites": bool(native_ready), "fixtureFilePrerequisites": bool(fixture_ready),
        "manualChecks": ["Verify Developer Professional and Server execution on this Mac; file presence does not establish licensing.",
                         "Run the fixture and require AL_Register result 0 and the intended Is compiled mode result.",
                         "Reuse the installed AXB Fixture Tests.app with --no-build through LaunchServices; request Accessibility approval only if its permission check fails."]
    }
    print(json.dumps(report, indent=2))
    if args.require == "build" and not native_ready or args.require == "fixture" and not fixture_ready:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
