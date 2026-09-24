#!/usr/bin/env python3
"""Test the logical grid model and asynchronous values without opening a UI."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
binary = root / "build/GridTests"
binary.parent.mkdir(exist_ok=True)
subprocess.run([
    "xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
    "-fsanitize=undefined", "-fno-sanitize-recover=all", "-g", "-I", str(root / "src"),
    str(root / "src/Grid.mm"), str(root / "src/Session.mm"), str(root / "tests/GridTests.mm"),
    "-framework", "Foundation", "-o", str(binary),
], check=True)
subprocess.run([str(binary)], check=True, timeout=60)
