#!/usr/bin/env python3
"""Publish the source-matched read-only grouped 4D development gate."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from build_component import CORE
from prepare_hierarchy_probe import canonical_sources
from test_grouped_outline import DRIVER_SOURCES
from test_outline_value_speech import CASES as OUTLINE_CASES, SOURCES as OUTLINE_SOURCES
from test_grid_value_speech import CASES as GRID_CASES, SOURCES as GRID_SOURCES

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(root):
    return {str(p.relative_to(root)): sha(p) for p in root.rglob("*") if p.is_file()}


def read(path):
    return json.loads(path.read_text())


def validate_prepared(root):
    build = root / "build"
    fixture = build / "hierarchy-probe"
    path = build / "hierarchy-probe-compile.json"
    prepared = read(path)
    assert prepared["passed"] is True and prepared["bridge"] is True
    assert prepared["compiler"]["success"] is True and not prepared["compiler"]["errors"]
    assert not prepared["changed_during_compile"]
    assert prepared["canonicalSourceSHA256"] == canonical_sources(root)
    assert prepared["preparerSHA256"] == sha(root / "prepare_hierarchy_probe.py")
    # Source paths are fixture-relative; compare the exact set as well as bytes.
    source_map = {"Project/Sources/" + name: value for name, value in files(fixture / "Project/Sources").items()}
    assert prepared["sources_sha256"] == source_map
    host_map = {str(p.relative_to(fixture)): sha(p)
                for directory in (fixture / "Libraries", fixture / "Project/DerivedData/CompiledCode")
                for p in directory.rglob("*") if p.is_file()}
    assert host_map and host_map == prepared["compiledHostSHA256"]
    component = fixture / "Components/AccessibilityBridge.4dbase"
    assert files(component) == prepared["componentPackageSHA256"]
    assert sha(component / "AccessibilityBridge.4DZ") == prepared["componentSHA256"]
    assert sha(fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge") == prepared["nativeSHA256"]
    native_build, component_build = read(build / "build-report.json"), read(build / "component-build-report.json")
    assert component_build["passed"] is True
    assert native_build["binary_sha256"] == component_build["native_sha256"] == prepared["nativeSHA256"]
    assert component_build["package_sha256"] == prepared["componentPackageSHA256"]
    native_paths = sorted((root / "src").glob("*")) + sorted((root / "host/Methods").glob("*.4dm")) + sorted((root / "resources/en.lproj").glob("*"))
    native_paths += [root / "manifest.json", root / "VERSION"]
    assert prepared["nativeSourceSHA256"] == {str(p.relative_to(root)): sha(p) for p in native_paths if p.is_file()}
    component_paths = [root / "host/Methods" / (name + ".4dm") for name in CORE]
    component_paths += [root / "host/Methods/Compiler_AXB.4dm", root / "VERSION", root / "build_component.py"]
    assert prepared["componentSourceSHA256"] == {str(p.relative_to(root)): sha(p) for p in component_paths}
    for field, artifact in (("nativeSourceSHA256", native_build), ("componentSourceSHA256", component_build)):
        assert prepared[field] == artifact["sources_sha256"]
        assert all(sha(root / name) == value for name, value in prepared[field].items())
    return path, prepared


def validate_run(root, path, prepared_path, prepared, compiled):
    report = read(path)
    assert report["passed"] is True and report["compiled"] is compiled
    assert report["exitCode"] == 0 and report["closed"]["runId"] == report["runId"]
    assert not any(report.get(name) for name in ("failure", "finalError", "shutdownErrors", "voiceoverCleanupFailure", "packageRestoreFailure"))
    assert report["compileReportSHA256"] == sha(prepared_path)
    assert report["preparedSourceSHA256"] == prepared["sources_sha256"]
    for field in ("canonicalSourceSHA256", "nativeSourceSHA256", "componentSourceSHA256", "componentPackageSHA256", "compiledHostSHA256",
                  "nativeSHA256", "componentSHA256"):
        assert report[field] == prepared[field], field
    assert report["driverSHA256"] == sha(root / "test_grouped_outline.py")
    assert report["driverSourceSHA256"] == {name: sha(root / name) for name in DRIVER_SOURCES}
    assert report["window"]["title"] == "AX native hierarchy probe"
    assert report["finalState"]["runId"] == report["runId"] and report["finalState"]["compiled"] is compiled
    for item in report["states"]:
        state = item["state"]
        assert state["runId"] == report["runId"] and state["compiled"] is compiled
        assert state["command"]["operation"] == item["operation"] and not state["command"].get("error")
        assert state["capturePreservesOK"] and state["modelSentinelBefore"] == state["modelSentinelAfter"]
        assert state["beforeGroup"] == state["afterGroup"] and state["groupSentinelBefore"] == state["groupSentinelAfter"]
        image = item["image"]
        assert sha(root / "build" / image["path"]) == image["sha256"]
        assert image["capturedWindow"]["pid"] == report["pid"] and image["capturedWindow"]["title"] == report["window"]["title"]
        assert image["capturedWindow"]["pidVerified"] is True
        assert all(image["capturedWindow"][name] == report["window"][name] for name in ("position", "size"))
    return report


def validate_faults(report):
    states = report["states"]
    prefix = ["groupCase", "groupExpandAll", "groupCollapseAll", "groupExpandAll"] * 3
    faults = ("groupFormatNested", "groupProtectNested", "groupHideFirst")
    expected = prefix + ["groupControlRestore", "groupFaultBinding"]
    for fault in faults:
        expected += [fault, "groupRestoreCaption", "groupShowAll", "groupCase"]
    expected += ["groupCaseVariants", "groupCase"]
    assert [item["operation"] for item in states] == expected
    assert [states[index]["payload"] for index in (0, 4, 8)] == [{"name": name} for name in ("singleText", "singleDate", "repeated")]
    bindings = states[13]["state"]["bindingFaults"]
    assert [item["fault"] for item in bindings] == ["key", "keyType", "hierarchy", "selection", "missingHierarchy", "missingKey", "missingSelection", "missingControl", "controlType", "controlNull"]
    assert all(item["rejected"] and item["preservesOK"] and item["preservesState"] for item in bindings)
    for index, message in ((14, "Formatted"), (18, "Protected"), (22, "Hidden")):
        capture = states[index]["state"]["capture"]
        assert capture["ok"] is False and message in capture["message"]
    variant = states[26]["state"]
    assert variant["capture"]["ok"] is True and variant["outline"]["ok"] is True
    level = variant["capture"]["snapshot"]["levels"][0]
    assert level["values"][0] != level["values"][1] and level["frames"][0] != level["frames"][1]
    model = variant["outline"]["outline"]
    parent_one = model[model["l:1"]["parent"]]["parent"]
    parent_two = model[model["l:2"]["parent"]]["parent"]
    assert parent_one != parent_two and model[parent_one]["label"] == "A" and model[parent_two]["label"] == "a"
    assert all(states[index]["state"]["capture"]["ok"] and states[index]["state"]["outline"]["ok"] for index in (17, 21, 25, 27))
    absent, restored = (states[index]["state"] for index in (11, 12))
    assert "controlType" not in absent["afterGroup"] and absent["capture"]["ok"] and absent["outline"]["ok"] and absent["capture"]["snapshot"]["flags"] == [0] * 8
    assert restored["afterGroup"]["controlType"] == 16 and restored["capture"]["ok"] and restored["outline"]["ok"]


def compare_pixels(build, baseline, integrated):
    from PIL import Image, ImageChops
    operations = ["groupCase", "groupExpandAll", "groupCollapseAll", "groupExpandAll"] * 3 + ["groupControlRestore"]
    assert len(baseline["states"]) == len(operations)
    candidates = integrated["states"][:len(operations)]
    assert [s["operation"] for s in baseline["states"]] == [s["operation"] for s in candidates] == operations
    assert baseline["window"] == integrated["window"]
    comparisons = []
    for before, after in zip(baseline["states"], candidates):
        assert before["payload"] == after["payload"]
        images = [Image.open(build / s["image"]["path"]).convert("RGBA") for s in (before, after)]
        assert images[0].size == images[1].size
        difference = ImageChops.difference(*images)
        changed = sum(count for count, color in difference.getcolors(difference.width * difference.height) if color != (0, 0, 0, 0))
        assert changed == 0, "Complete native grouped window changed"
        comparisons.append({"operation": before["operation"], "payload": before["payload"], "baselineSHA256": before["image"]["sha256"],
                            "integratedSHA256": after["image"]["sha256"], "size": list(images[0].size), "changedPixels": 0,
                            "differenceBounds": None, "wholeWindow": True, "mask": False, "tolerance": 0})
    return comparisons


def validate_speech(root, path, cases, sources, source_field="sourceSHA256"):
    report = read(path)
    assert report["passed"] is True
    assert report[source_field] == {name: sha(root / name) for name in sources}
    assert [item["case"] for item in report["cases"]] == list(cases)
    assert all(item["passed"] is True and item["exitCode"] == 0 and not item.get("error") and not item.get("cleanupError")
               for item in report["cases"])
    outline = source_field == "sourceSHA256"
    binary = path.parent / ("NativeOutlineFixture" if outline else "NativeGridFixture")
    assert sha(binary) == report["binarySHA256" if outline else "binary_sha256"]
    for item in report["cases"]:
        assert item["checks"] and item["voiceover"] and item["observations"]
        if outline:
            assert "Loading" in item["coldCaption"] and "25" in item["coldCaption"]
            assert len(item["observations"]) == 8
            for state in (item["beforeRelease"], item["afterRelease"]):
                assert state["runID"] == item["runID"] and state["pid"] == item["pid"]
            assert all(item["beforeRelease"][name] == item["afterRelease"][name] for name in ("generation", "order", "revision", "rows"))
            captions = [observation["caption"] for observation in item["observations"]]
            assert not any("not responding" in caption.lower() for caption in captions)
            if item["case"] in ("leave", "leave-after-load"):
                assert not any("root/" in caption or "Distant leaf" in caption for caption in captions)
                assert "arriving values do not interrupt reading outside the outline" in item["checks"]
            else:
                expected = "Updated final value" if item["case"] == "fast-update" else "Value root/19"
                assert any(expected in caption for caption in captions)
                assert not any("root/18" in caption or "Distant leaf" in caption for caption in captions)
                assert "VoiceOver speaks the loaded final value without cursor movement" in item["checks"]
            assert "owned fixture closes normally with matching evidence" in item["checks"]
        else:
            assert "VoiceOver actually reads the cold first cell" in item["checks"]
            for observation in item["observations"]:
                assert len(observation["captions"]) == 8
                captions = [value["caption"] for value in observation["captions"]]
                assert not any("not responding" in caption.lower() for caption in captions)
                if observation["leftGrid"]:
                    assert not any("row-" in caption for caption in captions)
                elif item["case"] in ("checkbox", "checkbox_leave"):
                    assert any("Approved" in caption and "checked" in caption.lower() and "unchecked" not in caption.lower() for caption in captions)
                elif item["case"] == "popup":
                    assert any("Decision" in caption and "Allowed" in caption for caption in captions)
                else:
                    column = observation["column"]
                    assert any(re.search(rf"row-00000\s*/\s*column-{column}\s*/\s*value-[0oO]\b", caption) for caption in captions)
    return {"reportSHA256": sha(path), "sourceSHA256": report[source_field], "cases": report["cases"]}


def publish(root, output):
    record = {"passed": False, "date": datetime.now(timezone.utc).isoformat()}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record) + "\n")
    try:
        prepared_path, prepared = validate_prepared(root)
        runs, pixels = [], []
        for mode in ("interpreted", "compiled"):
            path = root / "build" / ("grouped-outline-" + mode + ".json")
            report = validate_run(root, path, prepared_path, prepared, mode == "compiled")
            validate_faults(report)
            baseline_path = root / "build" / ("grouped-outline-" + mode + "-baseline.json")
            baseline = validate_run(root, baseline_path, prepared_path, prepared, mode == "compiled")
            assert baseline["packageRestored"] is True and baseline["finalState"]["info"]["native"] is False
            pixels.append({"mode": mode, "baselineReportSHA256": sha(baseline_path), "comparisons": compare_pixels(root / "build", baseline, report)})
            runs.append({"mode": mode, "reportSHA256": sha(path), "checks": report["checks"], "environment": report["environment"],
                         "nativeSHA256": report["nativeSHA256"], "componentPackageSHA256": report["componentPackageSHA256"], "normalClose": True})
        path = root / "build/grouped-outline-compiled-voiceover.json"
        voiceover = validate_run(root, path, prepared_path, prepared, True)
        validate_faults(voiceover)
        assert "Leaf 8" in voiceover.get("loadedEndCaption", "") or any("Leaf 8" in step["caption"] for step in voiceover["voiceover"] if step["key"] == "end")
        runs.append({"mode": "compiled-voiceover", "reportSHA256": sha(path), "checks": voiceover["checks"],
                     "voiceover": voiceover["voiceover"], "entryCaption": voiceover["entryCaption"],
                     "loadedEndCaption": voiceover.get("loadedEndCaption"), "normalClose": True})
        speech = validate_speech(root, root / "build/outline-value-speech-current/report.json", OUTLINE_CASES, OUTLINE_SOURCES)
        grid_speech = validate_speech(root, root / "build/grid-value-speech/report.json", GRID_CASES, GRID_SOURCES, "sources_sha256")
        supporting = []
        for mode in ("interpreted", "compiled"):
            path = root / "build" / ("grouped-single-level-" + mode + ".json")
            report = read(path)
            assert report["passed"] is True and report["compiled"] is (mode == "compiled") and report["bridgeInstalled"] is True
            assert report["compileReportSHA256"] == sha(prepared_path) and report["preparedSourceSHA256"] == prepared["sources_sha256"]
            assert report["driverSHA256"] == sha(root / "test_grouped_single_level.py") and len(report["checks"]) == 26
            assert report["exitCode"] == 0 and report["closed"]["runId"] == report["runId"] and not report.get("shutdownErrors")
            supporting.append({"mode": mode, "reportSHA256": sha(path), "checks": report["checks"]})
        row_path, helper_path = root / "build/outline-rows.json", root / "build/outline-host-helpers.json"
        row_report, helper_report = read(row_path), read(helper_path)
        assert row_report["passed"] is True and row_report["checks"] == 28
        assert row_report["sourceSHA256"] == sha(root / "host/OptionalMethods/AXB_OutlineRows.4dm")
        assert row_report["tokenSHA256"] == sha(root / "host/OptionalMethods/AXB_OutlineToken.4dm")
        assert row_report["driverSHA256"] == sha(root / "test_outline_rows.py") and len(row_report["result"]) == 28
        assert all(value is True for value in row_report["result"].values())
        assert helper_report["passed"] is True and helper_report["checks"] == 11
        assert helper_report["driverSHA256"] == sha(root / "test_outline_host_helpers.py")
        assert helper_report["sourceSHA256"] == {"host/OptionalMethods/" + name + ".4dm": sha(root / "host/OptionalMethods" / (name + ".4dm"))
                                                for name in ("AXB_GridGeometry", "AXB_GridReadPages", "AXB_KeyIndex")}
        record.update({"passed": True, "version": (root / "VERSION").read_text().strip(),
                       "scope": "Read-only text/date array grouped listboxes in a disposable 4D form. No disclosure action or Symphony workflow acceptance.",
                       "compileReportSHA256": sha(prepared_path), "canonicalSourceSHA256": prepared["canonicalSourceSHA256"],
                       "nativeSourceSHA256": prepared["nativeSourceSHA256"], "componentSourceSHA256": prepared["componentSourceSHA256"],
                       "componentPackageSHA256": prepared["componentPackageSHA256"], "compiledHostSHA256": prepared["compiledHostSHA256"],
                       "driverSourceSHA256": voiceover["driverSourceSHA256"], "summarySHA256": sha(root / "summarize_grouped_outlines.py"),
                       "runs": runs, "pixels": pixels, "coldOutlineSpeech": speech, "flatGridSpeechRegression": grid_speech,
                       "singlePointerGeometry": supporting,
                       "hostCommandChecks": {"rows": {"checks": 28, "reportSHA256": sha(row_path)}, "geometryAndPages": {"checks": 11, "reportSHA256": sha(helper_path)}},
                       "limitations": [
                           "Disclosure, complete selection, reveal and editing remain unavailable through accessibility. Original fixture commands change expansion.",
                           "Only text/date break captions are accepted. Hidden backing rows, formatted text and protected captions fail closed.",
                           "One-pointer and nested array hierarchies are synthetic acceptance. Actual Symphony Alerts/date workflows are pending.",
                           "Lazy loading, ancestor clipping, broader styled/numeric captions, classic trees and other hierarchy families remain pending.",
                           "VoiceOver says table on entry despite AXOutline. The one-second settled layout notification is an observed workaround.",
                           "Host architecture is recorded. Physical Intel, client/server, background-window speech and signed distribution are not established."]})
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        output.write_text(json.dumps(record, indent=2) + "\n")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/grouped-outlines-development.json")
    args = parser.parse_args()
    publish(ROOT, args.output.resolve())
    print("PASS: both 4D modes, compiled VoiceOver, cold-value speech regressions and whole-window pixels")


if __name__ == "__main__":
    main()
