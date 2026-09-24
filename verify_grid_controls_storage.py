#!/usr/bin/env python3
"""Reopen a copy of the synthetic entity fixture's data and verify widget saves."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from build_component import project_at, sha
from prepare_grid_fixture import BUILD


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--server", type=Path, required=True)
    args = parser.parse_args()
    fixture = args.fixture.resolve()
    assert fixture.is_relative_to(BUILD.resolve()), "Only owned synthetic build fixtures are accepted"
    config = json.loads((fixture / "Resources/launch.json").read_text())
    assert config["kind"] == "entity" and config["cellControls"]
    catalog = fixture / "Project/Sources/catalog.4DCatalog"
    assert {table.get("name") for table in ET.parse(catalog).getroot().findall("table")} == {"AXBGItem", "AXBGOther"}
    assert subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode != 0
    assert subprocess.run(["pgrep", "-x", "4D Server"], capture_output=True).returncode != 0
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.4D.4DServer"
    report = {"passed": False, "runId": config["runId"], "data_sha256": sha(fixture / "synthetic.4dd")}
    with tempfile.TemporaryDirectory(prefix="widget-storage-", dir=BUILD) as temporary:
        stage = Path(temporary)
        project = project_at(stage, "WidgetStorage")
        shutil.copy2(catalog, stage / "Project/Sources/catalog.4DCatalog")
        for source in fixture.glob("synthetic.*"):
            if source.is_file():
                shutil.copy2(source, stage / source.name)
        method = '''var $first; $far; $restricted; $result : Object
ON ERR CALL("StorageError")
$first:=ds.AXBGItem.get(1)
$restricted:=ds.AXBGItem.get(4)
$far:=ds.AXBGItem.get(600)
$result:=New object("first"; New object("approved"; $first.approved; "decision"; $first.decision; "mixed"; $first.mixed); "restricted"; $restricted.approved; "far"; $far.approved)
$result.passed:=($first.approved=False) & ($first.decision=True) & ($first.mixed=0) & ($restricted.approved=True) & ($far.approved=True)
File("/RESOURCES/storage.json").setText(JSON Stringify($result))
QUIT 4D
'''
        path = stage / "Project/Sources/Methods/StorageCheck.4dm"
        path.write_text(method)
        (stage / "Project/Sources/Methods/StorageError.4dm").write_text('File("/RESOURCES/storage.json").setText(JSON Stringify(New object("passed"; False; "error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
        report["reader_sha256"] = sha(path)
        with (BUILD / "grid-controls-storage.log").open("w") as log:
            result = subprocess.run([str(server / "Contents/MacOS" / info["CFBundleExecutable"]), "--project", str(project), "--data", str(stage / "synthetic.4dd"), "--headless", "--utility", "--skip-onstartup", "--startup-method", "StorageCheck", "--webadmin-auto-start", "false"], stdout=log, stderr=log, timeout=45)
        report["runtime"] = json.loads((stage / "Resources/storage.json").read_text(encoding="utf-8-sig"))
        report["passed"] = result.returncode == 0 and report["runtime"].get("passed") is True
    (BUILD / "grid-controls-storage-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(("PASS" if report["passed"] else "FAIL") + ": checkbox, popup, mixed, restricted-row and offscreen values persist after desktop close")
    assert report["passed"], report


if __name__ == "__main__":
    main()
