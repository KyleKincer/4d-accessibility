#!/usr/bin/env python3
"""Characterize one-pointer text/date geometry through public native getters."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

from build_component import BUILD, ROOT
from test_hierarchy_probe import finish_run, read_json
from prepare_hierarchy_probe import canonical_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.add_argument("--compiled", action="store_true")
    args = parser.parse_args()
    mode = "compiled" if args.compiled else "interpreted"
    path = BUILD / ("grouped-single-level-" + mode + ".json")
    report = {"passed": False, "checks": [], "states": [], "compiled": args.compiled,
              "scope": "Public geometry and pure host capture characterization. No accessibility action acceptance."}
    path.write_text(json.dumps(report) + "\n")
    sys.path.insert(0, str(ROOT / "tests"))
    import mac_ax as ax
    from fixture_desktop import activate_fixture, wait_for_start
    ax.require_test_input()
    compile_path = BUILD / "hierarchy-probe-compile.json"
    compiled = json.loads(compile_path.read_text())
    fixture = BUILD / "hierarchy-probe"
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    assert compiled["passed"] and compiled["preparerSHA256"] == hashlib.sha256((ROOT / "prepare_hierarchy_probe.py").read_bytes()).hexdigest()
    assert compiled["canonicalSourceSHA256"] == canonical_sources()
    report["bridgeInstalled"] = compiled["bridge"]
    for name, expected in compiled["sources_sha256"].items():
        assert hashlib.sha256((fixture / name).read_bytes()).hexdigest() == expected, name
    for source in (ROOT / "tests/4d").glob("AXHP_*.4dm"):
        expected = source.read_text()
        if compiled["bridge"] and source.name == "AXHP_State.4dm":
            expected = expected.replace("// Native probe result, when installed.",
                '$state.bridge:=AXB_Area("diagnostics"; ""; "")\n$state.info:=AXB_Host("info"; New object)')
        assert expected == (fixture / "Project/Sources/Methods" / source.name).read_text(), source.name
    for name in ("AXB_OutlineCapture", "AXB_OutlineRows", "AXB_OutlineToken"):
        source = ROOT / "host/OptionalMethods" / (name + ".4dm")
        installed = (fixture / "Project/Sources/Methods" / source.name).read_text()
        if compiled["bridge"]:
            header, _, installed = installed.partition("\n")
            assert header.endswith(hashlib.sha256(installed.encode()).hexdigest())
        assert source.read_text() == installed
    report.update({"preparedSourceSHA256": compiled["sources_sha256"], "compileReportSHA256": hashlib.sha256(compile_path.read_bytes()).hexdigest(),
                   "driverSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    resources = fixture / "Resources"
    for name in ("state.json", "close.json", "closed.json", "error.json", "request.json"):
        (resources / name).unlink(missing_ok=True)
    run_id = (resources / "run-id.txt").read_text()
    report["runId"] = run_id

    def state():
        assert not (resources / "error.json").exists()
        value = read_json(resources / "state.json")
        return value if value and value.get("runId") == run_id else None

    def check(condition, message):
        assert condition, message
        report["checks"].append(message)
        print("PASS:", message, flush=True)

    finished = False
    with (BUILD / ("grouped-single-level-" + mode + ".log")).open("w") as log:
        process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(fixture / "Project/Hierarchy.4DProject"),
                                    "--dataless", "--opening-mode", mode, "--webadmin-auto-start", "false"], stdout=log, stderr=log)
        try:
            ready, _ = wait_for_start(process, fixture / "Project/Hierarchy.4DProject", state, BUILD)
            check(ready["compiled"] is args.compiled, "actual desktop execution mode matches the requested mode")
            activate_fixture(process, fixture / "Project/Hierarchy.4DProject", "AX native hierarchy probe")

            def command(operation, **payload):
                identifier = uuid.uuid4().hex
                (resources / "request.json").write_text(json.dumps({"id": identifier, "operation": operation, **payload}))
                value = ax.wait_for(lambda: s if (s := state()) and s["command"]["id"] == identifier else None, "Public command did not finish")
                time.sleep(0.4)
                value = state()
                assert value and value["command"]["id"] == identifier
                assert not value["command"].get("error")
                assert value["beforeGroup"] == value["afterGroup"] and value["groupSentinelBefore"] == value["groupSentinelAfter"]
                assert value["okPreserved"] and value["focus"] == value["focusAfter"]
                assert value["capturePreservesOK"] and value["modelSentinelBefore"] == value["modelSentinelAfter"]
                assert value["capture"]["ok"], value["capture"]
                assert value["outline"]["ok"], value["outline"]
                report["states"].append({"operation": operation, "payload": payload, "state": value})
                image = BUILD / ("grouped-single-" + mode + "-" + identifier + ".png")
                ax.capture_window(process.pid, image)
                report["states"][-1]["image"] = {"path": image.name, "sha256": hashlib.sha256(image.read_bytes()).hexdigest()}
                return value["afterGroup"]

            def cell(snapshot, row, column):
                return next(c for c in snapshot["coordinates"] if c["row"] == row and c["column"] == column)

            for kind in ("singleText", "singleDate"):
                command("groupCase", name=kind)
                opened = command("groupExpandAll")
                check(len(opened["levels"]) == 1 and opened["rows"] == 8, kind + " returns one hierarchy pointer and eight backing rows")
                check(all(cell(opened, r, 1)["positive"] for r in range(1, 9)), kind + " all backing leaves have positive ordinary first-column geometry")
                model = report["states"][-1]["state"]["outline"]
                roots = [key for key in model["rows"] if model["outline"][key]["kind"] == "group"]
                check(len(roots) == 4 and len(model["rows"]) == 12 and len(set(roots)) == 4,
                      kind + " host capture publishes four distinct native groups and eight leaves")
                collapsed = command("groupCollapseAll")
                check(all(not cell(collapsed, r, 1)["positive"] for r in range(1, 9)), kind + " collapse removes ordinary leaf geometry")
                model = report["states"][-1]["state"]["outline"]
                check(model["rows"] == roots and all(not item["expanded"] for item in model["outline"].values()),
                      kind + " host capture retains root identities and omits collapsed leaves")
                reopened = command("groupExpandAll")
                check(all(cell(reopened, r, 1)["positive"] for r in range(1, 9)) and
                      reopened["levels"] == opened["levels"] and reopened["keys"] == opened["keys"], kind + " reopening restores every leaf and preserves binding values")
                offset = cell(reopened, 1, 1)["frame"][1] - cell(opened, 1, 1)["frame"][1]
                check(all(cell(reopened, r, c)["frame"] == [v + (offset if i in (1, 3) else 0) for i, v in enumerate(cell(opened, r, c)["frame"])]
                          for r in range(1, 9) for c in range(1, 4)), kind + " native reopen changes only a uniform vertical origin")
                report["states"][-1]["nativeVerticalOriginChange"] = offset
                taller = command("groupHeight37")
                check(taller["baseRowHeight"] == 37 and all(cell(taller, r, 1)["frame"][3] - cell(taller, r, 1)["frame"][1] == 37 for r in range(1, 9)),
                      kind + " explicit global height controls the leaf heights")
                check(all(cell(taller, r, 1)["frame"][1] - cell(taller, r-1, 1)["frame"][3] == 37 for r in (4, 6, 8)),
                      kind + " each break gap follows the public global height")
                variable = command("groupVariableHeight")
                check(variable["rowHeights"][1] == 45 and variable["coordinates"] == taller["coordinates"],
                      kind + " individual configured height is ignored by native hierarchy geometry")
                check(report["states"][-1]["image"]["sha256"] == report["states"][-2]["image"]["sha256"],
                      kind + " ignored individual height preserves the native window pixels")
                collapsed = command("groupCollapseAll")
                check(all(cell(collapsed, b, 1)["frame"][1] - cell(collapsed, a, 1)["frame"][1] == collapsed["baseRowHeight"] for a, b in ((1, 4), (4, 6), (6, 8))),
                      kind + " collapsed group markers differ by the public break height")
            finished = True
        except BaseException as error:
            report["failure"] = repr(error)
            raise
        finally:
            finish_run(process, resources, run_id, report, path, finished)
    assert report["passed"]


if __name__ == "__main__":
    main()
