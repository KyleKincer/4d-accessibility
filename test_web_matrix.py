#!/usr/bin/env python3
"""Run or collect the seven system-engine cases with one unchanged desktop driver."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from build_component import sha
from prepare_web_fixture import BUILD, ROOT


CASES = (
    "baseline-actions-interpreted", "baseline-actions-compiled",
    "bridge-actions-interpreted", "bridge-actions-compiled",
    "bridge-voiceover-compiled", "baseline-pixels-compiled", "bridge-pixels-compiled",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--run", action="store_true")
    action.add_argument("--collect", action="store_true", help="Verify existing reports without launching applications")
    parser.add_argument("--server", type=Path)
    parser.add_argument("--kit", type=Path)
    args = parser.parse_args()
    if args.run:
        if args.server is None or args.kit is None:
            parser.error("--run requires --server and --kit")
        for baseline in (True, False):
            subprocess.run([sys.executable, "prepare_web_fixture.py", "--server", str(args.server), "--kit", str(args.kit), *(["--baseline"] if baseline else [])], cwd=ROOT, check=True)
            for compiled in (False, True):
                subprocess.run([sys.executable, "test_web_fixture.py", "--run", *(["--compiled"] if compiled else [])], cwd=ROOT, check=True)
            if not baseline:
                subprocess.run([sys.executable, "test_web_fixture.py", "--run", "--compiled", "--read-only", "--voiceover"], cwd=ROOT, check=True)
        subprocess.run([sys.executable, "test_web_pixels.py", "--run", "--server", str(args.server), "--kit", str(args.kit)], cwd=ROOT, check=True)

    reports, runs = {}, []
    driver = sha(ROOT / "test_web_fixture.py")
    for case in CASES:
        path = BUILD / ("web-system-" + case + ".json")
        data = json.loads(path.read_text())
        assert data["passed"] and data["exitCode"] == 0 and data["closed"]["runId"] == data["runId"], case
        assert data["engine"] == "system" and data["driver_sha256"] == driver, "Rerun the full matrix with the current driver: " + case
        assert data["baseline"] is case.startswith("baseline-") and data["compiled"] is case.endswith("-compiled"), case
        assert all(check["passed"] for check in data["checks"]), case
        reports[case] = data
        runs.append({"case": "web-system-" + case, "passed": True, "report_sha256": sha(path),
                     **{key: data[key] for key in ("driver_sha256", "compile_sha256", "checks", "closed", "requests")},
                     "voiceoverSteps": len(data.get("voiceover", [])), "browserEvents": data.get("browserEvents"),
                     "bridgeInfo": data["finalState"].get("info"), "readingOrder": data.get("readingOrder")})
    reference = reports["bridge-actions-compiled"]
    for case, data in reports.items():
        assert data["kitVersion"] == reference["kitVersion"], case
        for key in ("native_sha256", "component_sha256"):
            assert data[key] == (None if data["baseline"] else reference[key]), case
    event_checks = []
    for mode in ("interpreted", "compiled"):
        baseline = reports["baseline-actions-" + mode]["browserEvents"]
        bridge = reports["bridge-actions-" + mode]["browserEvents"]
        assert baseline == bridge, "Original browser event sequence changed in " + mode
        event_checks.append({"mode": mode, "passed": True, "events": baseline})
    captions = [step["caption"] for step in reports["bridge-voiceover-compiled"]["voiceover"]]
    close_index = next((index for index, caption in enumerate(captions) if "Close fixture" in caption and "button" in caption), None)
    web_index = next((index for index, caption in enumerate(captions) if caption.lower().rstrip().endswith("native web fixture, web content")), None)
    heading_index = next((index for index, caption in enumerate(captions) if "Native web fixture" in caption and "heading level 1" in caption), None)
    assert close_index is not None, "VoiceOver did not speak the ordinary Close fixture button"
    assert web_index is not None, "VoiceOver did not speak the native web content group"
    assert heading_index is not None, "VoiceOver did not speak the native HTML heading with its role"
    assert close_index < web_index < heading_index, "Reassess the documented ordinary-group then native-web reading order"
    reading_order = {"passed": True, "closeIndex": close_index, "webGroupIndex": web_index,
                     "headingIndex": heading_index, "captions": captions,
                     "scope": "Close visually below the web area is read before native web content; visual interleaving remains incomplete"}
    pixel_path = BUILD / "web-system-pixels.json"
    pixels = json.loads(pixel_path.read_text())
    assert pixels["passed"] and pixels["changedPixels"] == 0 and pixels["differenceBounds"] is None
    assert pixels["driver_sha256"] == sha(ROOT / "test_web_pixels.py"), "Repeat pixel comparison with the current driver"
    for variant in ("baseline", "bridge"):
        assert pixels["reports"][variant] == sha(BUILD / ("web-system-" + variant + "-pixels-compiled.json"))
    result = {"passed": True, "driver_sha256": driver, "runs": runs,
              "liveChecks": sum(len(run["checks"]) for run in runs), "browserEventChecks": event_checks,
              "voiceoverReadingOrder": reading_order,
              "pixels": pixels, "pixels_report_sha256": sha(pixel_path)}
    (BUILD / "web-system-matrix.json").write_text(json.dumps(result, indent=2) + "\n")
    print("PASS: seven current-driver runs, original browser events, recorded VoiceOver order and complete-window pixels")


if __name__ == "__main__":
    main()
