#!/usr/bin/env python3
"""Publish visible grouped-break native input prerequisites."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import unittest
from datetime import datetime, timezone

from build_component import BUILD, ROOT, sha
from summarize_grouped_probe import validate_sources


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def cell(state, row, column):
    return next(c for c in state["afterGroup"]["coordinates"] if c["row"] == row and c["column"] == column)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=BUILD / "grouped-native-inputs.json")
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    record = {"passed": False, "date": datetime.now(timezone.utc).isoformat()}
    output.write_text(json.dumps(record) + "\n")
    try:
        compiled_path, compiled = validate_sources(ROOT, BUILD)
        suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_hierarchy_probe_cleanup.py")
        result = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
        assert result.wasSuccessful() and result.testsRun == 7
        suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_hierarchy_probe_inputs.py")
        result = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
        assert result.wasSuccessful() and result.testsRun == 2
        record.update({
            "scope": "Visible synthetic later/nested grouped breaks, center clicks followed by native keyboard disclosure. No production adapter, VoiceOver or Symphony hierarchy acceptance.",
            "sourceBaseCommit": compiled["sourceCommit"],
            "driverSHA256": sha(ROOT / "test_hierarchy_probe.py"),
            "preparerSHA256": compiled["preparerSHA256"],
            "summarySHA256": sha(Path(__file__)),
            "sourceValidatorSHA256": sha(ROOT / "summarize_grouped_probe.py"),
            "compileReportSHA256": sha(compiled_path),
            "preparedSourceSHA256": compiled["sources_sha256"],
            "diagnosticNativeSHA256": compiled.get("diagnosticNativeSHA256"),
            "cleanupRegression": {"passed": True, "checks": 7, "testSHA256": sha(ROOT / "tests/test_hierarchy_probe_cleanup.py")},
            "flagGuardRegression": {"passed": True, "checks": 2, "testSHA256": sha(ROOT / "tests/test_hierarchy_probe_inputs.py")},
            "limitations": [
                "Center clicking selects the intended break. Selection-preserving expansion and complete selected-row reporting remain unvalidated.",
                "Only visible later and nested breaks in the synthetic fixture are established. Arbitrary targets, offscreen reveal, clipping, action races and lazy loading remain separate work.",
                "Collapsed unrelated branches remain collapsed in sampled geometry; their latent descendant states were not independently reopened.",
                "Keyboard event row/column fields are not treated as authoritative target addresses.",
                "Host architecture is recorded; 4D process architecture was not independently sampled. Physical Intel and remote delivery remain unvalidated.",
                "Diagnostic binaries are not a production kit or notarized distribution."
            ],
            "runs": []
        })
        operations = ["nativeGroupClick", "laterRootRight", "nativeGroupClick", "laterNestedRight", "laterNestedLeft", "nativeGroupClick", "laterRootLeft"]
        for mode in ("interpreted", "compiled"):
            report_path = BUILD / ("hierarchy-input-probe-" + mode + ".json")
            report = json.loads(report_path.read_text())
            assert report["passed"] and report["compiled"] is (mode == "compiled")
            for field in ("driverSHA256", "preparerSHA256", "compileReportSHA256", "preparedSourceSHA256"):
                assert report[field] == record[field], field
            assert report["exitCode"] == 0 and report["closed"]["runId"] == report["runId"]
            assert not any(report.get(key) for key in ("failure", "finalError", "shutdownErrors"))
            assert len(report["checks"]) == 12
            if record["diagnosticNativeSHA256"]:
                assert report["uniqueMappedDiagnostic"] and report["diagnosticNativeSHA256"] == record["diagnosticNativeSHA256"]
            for probe in report["commandProbes"]:
                state = probe["state"]
                assert state["compiled"] is report["compiled"] and state["runId"] == report["runId"]
                assert state["beforeGroup"] == state["afterGroup"]
                assert state["groupSentinelBefore"] == state["groupSentinelAfter"] and state["groupSentinelBefore"]["ok"] == 0
            actions = [p for p in report["commandProbes"] if p["operation"] in set(operations)]
            assert [p["operation"] for p in actions] == operations
            reference = actions[0]["before"]
            targets = iter(((1, 6), (2, 6), (1, 6)))
            public = []
            for action in actions:
                before, after = action["before"], action["state"]
                for state in (before, after):
                    assert state["beforeA"] == reference["beforeA"] and state["beforeB"] == reference["beforeB"]
                    for field in ("levels", "keys", "control", "arrayLengths"):
                        assert state["afterGroup"][field] == reference["afterGroup"][field]
                events = after["events"][len(before["events"]):]
                if action["operation"] == "nativeGroupClick":
                    column, row = next(targets)
                    assert action["target"] == [column, row] and action["ownerVerified"]
                    sampled = cell(before, row, column)
                    assert sampled["positive"] and sampled["hit"] == [column, row]
                    l, t, r, b = sampled["screenFrame"]
                    assert action["point"] == [(l+r)/2, (t+b)/2]
                    wx, wy = report["window"]["position"]; ww, wh = report["window"]["size"]
                    assert wx <= action["point"][0] < wx+ww and wy <= action["point"][1] < wy+wh
                    clicks = [e for e in events if e["event"] == 4]
                    assert len(clicks) == 1 and clicks[0]["name"] == "Grouped" and clicks[0]["row"] == row and clicks[0]["column"] == column
                    assert not any(e["event"] in (43, 44) for e in events)
                    assert before["afterGroup"]["coordinates"] == after["afterGroup"]["coordinates"]
                else:
                    opened = action["operation"].endswith("Right")
                    column = 3 if "Nested" in action["operation"] else 2
                    disclosure = [e for e in events if e["event"] in (43, 44)]
                    assert len(disclosure) == 1 and disclosure[0]["name"] == "Grouped" and disclosure[0]["event"] == (43 if opened else 44)
                    for member in (6, 7):
                        assert cell(before, member, column)["positive"] is (not opened)
                        assert cell(after, member, column)["positive"] is opened
                        assert cell(before, member, column-1) == cell(after, member, column-1)
                        assert cell(after, member, column-1)["positive"]
                    for other in (1, 4, 8):
                        assert not cell(after, other, 2)["positive"]
                    assert before["focus"] == after["focus"] == "Grouped"
                public.append({
                    "operation": action["operation"], "events": events,
                    **{key: action[key] for key in ("target", "point", "ownerVerified") if key in action},
                    "beforeReadbackSHA256": digest(before), "afterReadbackSHA256": digest(after),
                    "beforeCoordinates": [c for c in before["afterGroup"]["coordinates"] if c["row"] in (1, 4, 6, 7, 8) and c["column"] <= 3],
                    "afterCoordinates": [c for c in after["afterGroup"]["coordinates"] if c["row"] in (1, 4, 6, 7, 8) and c["column"] <= 3],
                    "focusBefore": before["focus"], "focusAfter": after["focus"]
                })
            record["runs"].append({"mode": mode, "passed": True, "checks": report["checks"], "reportSHA256": sha(report_path), "hostEnvironment": report["environment"], "actualCompiledVerified": True, "ownedProcessExitedZero": True, "matchingCloseReceipt": True, "window": report["window"], "actions": public})
        record["totalChecks"] = 24
        record["newVisibleGroupInputChecks"] = 8
        record["passed"] = True
    except BaseException as error:
        record["failure"] = repr(error)
        raise
    finally:
        output.write_text(json.dumps(record, indent=2) + "\n")
    print("PASS: both modes, 24 native checks, 7 cleanup/2 flag regressions and matching sources")


if __name__ == "__main__":
    main()
