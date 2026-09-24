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
    "-I", str(root / "src"), str(root / "tests/NativeProviderTests.mm"),
    str(root / "src/Session.mm"), str(root / "src/Grid.mm"), str(root / "src/Bridge.mm"), str(root / "src/GridNative.mm"),
    "-framework", "Cocoa", "-o", str(binary),
], check=True)
print("Built native provider tests; an unlocked desktop is required to run them.")
if args.run:
    subprocess.run([str(binary)], check=True, timeout=45)
