#!/usr/bin/env python3
"""Publish source-matched native outline provider acceptance, without 4D claims."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def publish(root, output):
    record = {"passed": False, "date": datetime.now(timezone.utc).isoformat()}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record) + "\n")
    try:
        sources = sorted(str(p.relative_to(root)) for p in (root / "src").glob("*") if p.is_file()) + [
            "tests/NativeOutlineFixture.mm", "test_native_outlines.py", "tests/mac_ax.py",
            "tests/voiceover.py", "tests/ReadScreen.swift"]
        expected = {name: sha(root / name) for name in sources}
        runs = []
        for mode, count in (("ax", 47), ("voiceover", 52)):
            path = root / "build" / ("native-outline.json" if mode == "ax" else "native-outline-voiceover.json")
            report = json.loads(path.read_text())
            assert report["passed"] is True and report["normalClose"] is True and report["exitCode"] == 0
            assert not any(report.get(name) for name in ("error", "voiceoverCleanupError"))
            assert report["sourceSHA256"] == expected, "Acceptance source set is stale"
            assert report["count"] == len(report["checks"]) == count
            assert report["finalState"]["runID"] == report["runID"]
            assert report["finalState"]["pid"] == report["pid"]
            runs.append({"mode": mode, "reportSHA256": sha(path), "binarySHA256": report["binarySHA256"],
                         "checks": report["checks"], "voiceover": report["voiceover"],
                         "entryCaption": report.get("voiceoverEntryCaption"), "normalClose": True, "exitCode": 0})
        record.update({"passed": True, "scope": "Production AppKit outline provider with synthetic application-owned topology. No 4D hierarchy adapter or Symphony acceptance.",
                       "sourceSHA256": expected, "runs": runs,
                       "limitations": [
                           "The 4D host still rejects hierarchical listboxes. Classic-tree geometry and grouped-list identity, selection and actions remain open.",
                           "No disclosure action is implemented or advertised. Fixture commands supply external state transitions after VoiceOver stops.",
                           "VoiceOver speaks table on entry despite AXOutline and the outline role description. Nested level cues and distant-row navigation pass.",
                           "No spoken disclosure-transition, editing, lazy-loading, 4D desktop mode, pixel comparison, Symphony workflow or signed-kit claim."]})
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        output.write_text(json.dumps(record, indent=2) + "\n")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/native-outlines-development.json")
    args = parser.parse_args()
    publish(ROOT, args.output.resolve())
    print("PASS: source-matched native outline provider record")


if __name__ == "__main__":
    main()
