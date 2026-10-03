#!/usr/bin/env python3
"""Validate and publish the scoped grouped-state probe record."""

import argparse
import hashlib
import io
import json
import platform
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

from build_component import BUILD, ROOT, sha


def validate_sources(root, build):
    compiled_path = build / "hierarchy-probe-compile.json"
    compiled = json.loads(compiled_path.read_text())
    assert compiled["passed"] and compiled["compiler"]["success"] and not compiled["compiler"].get("errors")
    assert not compiled["changed_during_compile"]
    assert compiled["preparerSHA256"] == sha(root / "prepare_hierarchy_probe.py")
    fixture = build / "hierarchy-probe"
    for name, digest in compiled["sources_sha256"].items():
        assert sha(fixture / name) == digest, name
    canonical_names = {path.name for path in (root / "tests/4d").glob("AXHP_*.4dm")}
    prepared_names = {path.name for path in (fixture / "Project/Sources/Methods").glob("AXHP_*.4dm")}
    manifest_names = {Path(name).name for name in compiled["sources_sha256"] if Path(name).parent == Path("Project/Sources/Methods") and Path(name).name.startswith("AXHP_") and Path(name).suffix == ".4dm"}
    assert canonical_names == prepared_names == manifest_names, "Canonical, prepared and manifest AXHP methods differ"
    for source in (root / "tests/4d").glob("AXHP_*.4dm"):
        expected = source.read_text()
        if source.name == "AXHP_State.4dm" and compiled.get("diagnosticNativeSHA256"):
            expected = expected.replace("// Native probe result, when installed.", '$state.native:=JSON Parse(AXB Native layout(Current form window; "hierarchyProbe"))')
        assert (fixture / "Project/Sources/Methods" / source.name).read_text() == expected, source.name
    return compiled_path, compiled


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=BUILD / "grouped-hierarchy-state.json")
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    record = {"passed": False, "date": datetime.now(timezone.utc).isoformat()}
    output.write_text(json.dumps(record) + "\n")
    try:
        import PIL
        from PIL import Image, ImageChops

        compiled_path, compiled = validate_sources(ROOT, BUILD)

        suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_hierarchy_probe_cleanup.py")
        result = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
        assert result.wasSuccessful() and result.testsRun == 7
        record.update({
            "scope": "Native synthetic grouped-listbox state probes. No production adapter, hierarchy VoiceOver or Symphony hierarchy workflow acceptance.",
            "sourceBaseCommit": compiled["sourceCommit"],
            "driverSHA256": sha(ROOT / "test_hierarchy_probe.py"),
            "preparerSHA256": compiled["preparerSHA256"],
            "summarySHA256": sha(Path(__file__)),
            "compileReportSHA256": sha(compiled_path),
            "preparedSourceSHA256": compiled["sources_sha256"],
            "diagnosticNativeSHA256": compiled.get("diagnosticNativeSHA256"),
            "environment": {"macOS": platform.mac_ver()[0], "summaryPython": sys.version.split()[0], "pixelDecoder": "Pillow " + PIL.__version__},
            "cleanupRegression": {"passed": True, "checks": 7, "testSHA256": sha(ROOT / "tests/test_hierarchy_probe_cleanup.py")},
            "limitations": [
                "Equality applies to the sampled public getters, not every possible API.",
                "Host architecture is recorded; the 4D process architecture was not independently sampled. Physical Intel and remote/client-server behavior remain unvalidated.",
                "Blank backing data and an empty list do not establish loaded-empty or unloaded lazy branches.",
                "Identity through sorting, replacement, lazy loading and action races remains unvalidated.",
                "The expanded break/leaf comparison is a command-sequence observation; retained break highlight after expansion was not separately verified.",
                "Separate diagnostic binaries are not a production kit or notarized distribution."
            ],
            "runs": []
        })
        operations = ["groupCase", "groupCollapseAll", "groupSelectRoot", "groupSelectLaterBreak", "groupCase", "groupCollapseAll", "groupSelectRoot", "groupExpandAll", "groupSelectFirstLeaves", "groupCase", "groupCollapseNested", "groupCollapse", "groupExpand", "groupExpandNested", "groupCollapse", "groupExpand", "groupCase", "groupHideFirst", "groupShowAll", "groupCase", "groupCase"]
        for mode in ("interpreted", "compiled"):
            report_path = BUILD / ("hierarchy-probe-" + mode + ".json")
            report = json.loads(report_path.read_text())
            assert report["passed"] and report["compiled"] is (mode == "compiled")
            assert report["driverSHA256"] == record["driverSHA256"] and report["preparerSHA256"] == record["preparerSHA256"]
            assert report["compileReportSHA256"] == record["compileReportSHA256"]
            assert report["preparedSourceSHA256"] == record["preparedSourceSHA256"]
            assert report["exitCode"] == 0 and report["closed"]["runId"] == report["runId"]
            assert not any(report.get(key) for key in ("failure", "finalError", "shutdownErrors"))
            assert len(report["checks"]) == 13
            if record["diagnosticNativeSHA256"]:
                assert report["uniqueMappedDiagnostic"] and report["diagnosticNativeSHA256"] == record["diagnosticNativeSHA256"]
            for command in report["commandProbes"]:
                state = command["state"]
                assert state["compiled"] is report["compiled"] and state["runId"] == report["runId"]
                assert state["beforeGroup"] == state["afterGroup"]
                assert state["groupSentinelBefore"] == state["groupSentinelAfter"] and state["groupSentinelBefore"]["ok"] == 0
            grouped = report["groupedStates"]
            snapshots = grouped["snapshots"]
            assert [snapshot["operation"] for snapshot in snapshots] == operations
            assert snapshots[0]["payload"] == snapshots[4]["payload"] == snapshots[9]["payload"] == snapshots[16]["payload"] == {"name": "repeated"}
            assert snapshots[19]["payload"] == {"name": "placeholder"} and snapshots[20]["payload"] == {"name": "empty"}
            assert snapshots[1]["state"] == snapshots[2]["state"] == snapshots[3]["state"] == snapshots[5]["state"]
            assert snapshots[11]["state"] == snapshots[14]["state"]
            assert grouped["oppositeLatentChildStatesConfirmedByReopen"]
            for snapshot in snapshots:
                assert sha(BUILD / snapshot["image"]) == snapshot["imageSHA256"]
                capture = snapshot["capturedWindow"]
                assert capture["pidVerified"] and capture["title"] == "AX native hierarchy probe"
                assert capture["position"] == report["window"]["position"] and capture["size"] == report["window"]["size"]
            for label, first, second in (("baselineToFirst", 1, 2), ("baselineToLater", 1, 3), ("firstToLater", 2, 3), ("baselineToReset", 1, 5)):
                images = [Image.open(BUILD / snapshots[index]["image"]).convert("RGBA") for index in (first, second)]
                assert images[0].size == images[1].size
                pixels = grouped["selectionImages"][label]
                changed = sum(a != b for a, b in zip(images[0].get_flattened_data(), images[1].get_flattened_data()))
                assert changed == pixels["changedPixels"]
                bounds = ImageChops.difference(*images).convert("RGB").getbbox()
                assert (list(bounds) if bounds else None) == pixels["differenceBounds"]
                assert (changed == 0) is (label == "baselineToReset")
            public_grouped = {key: value for key, value in grouped.items() if key != "snapshots"}
            public_grouped["snapshots"] = []
            for snapshot in snapshots:
                state = snapshot["state"]
                public_state = {key: value for key, value in state.items() if key != "coordinates"}
                public_state["sampledCoordinates"] = [cell for cell in state["coordinates"] if (cell["row"], cell["column"]) in ((1, 1), (1, 2), (1, 3), (6, 1))]
                public_grouped["snapshots"].append({**{key: value for key, value in snapshot.items() if key != "state"},
                    "readbackSHA256": hashlib.sha256(json.dumps(state, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                    "state": public_state})
            record["runs"].append({"mode": mode, "passed": True, "checks": report["checks"], "reportSHA256": sha(report_path), "hostEnvironment": report["environment"], "actualCompiledVerified": True, "ownedProcessExitedZero": True, "matchingCloseReceipt": True, "window": report["window"], "groupedStates": public_grouped})
        record["totalChecks"] = 26
        record["newGroupedChecks"] = 10
        record["passed"] = True
    except BaseException as error:
        record["failure"] = repr(error)
        raise
    finally:
        output.write_text(json.dumps(record, indent=2) + "\n")
    print("PASS: both modes, 26 probe checks, 7 cleanup regressions and matching sources/images")


if __name__ == "__main__":
    main()
