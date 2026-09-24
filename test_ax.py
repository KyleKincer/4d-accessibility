#!/usr/bin/env python3
"""Exercise only the open disposable 4D fixture through macOS AX APIs."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--run", action="store_true", help="Exercise a fresh disposable fixture; requires Accessibility permission")
parser.add_argument("--no-build", action="store_true", help="Reuse the exact signed executable approved in System Settings")
parser.add_argument("--app", type=Path, help="Run an installed copy of the approved test app; requires --no-build")
parser.add_argument("--expect-mode", choices=("interpreted", "compiled"), help="Require the running fixture to report this execution mode")
parser.add_argument("--expect-component", action="store_true", help="Require a compiled component in the fixture diagnostics")
parser.add_argument("--suite", choices=("standalone", "component", "invoice"), help="Name the fixture family when retaining mode-specific reports")
parser.add_argument("--via-host", action="store_true", help="Run under the invoking agent/terminal Accessibility grant instead of LaunchServices")
args = parser.parse_args()
if args.app and not args.no_build:
    parser.error("--app requires --no-build; build and review a new app separately")
(root / "build").mkdir(exist_ok=True)
bundle = args.app.resolve() if args.app else root / "build/AXB Fixture Tests.app"
binary = bundle / "Contents/MacOS/AXFixtureTests"
if not args.no_build:
    binary.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
    "xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
    str(root / "tests/AXFixtureTests.mm"), "-framework", "AppKit", "-framework", "ApplicationServices",
    "-o", str(binary),
    ], check=True)
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "io.github.kylekincer.4d-accessibility.tests",
        "CFBundleName": "AXB Fixture Tests",
        "CFBundleExecutable": "AXFixtureTests",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "LSUIElement": True,
    }))
    subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
if not binary.is_file():
    parser.error("Build the test application before using --no-build")
print(f"External AX test app: {bundle}")
print("--run requires permission and a fresh disposable fixture.")
if args.run:
    metadata = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    if metadata.get("CFBundleIdentifier") != "io.github.kylekincer.4d-accessibility.tests":
        parser.error("The selected app is not the fixture test client")
    report_file = root / "build/external-ax-result.json"
    report_file.write_text(json.dumps({"passed": False, "state": "running", "expectedMode": args.expect_mode}) + "\n")
    # LaunchServices attributes TCC permission to the approved app bundle.
    # Directly spawning its Mach-O executable can inherit the terminal's identity.
    with tempfile.TemporaryDirectory(prefix="external-ax-", dir=root / "build") as directory:
        stdout, stderr = Path(directory) / "stdout", Path(directory) / "stderr"
        stdout.touch(); stderr.touch()
        failure = ""
        try:
            if args.via_host:
                with stdout.open("w") as out, stderr.open("w") as err:
                    launched = subprocess.run([str(binary), "--exercise-fixture"], stdout=out, stderr=err, timeout=45)
            else:
                launched = subprocess.run(["/usr/bin/open", "-n", "-g", "-W", "--stdout", str(stdout), "--stderr", str(stderr), str(bundle), "--args", "--exercise-fixture"], timeout=45)
            if launched.returncode:
                launcher = "External AX client" if args.via_host else "LaunchServices"
                failure = f"FAIL: {launcher} exited {launched.returncode}\n"
        except subprocess.TimeoutExpired:
            failure = "FAIL: external AX test exceeded its 45-second deadline\n"
        output = stdout.read_text() + stderr.read_text()
        output += failure
    # open's exit status covers launching, not the test process's exit status.
    passed = "PASS: external AX integration, without coordinate input" in output and "FAIL:" not in output
    if args.expect_mode:
        mode_matches = re.search(r"; 4D mode: " + args.expect_mode + r"(?:;|\n)", output) is not None
        if not mode_matches:
            output += f"FAIL: fixture did not confirm expected {args.expect_mode} mode\n"
        passed = passed and mode_matches
    if args.expect_component:
        component_matches = "; component mode: compiled\n" in output
        if not component_matches:
            output += "FAIL: fixture did not confirm compiled component execution\n"
        passed = passed and component_matches
    if args.suite == "invoice":
        resources = root / "build/invoice-fixture/Resources"
        try:
            checks = json.loads((resources / "adapter-checks.json").read_text(encoding="utf-8-sig"))
            clean = checks.get("passed") is True and bool(checks.get("checks"))
            clean = clean and all(check.get("passed") is True and check.get("vendorError") == 0 for check in checks["checks"])
            if args.expect_mode:
                clean = clean and checks.get("compiled") is (args.expect_mode == "compiled")
            clean = clean and not (resources / "vendor-error.json").exists()
        except (OSError, ValueError, TypeError, KeyError):
            clean = False
        if not clean:
            output += "FAIL: invoice adapter checks or AreaList vendor-error audit failed\n"
        passed = passed and clean
    print(output, end="")
    (root / "build/external-ax-report.txt").write_text(output)
    if args.expect_mode:
        suite = args.suite or ("component" if args.expect_component else "standalone")
        family = "" if suite == "standalone" else suite + "-"
        (root / f"build/external-ax-{family}{args.expect_mode}-report.txt").write_text(output)
    report_file.write_text(json.dumps({
        "passed": passed, "state": "finished", "expectedMode": args.expect_mode, "expectedCompiledComponent": args.expect_component, "suite": args.suite,
        "permissionHost": "invoking-agent-or-terminal" if args.via_host else "test-app",
        "testBinarySha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "reportSha256": hashlib.sha256(output.encode()).hexdigest(),
    }, indent=2) + "\n")
    raise SystemExit(0 if passed else 1)
