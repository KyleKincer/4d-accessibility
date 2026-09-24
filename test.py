#!/usr/bin/env python3
"""Run action-state tests with a selected sanitizer and a bounded runtime."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--sanitizer", choices=["none", "undefined", "address", "thread"], default="undefined")
parser.add_argument("--compiler", type=Path, help="Optional compiler path, for testing with another installed toolchain")
args = parser.parse_args()
build = root / "build"
build.mkdir(exist_ok=True)
binary = build / "SessionTests"
sdk = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], check=True, capture_output=True, text=True).stdout.strip()
subprocess.run([
    *([str(args.compiler)] if args.compiler else ["xcrun", "clang++"]),
    "-isysroot", sdk, "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
    *([] if args.sanitizer == "none" else [f"-fsanitize={args.sanitizer}"]),
    *(["-fno-sanitize-recover=all"] if args.sanitizer == "undefined" else []),
    "-fno-omit-frame-pointer", "-g", "-I", str(root / "src"),
    str(root / "src/Session.mm"), str(root / "src/Grid.mm"), str(root / "tests/SessionTests.mm"),
    "-framework", "Foundation", "-o", str(binary),
], check=True)
subprocess.run([str(binary)], check=True, timeout=30)
