#!/usr/bin/env python3
"""Compile typed and hierarchical dropdowns with existing handlers."""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import (
    BUILD,
    PACKAGE,
    ROOT,
    literal,
    project_at,
    run_utility,
    sha,
    verify_package,
)

FIXTURE = BUILD / "dropdown-controls-fixture"
TITLE = "AXB dropdown controls"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("dropdown-controls-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "DropdownControls")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    shutil.copytree(
        BUILD / "AccessibilityBridge.bundle",
        FIXTURE / "Plugins/AccessibilityBridge.bundle",
    )
    for source in (ROOT / "host/OptionalMethods").glob("*.4dm"):
        shutil.copy2(source, methods / source.name)
    (sources / "DatabaseMethods").mkdir()
    shutil.copy2(ROOT / "tests/4d/DropdownStartup.4dm", sources / "DatabaseMethods/onStartup.4dm")
    for name in ["DropdownError", "DropdownEvent", "DropdownForm", "Compiler_Dropdown"]:
        shutil.copy2(ROOT / "tests/4d" / (name + ".4dm"), methods / (name + ".4dm"))
    objects = {}
    definitions = [
        ("Numbers", "DropdownNumbers", "arrayNumber", {}),
        ("Integers", "DropdownIntegers", "arrayInteger", {}),
        ("Dates", "DropdownDates", "arrayDate", {}),
        ("Times", "DropdownTimes", "arrayTime", {}),
        ("ObjectChoice", "Form.objectChoice", "object", {}),
        ("NumberChoice", "Form.numberChoice", "object", {"numberFormat": "0.0"}),
        ("ValueChoice", "Form.valueChoice", "text", {"saveAs": "value"}),
        ("ReferenceChoice", "Form.referenceChoice", "integer", {"saveAs": "reference"}),
        ("Hierarchical", "DropdownHierarchy", "integer", {}),
        ("Placeholder", "Form.placeholder", "object", {}),
        ("Disabled", "Form.disabled", "object", {"enabled": False}),
        ("Unhandled", "Form.unhandled", "object", {}),
    ]
    for i, (name, binding, hint, extra) in enumerate(definitions):
        objects[name] = {"type": "dropdown", "dataSource": binding,
            "dataSourceTypeHint": hint, "left": 20, "top": 20 + i * 35,
            "width": 220, "height": 26, "method": "DropdownEvent",
            "events": ["onClick", "onDataChange"], **extra}
    objects["Note"] = {"type": "input", "dataSource": "Form.note", "left": 20,
        "top": 455, "width": 220, "height": 24}
    objects["Close"] = {"type": "button", "text": "Close", "action": "cancel",
        "left": 265, "top": 455, "width": 90, "height": 28}
    form = sources / "Forms/Root"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(json.dumps({"windowTitle": TITLE,
        "width": 380, "height": 505, "method": "DropdownForm",
        "events": ["onLoad", "onTimer", "onUnload"], "pages": [None, {"objects": objects}]}, indent=2) + "\n")
    hashes = {
        str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()
    }
    with tempfile.TemporaryDirectory(
        prefix="dropdown-controls-compile-", dir=BUILD
    ) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(
            server / "Contents/MacOS" / info["CFBundleExecutable"],
            driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f"$options.plugins:=Folder({literal(FIXTURE / 'Plugins')})\n"
            f"$options.components:=New collection(File({literal(FIXTURE / 'Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ')}))\n"
            f"$result:=Compile project(File({literal(project)}); $options)",
            90,
        )
    report = {
        "passed": compiled.get("success") is True and not compiled.get("errors"),
        "compiler": compiled,
        "sources_sha256": hashes,
        "native_sha256": sha(
            FIXTURE
            / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
        ),
        "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
    }
    (BUILD / "dropdown-controls-compile-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(("PASS" if report["passed"] else "FAIL") + ": dropdown controls compilation")
    if not report["passed"]:
        print(compiled)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
