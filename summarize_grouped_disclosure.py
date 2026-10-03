#!/usr/bin/env python3
"""Publish only the complete, source-matched grouped disclosure gate."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re

from summarize_grouped_outlines import GRID_CASES, GRID_SOURCES, compare_pixels, read, sha, validate_faults, validate_prepared, validate_run as validate_readonly_run, validate_speech
from test_grouped_disclosure import SOURCES as ACTION_SOURCES
from test_grouped_disclosure_subforms import SOURCES as NESTED_SOURCES

ROOT = Path(__file__).resolve().parent
CONFIRMED = "Group disclosure confirmed"
IDEMPOTENT = "Group already has the requested disclosure state"
FIELDS = {"objectName", "backingRow", "breakLevel", "expanded", "actionID"}
FAULTS = ("ignore", "membership", "caption", "reparent", "scope", "loading", "replace", "remove")


def terminal_rejection(receipt):
    assert isinstance(receipt, str) and receipt.strip()
    assert receipt not in (CONFIRMED, IDEMPOTENT, "Action queued", "Waiting for the application to complete the action")


def validate_action(item, instance=None, run_id=None, compiled=None, outcome=None, call_count=None):
    before, after = item["before"], item["after"]
    if instance:
        before, after = before[instance], after[instance]
    if run_id is not None:
        assert before["runId"] == after["runId"] == run_id
        assert before["compiled"] is compiled and after["compiled"] is compiled
    calls = after["disclosureCalls"][len(before["disclosureCalls"]):]
    assert after["disclosureCalls"] == before["disclosureCalls"] + calls
    assert calls == item["calls"] and len(calls) <= 1
    if call_count is not None:
        assert len(calls) == call_count
    key = item["rowKey"]
    group = before["outline"]["outline"][key]
    assert group["kind"] == "group" and type(item["expanded"]) is bool
    for call in calls:
        assert set(call) == FIELDS and call["actionID"]
        assert call["objectName"] == "Grouped" and call["expanded"] is item["expanded"]
        assert call["backingRow"] == before["outline"]["positions"][key]
        assert call["breakLevel"] == group["level"] + 1
    if outcome in (CONFIRMED, IDEMPOTENT):
        assert item["receipt"] == outcome
    elif outcome == "rejected":
        terminal_rejection(item["receipt"])
    if item["receipt"] == CONFIRMED:
        assert len(calls) == 1
        assert after["outline"]["outline"][key]["expanded"] is item["expanded"]
    elif item["receipt"] == IDEMPOTENT:
        assert not calls and group["expanded"] is item["expanded"]
        assert after["outline"]["outline"][key]["expanded"] is item["expanded"]
    else:
        assert isinstance(item["receipt"], str) and item["receipt"].strip()
        assert item["receipt"] not in ("Action queued", "Waiting for the application to complete the action")
    return calls


def validate_nested_preservation(item, run_id, compiled):
    before, after = item["before"], item["after"]
    for snapshot in (before, after):
        assert set(snapshot) == {"root", "main", "peer"}
        assert len({state["rootTick"] for state in snapshot.values()}) == 1
        assert all(state["runId"] == run_id and state["compiled"] is compiled for state in snapshot.values())
    instance = item["instance"]
    other = "peer" if instance == "main" else "main"
    assert all(before[other][field] == after[other][field] for field in ("disclosureCalls", "beforeGroup", "events"))
    assert before["root"]["outerScroll"] == after["root"]["outerScroll"]
    assert before["root"][other]["innerScroll"] == after["root"][other]["innerScroll"]
    if item.get("fault") == "replace":
        # The fixture's ordinary replacement creates a fresh child at its
        # native initial scroll. Parent and untouched sibling must stay still.
        assert after[instance]["loadSerial"] > before[instance]["loadSerial"]
        assert after["root"][instance]["innerScroll"] == [0, 0]
    else:
        assert before["root"][instance]["innerScroll"] == after["root"][instance]["innerScroll"]


def validate_voiceover(report):
    items = [report["voiceoverCollapse"], report["voiceoverExpand"], *report["voiceoverRowActions"]]
    assert [item["expanded"] for item in items] == [False, True, False, True]
    for item in items:
        validate_action(item, run_id=report["runId"], compiled=True, outcome=CONFIRMED, call_count=1)
        assert item["rowKey"] == item["before"]["outline"]["rows"][0]
        assert item["before"]["outline"]["outline"][item["rowKey"]]["label"] == "A"
        assert re.search(r"\bA:\s*" + ("expanded" if item["expanded"] else "collapsed") + r"\b", item["caption"], re.I)
    assert report["collapsedCaption"] == items[0]["caption"] and report["expandedCaption"] == items[1]["caption"]
    assert report["groupActivationTarget"] == "disclosure"
    activations = [i for i, step in enumerate(report["voiceover"]) if step["key"] == "space"]
    assert len(activations) == 4
    assert report["disclosureNavigationIndex"] == activations[1] + 1
    assert report["rowNavigationIndex"] == activations[3] + 1
    exit_step = report["voiceover"][report["disclosureNavigationIndex"]]
    assert exit_step["key"] == "up" and exit_step["shift"] is True
    for field, offset in (("disclosureNavigationIndex", 1), ("rowNavigationIndex", 0)):
        index = report[field] + offset
        step = report["voiceover"][index]
        assert step["key"] == "right" and "shared" in step["caption"] and "level 1" in step["caption"]


def validate_fault(item, nested=False):
    if nested:
        fault = item["fault"]
        before, after = item["before"], item["after"]
        command = after["root"]["command"]
        assert command["id"] and command["operation"] == fault and command["target"] == "main"
        if fault == "childScope":
            assert before["main"]["scope"] != after["main"]["scope"]
        elif fault == "childReady":
            assert before["main"]["ready"] is True and after["main"]["ready"] is False
            assert before["main"]["runtimeGeneration"] != after["main"]["runtimeGeneration"]
        elif fault == "replace":
            assert after["main"]["loadSerial"] > before["main"]["loadSerial"]
            assert before["main"]["runtimeGeneration"] != after["main"]["runtimeGeneration"]
        elif fault == "rootScope":
            assert before["root"]["scope"] != after["root"]["scope"]
        else:
            raise AssertionError("Unknown nested fault")
        return
    before, after = item["before"], item["after"]
    fault = before["disclosureMode"]
    assert fault in FAULTS
    position = before["outline"]["positions"][item["rowKey"]] - 1
    if fault == "membership":
        assert after["beforeGroup"]["keys"][position] == before["beforeGroup"]["keys"][position] + 1000
    elif fault in ("caption", "reparent"):
        assert before["beforeGroup"]["levels"][0]["values"][position] != after["beforeGroup"]["levels"][0]["values"][position]
        assert after["beforeGroup"]["levels"][0]["values"][position] == ("Changed caption" if fault == "caption" else "Moved parent")
        if fault == "reparent":
            assert before["outline"]["outline"][item["rowKey"]]["level"] == 1
    elif fault == "scope":
        assert before["scope"] != after["scope"]
    elif fault == "loading":
        assert before["ready"] is True and after["ready"] is False
    if fault in ("loading", "replace", "remove"):
        assert before["runtimeGeneration"] != after["runtimeGeneration"]
    if fault in ("replace", "remove"):
        assert after["ready"] is True
        assert after["runtimeDisclosure"] is (fault == "replace")


def validate_pixels(root, report, cases):
    from PIL import Image, ImageChops
    assert [item.get("case") for item in report["pixels"]] == list(cases)
    for item in report["pixels"]:
        assert item["wholeWindow"] is True and item["mask"] is False and item["tolerance"] == 0 and item["changedPixels"] == 0
        images = []
        for kind in ("baseline", "integrated"):
            image = item[kind]
            path = root / "build" / image["path"]
            assert path.parent == root / "build" and sha(path) == image["sha256"]
            captured = image["capturedWindow"]
            assert captured["pidVerified"] is True and captured["pid"] == report["pid"]
            assert all(captured[name] == report["window"][name] for name in ("title", "position", "size"))
            images.append(Image.open(path).convert("RGBA"))
        assert images[0].size == images[1].size
        difference = ImageChops.difference(*images)
        assert all(color == (0, 0, 0, 0) for _, color in difference.getcolors(difference.width * difference.height))


def validate_run(root, path, prepared_path, prepared, compiled, nested=False, voiceover=False):
    report = read(path)
    assert report["passed"] is True and report["compiled"] is compiled
    assert report["exitCode"] == 0 and report["closed"]["runId"] == report["runId"]
    assert not any(report.get(field) for field in ("error", "finalError", "shutdownErrors", "voiceoverCleanupFailure"))
    assert report["compileReportSHA256"] == sha(prepared_path)
    assert report["sources_sha256" if nested else "preparedSourceSHA256"] == prepared["sources_sha256"]
    for field in ("canonicalSourceSHA256", "nativeSourceSHA256", "componentSourceSHA256", "nativeSHA256", "componentPackageSHA256", "compiledHostSHA256"):
        assert report[field] == prepared[field], field
    sources = NESTED_SOURCES if nested else ACTION_SOURCES
    assert report["driverSourceSHA256"] == {name: sha(root / name) for name in sources}
    assert report["window"]["title"] == "AX native hierarchy probe"
    states = report["finalState"].values() if nested else [report["finalState"]]
    assert all(state["runId"] == report["runId"] and state["compiled"] is compiled for state in states)
    if nested:
        assert len(report["actions"]) == 12
        faults = [item for item in report["actions"] if "fault" in item]
        assert [item["fault"] for item in faults] == ["childScope", "childReady", "replace", "rootScope"]
        outcomes = [CONFIRMED, CONFIRMED, IDEMPOTENT, CONFIRMED] + ["rejected"] * 5 + [CONFIRMED, IDEMPOTENT, "rejected"]
        counts = [1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1]
        for item, outcome, count in zip(report["actions"], outcomes, counts):
            validate_action(item, item["instance"], report["runId"], compiled, outcome, count)
            validate_nested_preservation(item, report["runId"], compiled)
            if "fault" in item:
                validate_fault(item, True)
        assert report["closed"]["clearedTrees"] == len(report["finalState"]["root"]["ownedTrees"])
        validate_pixels(root, report, [None])
    else:
        assert report["actionGate"] is True and len(report["actions"]) == 25
        outcomes = [CONFIRMED, CONFIRMED, IDEMPOTENT] * 3 + [CONFIRMED] * 8 + ["rejected"] * 8
        counts = [1, 1, 0] * 3 + [1] * 16
        for item, outcome, count in zip(report["actions"], outcomes, counts):
            validate_action(item, run_id=report["runId"], compiled=compiled, outcome=outcome, call_count=count)
        assert [item["before"]["disclosureMode"] for item in report["actions"][-8:]] == list(FAULTS)
        assert all(item["receipt"] not in (CONFIRMED, IDEMPOTENT) and len(item["calls"]) == 1 for item in report["actions"][-8:])
        for item in report["actions"][-8:]:
            validate_fault(item)
        editor = report["nativeEditorRejection"]
        assert all(state["runId"] == report["runId"] and state["compiled"] is compiled for state in (editor["before"], editor["after"]))
        assert editor["before"]["editing"] and editor["after"]["editing"]
        assert editor["before"]["disclosureCalls"] == editor["after"]["disclosureCalls"]
        assert editor["before"]["editedText"] == editor["after"]["editedText"]
        terminal_rejection(editor["receipt"])
        validate_pixels(root, report, ["singleText", "singleDate", "repeated"])
    if voiceover:
        validate_voiceover(report)
    return report


def publish(root, output):
    record = {"passed": False, "date": datetime.now(timezone.utc).isoformat()}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record) + "\n")
    try:
        prepared_path, prepared = validate_prepared(root)
        assert prepared["disclosure"] is True and prepared["subforms"] is True
        runs = []
        for mode, compiled, nested, voiceover in (
            ("interpreted", False, False, False), ("compiled", True, False, False),
            ("compiled-voiceover", True, False, True), ("subforms-interpreted", False, True, False), ("subforms-compiled", True, True, False)):
            path = root / "build" / ("grouped-disclosure-" + mode + ".json")
            report = validate_run(root, path, prepared_path, prepared, compiled, nested, voiceover)
            result = {"mode": mode, "reportSHA256": sha(path), "checks": report["checks"], "pixels": report["pixels"],
                      "environment": report["environment"], "normalClose": True}
            if voiceover:
                result["voiceover"] = report["voiceover"]
                result["disclosureFeedback"] = [{field: item[field] for field in ("rowKey", "expanded", "calls", "receipt", "caption")} for item in
                                               (report["voiceoverCollapse"], report["voiceoverExpand"], *report["voiceoverRowActions"])]
            runs.append(result)
        helper_path = root / "build/outline-action-helpers.json"
        helper = read(helper_path)
        assert helper["passed"] is True and helper["checks"] == 37 and len(helper["result"]) == 37
        assert all(value is True for value in helper["result"].values())
        assert helper["driverSHA256"] == sha(root / "test_outline_action_helpers.py")
        assert helper["sourceSHA256"] == {name: sha(root / name) for name in
            ("host/OptionalMethods/AXB_OutlineTarget.4dm", "host/OptionalMethods/AXB_KeyIndex.4dm", "host/OptionalMethods/AXB_GridOptions.4dm")}
        readonly, pixels = [], []
        for mode in ("interpreted", "compiled"):
            path = root / "build" / ("grouped-outline-" + mode + ".json")
            report = validate_readonly_run(root, path, prepared_path, prepared, mode == "compiled")
            validate_faults(report)
            assert report["finalState"]["runtimeDisclosure"] is False
            baseline_path = root / "build" / ("grouped-outline-" + mode + "-baseline.json")
            baseline = validate_readonly_run(root, baseline_path, prepared_path, prepared, mode == "compiled")
            assert baseline["packageRestored"] is True and baseline["finalState"]["info"]["native"] is False
            pixels.append({"mode": mode, "baselineReportSHA256": sha(baseline_path),
                           "comparisons": compare_pixels(root / "build", baseline, report)})
            readonly.append({"mode": mode, "reportSHA256": sha(path), "checks": report["checks"]})
        path = root / "build/grouped-outline-compiled-voiceover.json"
        report = validate_readonly_run(root, path, prepared_path, prepared, True)
        validate_faults(report)
        assert report["finalState"]["runtimeDisclosure"] is False
        end_caption = report.get("loadedEndCaption") or next((step["caption"] for step in report["voiceover"] if step["key"] == "end"), "")
        assert "Leaf 8" in end_caption
        readonly.append({"mode": "compiled-voiceover", "reportSHA256": sha(path), "checks": report["checks"],
                         "voiceover": report["voiceover"], "loadedEndCaption": end_caption})
        grid_speech = validate_speech(root, root / "build/grid-value-speech/report.json", GRID_CASES, GRID_SOURCES, "sources_sha256")
        record.update({"passed": True, "version": (root / "VERSION").read_text().strip(), "runs": runs,
            "scope": "Explicit application-controlled text/date grouped disclosure in standalone and repeated nested synthetic 4D forms.",
            "compileReportSHA256": sha(prepared_path), "nativeSHA256": prepared["nativeSHA256"],
            "canonicalSourceSHA256": prepared["canonicalSourceSHA256"], "nativeSourceSHA256": prepared["nativeSourceSHA256"],
            "componentSourceSHA256": prepared["componentSourceSHA256"], "componentPackageSHA256": prepared["componentPackageSHA256"],
            "summarySHA256": sha(root / "summarize_grouped_disclosure.py"), "hostCommandChecks": {"checks": 37, "reportSHA256": sha(helper_path)},
            "readOnlyRegression": readonly, "packageBaselinePixels": pixels, "flatGridSpeechRegression": grid_speech,
            "limitations": ["Complete break selection, reveal and editing remain unavailable.",
                "Actual Symphony workflows, classic trees, broader caption types and lazy loading remain pending.",
                "VoiceOver speech is accepted in English. One bridge announcement does not establish absence of duplicate native speech.",
                "Physical Intel, client/server and signed distribution are separate gates."]})
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        output.write_text(json.dumps(record, indent=2) + "\n")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/grouped-disclosure-development.json")
    args = parser.parse_args()
    publish(ROOT, args.output.resolve())
    print("PASS: complete grouped disclosure matrix and exact source/artifact validation")


if __name__ == "__main__":
    main()
