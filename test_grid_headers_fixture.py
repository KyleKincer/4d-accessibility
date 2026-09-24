#!/usr/bin/env python3
"""Verify native header actions against real 4D handlers and sort state."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from build_component import sha
from prepare_grid_fixture import BUILD, FIXTURE, ROOT, TITLE
sys.path.insert(0, str(ROOT / "tests"))
import doctor
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, existing Accessibility permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the owned fixture")
    compiled = json.loads((BUILD / "logical-grid-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, relative
    for relative, key in [("Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge", "native_sha256"),
                          ("Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ", "component_sha256")]:
        assert sha(FIXTURE / relative) == compiled[key]
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    assert config["headers"]
    status = FIXTURE / "Resources/runtime-status.json"
    error_file = FIXTURE / "Resources/native-error.json"
    command_file = FIXTURE / "Resources/header-command.json"
    for p in [status, error_file, command_file, FIXTURE / "Resources/closed.json"]:
        p.unlink(missing_ok=True)
    report = {"passed": False, **config, "checks": [], "actions": [], "native_sha256": compiled["native_sha256"],
              "component_sha256": compiled["component_sha256"]}
    last_state = {}
    def state():
        nonlocal last_state
        if error_file.exists():
            raise AssertionError(error_file.read_text(encoding="utf-8-sig"))
        try:
            last_state = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        assert not last_state.get("bridgeError") and not last_state.get("failure"), last_state
        return last_state
    def check(condition, label):
        report["checks"].append({"passed": bool(condition), "name": label})
        print(("PASS: " if condition else "FAIL: ") + label, flush=True)
        assert condition, label
    project = FIXTURE / "Project/LogicalGridFixture.4DProject"
    command = ["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
               *(["--data", str(FIXTURE / "synthetic.4dd")] if config["kind"] == "entity" else ["--dataless"]),
               "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    with (BUILD / "grid-headers-desktop.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
    close = group = None
    try:
        ready, report["application_mode_notice_acknowledged"] = wait_for_start(
            process, project, lambda: state() if state().get("runId") == config["runId"] else None, BUILD)
        check(ready.get("start", {}).get("ok") is True and ready["compiled"] is args.compiled, "4D starts the header fixture in the requested execution mode")
        app, window = activate_fixture(process, project, TITLE)
        def root():
            pending = [window]
            while pending:
                node = pending.pop()
                if (node.read("AXIdentifier") or "").startswith("axb.window."):
                    return node
                if node.read("AXRole") != "AXTable":
                    pending.extend(node.read("AXChildren") or [])
        group = ax.wait_for(root, "Bridge group missing")
        def find(label):
            return next((n for n in group.read("AXChildren") or [] if label in [n.read("AXDescription"), n.read("AXTitle")]), None)
        table = ax.wait_for(lambda: find("Invoice lines"), "Grid missing")
        close = find("Close")
        def headers():
            return table.read("AXColumnHeaderUIElements") or []
        def header(label):
            return next((h for h in headers() if label in [h.read("AXDescription"), h.read("AXTitle"), h.read("AXValue")]), None)
        description = ax.wait_for(lambda: header("Description"), "Description header missing")
        amount = ax.wait_for(lambda: header("Amount"), "Amount header missing")
        check(len(headers()) == 2 and table.count("AXRows") == 599, "complete grid exposes both visible column headers")
        check(description.read("AXRole") == "AXButton" and description.read("AXSubrole") == "AXSortButton", "sortable header has native button semantics")
        def settle():
            time.sleep(.25)
            return ax.wait_for(lambda: state() and group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action") and group.read("AXHelp"), "Header action did not settle", timeout=15)
        sequence = 0
        def configure(**options):
            nonlocal sequence
            sequence += 1
            temporary = command_file.with_suffix(".tmp")
            temporary.write_text(json.dumps({"sequence": sequence, **options}))
            temporary.replace(command_file)
            ax.wait_for(lambda: state().get("sequence") == sequence, "Header configuration was not consumed")
            time.sleep(.25)
        def press(target, label):
            before = len(state()["events"])
            check(target.press() == 0, label + " accepts AX activation")
            ax.wait_for(lambda: len(state()["events"]) > before, label + " did not reach its native handler")
            receipt = settle()
            events = state()["events"][before:]
            report["actions"].append({"label": label, "receipt": receipt, "events": events, "headers": state()["headers"], "first_rows": state()["rows"][:3]})
            check(receipt == "Column header activated", label + " confirms native input delivery")
            return events
        retained_id = description.read("AXIdentifier")
        press(description, "first sort")
        first_sort = state()["headers"]["ItemNameHeader"].get("sort")
        check(first_sort in (1, 2), "native header variable reports the resulting sort direction")
        expected = "AXAscendingSortDirection" if first_sort == 1 else "AXDescendingSortDirection"
        ax.wait_for(lambda: description.read("AXSortDirection") == expected, "Accessible sort direction differs from native state")
        check(description.read("AXIdentifier") == retained_id, "sorting retains the header identity")
        press(description, "reverse sort")
        check(state()["headers"]["ItemNameHeader"].get("sort") in (1, 2) and state()["headers"]["ItemNameHeader"]["sort"] != first_sort, "second activation reverses native sorting")
        configure(behavior="reject")
        before_rows = state()["rows"]
        press(description, "rejected sort")
        check(state()["rows"] == before_rows, "existing On Header Click rejection preserves row order")
        configure(behavior="custom")
        press(description, "custom sort")
        check(state()["events"][-1]["behavior"] == "custom", "existing custom sort handler remains in charge")
        configure(behavior="native")
        press(amount, "offscreen amount header")
        check(state()["scroll"][1] > 1, "offscreen header activation scrolls the real list box")
        check(amount.read("AXEnabled") is True, "read-only numeric column still has an operable header")
        configure(headers=False)
        ax.wait_for(lambda: not headers(), "Hidden headers remain in the tree")
        before_events = len(state()["events"])
        description.press()
        time.sleep(.35)
        check(len(state()["events"]) == before_events, "retained hidden header cannot invoke its handler")
        configure(headers=True, enabled=False)
        disabled_at = time.monotonic()
        ax.wait_for(lambda: headers() and header("Description").read("AXEnabled") is False, "Disabled grid header is still enabled", timeout=20)
        report["disabled_state_delay_seconds"] = time.monotonic() - disabled_at
        check("AXPress" not in header("Description").actions(), "disabled header offers no activation")
        configure(enabled=True, empty=True)
        ax.wait_for(lambda: table.count("AXRows") == 0, "Empty grid still exposes rows")
        check(len(headers()) == 2, "empty grid retains its headers")
        press(header("Description"), "empty-grid header")
        check(table.count("AXRows") == 0, "header activation does not create or select a row")
        check(close.press() == 0, "normal form close remains accessible")
        process.wait(timeout=15)
        check(process.returncode == 0, "owned 4D fixture closes normally")
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        if process.poll() is None:
            ax.capture_window(process.pid, BUILD / "grid-headers-failure.png")
        if group is not None and process.poll() is None:
            report["failure_headers"] = [{key: h.read(key) for key in ("AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue", "AXEnabled", "AXIdentifier", "AXPosition", "AXSize")} for h in headers()]
            report["failure_table"] = {key: table.read(key) for key in ("AXEnabled", "AXTitle", "AXDescription")}
        raise
    finally:
        report["final_state"] = last_state
        if group is not None and process.poll() is None:
            report["final_receipt"] = group.read("AXHelp")
        (BUILD / "grid-headers-runtime-report.json").write_text(json.dumps(report, indent=2) + "\n")
        if process.poll() is None:
            if close is not None:
                close.press()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    main()
