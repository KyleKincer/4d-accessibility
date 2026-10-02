#!/usr/bin/env python3
"""Validate the owned classic-selection fixture through external macOS AX."""

import argparse
import hashlib
import xml.etree.ElementTree as ET
import json
from pathlib import Path
import subprocess
import sys
import time
from build_component import BUILD, ROOT, sha
from prepare_selection_fixture import FIXTURE, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
import doctor
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    parser.add_argument("--inspect-only", action="store_true")
    parser.add_argument("--selection-only", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error(
            "--run, Accessibility permission and an unlocked desktop are required"
        )
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before this owned fixture run")
    compiled = json.loads((BUILD / "selection-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        actual = sha(FIXTURE / relative)
        if relative == "Project/Sources/catalog.4DCatalog" and actual != expected:
            semantic = hashlib.sha256(
                ET.canonicalize(
                    (FIXTURE / relative).read_text(), strip_text=True
                ).encode()
            ).hexdigest()
            assert semantic == compiled["catalog_semantic_sha256"], (
                "Catalog definitions changed"
            )
        else:
            assert actual == expected, relative
    assert (
        sha(
            FIXTURE
            / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"
        )
        == compiled["native_sha256"]
    )
    assert (
        sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")
        == compiled["component_sha256"]
    )
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    assert config["bridge"]
    checks = []
    report = {
        "passed": False,
        "compiled": args.compiled,
        "voiceover": args.voiceover,
        "config": config,
        "checks": checks,
        "native_sha256": compiled["native_sha256"],
        "component_sha256": compiled["component_sha256"],
        "sources_sha256": compiled["sources_sha256"],
        "driver_sha256": sha(ROOT / "test_selection_fixture.py"),
        "preparer_sha256": compiled["preparer_sha256"],
    }
    for name in ("runtime-status.json", "errors.json", "closed.json"):
        (FIXTURE / "Resources" / name).unlink(missing_ok=True)
    last = {}

    def check(ok, message):
        checks.append({"name": message, "passed": bool(ok)})
        print(("PASS: " if ok else "FAIL: ") + message, flush=True)
        if not ok:
            raise AssertionError(message)

    def state():
        nonlocal last
        if (FIXTURE / "Resources/errors.json").exists():
            raise AssertionError((FIXTURE / "Resources/errors.json").read_text())
        try:
            last = json.loads(
                (FIXTURE / "Resources/runtime-status.json").read_text(
                    encoding="utf-8-sig"
                )
            )
        except (FileNotFoundError, ValueError):
            pass
        return last

    project = FIXTURE / "Project/Selection.4DProject"
    with (BUILD / "selection-desktop.log").open("w") as log:
        process = subprocess.Popen(
            [
                "/usr/bin/arch",
                "-arm64",
                "/Applications/4D/4D.app/Contents/MacOS/4D",
                "--project",
                str(project),
                "--data",
                str(FIXTURE / "synthetic.4dd"),
                "--opening-mode",
                "compiled" if args.compiled else "interpreted",
                "--webadmin-auto-start",
                "false",
            ],
            stdout=log,
            stderr=log,
        )
    close = None
    vo = None
    try:
        ready, report["startup_notice"] = wait_for_start(
            process,
            project,
            lambda: state() if state().get("runId") == config["runId"] else None,
            BUILD,
        )
        check(
            ready["compiled"] is args.compiled,
            "actual requested desktop execution mode",
        )
        report["architecture"] = ax.process_architecture(process.pid)
        check(
            report["architecture"].replace("-", "").startswith("ARM64"),
            "actual ARM execution",
        )
        app, window = activate_fixture(process, project, TITLE)

        def find(label, role=None):
            pending = [window]
            while pending:
                item = pending.pop()
                if label in (item.read("AXDescription"), item.read("AXTitle")) and (
                    role is None or item.read("AXRole") == role
                ):
                    return item
                if item.read("AXRole") != "AXTable":
                    pending.extend(item.read("AXChildren") or [])

        table = ax.wait_for(lambda: find("Records", "AXTable"), "Classic table missing")
        ax.wait_for(
            lambda: table.count("AXRows") == 600,
            "Classic rows never published",
            timeout=20,
        )
        close = find("Close", "AXButton")
        check(close is not None, "ordinary controls remain exposed")
        report["initial"] = state()
        pending = [window]
        group = None
        while pending:
            candidate = pending.pop()
            identifier = candidate.read("AXIdentifier")
            if isinstance(identifier, str) and identifier.startswith("axb.window."):
                group = candidate
                break
            if candidate.read("AXRole") != "AXTable":
                pending.extend(candidate.read("AXChildren") or [])
        check(
            state()["columnPointer"][:2] == [1, 2],
            "public object pointer resolves the stored field without evaluating its expression",
        )
        check(
            table.count("AXRows") == 600 and table.count("AXColumns") == 4,
            "all logical rows and scalar columns are exposed",
        )
        order = list(range(600, 0, -1)) if config["named"] else list(range(1, 601))

        def value(column, row, text):
            return ax.wait_for(
                lambda: (
                    table.cell(column, row)
                    if table.cell(column, row).read("AXValue") == text
                    else None
                ),
                "Expected cell value did not load: " + text,
                timeout=20,
            )

        value(1, 0, "Record " + f"{order[0]:04d}")
        check(True, "first row keeps the native current/named selection order")
        value(1, 599, "Record " + f"{order[-1]:04d}")
        check(True, "distant values load without moving the form record")
        report["after_reads"] = state()

        def settle():
            ax.wait_for(
                lambda: (
                    group.read("AXHelp")
                    not in (
                        None,
                        "Action queued",
                        "Waiting for the application to complete the action",
                    )
                ),
                "Action did not settle",
                timeout=20,
            )

        if args.inspect_only:
            report["passed"] = True
            return
        if args.voiceover:
            from voiceover import VoiceOver

            vo = VoiceOver(
                process,
                project,
                TITLE,
                BUILD / "selection-voiceover",
                BUILD / "read-fixture-screen",
            )
            vo.start()
            vo.key("home")
            vo.key("down", shift=True)
            first = vo.key("home")
            vo.key("right")
            description = vo.read_caption()
            end = vo.key("end")
            vo.key("left")
            vo.key("left")
            final = vo.read_caption()
            report["speech"] = vo.steps
            check(
                "row600of600" in end.replace(" ", ""),
                "VoiceOver reaches the final logical row",
            )
            check(
                "Record " + f"{order[-1]:04d}" in final,
                "VoiceOver reads the final-row text",
            )
            vo.key("space")
            ax.wait_for(
                lambda: state().get("selectedCount") == 1,
                "VoiceOver selection did not reach the native highlight set",
            )
            ax.wait_for(
                lambda: (
                    state().get("hooks") == 1
                    and state().get("record", {}).get("id") == order[-1]
                    and group.read("AXHelp")
                    in ("List box selection confirmed", "Cell editor is focused")
                ),
                "VoiceOver selection did not complete through the original controller",
                timeout=20,
            )
            check(
                True,
                "VoiceOver selects through the native list box and existing controller",
            )
            vo.key("right")
            caption = vo.key("right")
            check(
                "checkbox" in caption.lower().replace(" ", "")
                and "Approved" in caption,
                "VoiceOver reads the native classic-field checkbox",
            )
            vo.key("space")
            ax.wait_for(
                lambda: (
                    state().get("changes") == 1
                    and state().get("edgeChecked") is True
                    and group.read("AXHelp")
                    not in (
                        None,
                        "Action queued",
                        "Waiting for the application to complete the action",
                    )
                ),
                "VoiceOver checkbox did not commit through the native handler",
                timeout=20,
            )
            check(
                True,
                "VoiceOver checkbox activation commits through the original handler once",
            )

            report["checkbox_feedback_samples"] = []
            speech_started = time.monotonic()

            def confirmed_speech():
                caption = vo.read_caption()
                report["checkbox_feedback_samples"].append(
                    {
                        "seconds": round(time.monotonic() - speech_started, 3),
                        "caption": caption,
                    }
                )
                return (
                    caption
                    if "checked" in caption.lower()
                    and "unchecked" not in caption.lower()
                    else None
                )

            feedback = ax.wait_for(
                confirmed_speech,
                "VoiceOver did not announce the confirmed checkbox state",
                timeout=20,
            )
            report["checkbox_speech"] = feedback
            check(True, "VoiceOver announces the confirmed classic checkbox state")
            report["passed"] = True
            return
        for label, expected in (
            []
            if args.selection_only
            else [
                (
                    "Modify",
                    {
                        "loaded": True,
                        "modified": True,
                        "id": 2,
                        "name": "Unsaved buffer",
                    },
                ),
                ("Unload", {"loaded": False, "modified": False}),
                (
                    "New",
                    {
                        "loaded": True,
                        "modified": True,
                        "id": 999,
                        "name": "Unsaved new buffer",
                    },
                ),
            ]
        ):
            check(
                find(label, "AXButton").press() == 0,
                "native " + label.lower() + " control accepts AX activation",
            )
            settle()
            baseline = ax.wait_for(
                lambda: (
                    state()["record"]
                    if all(state()["record"].get(k) == v for k, v in expected.items())
                    else None
                ),
                "Native record state was not established: " + label,
            )
            # Wait through many real inspection/paint cycles, including distant reads.
            started = time.monotonic()
            while time.monotonic() - started < 2:
                table.cell(1, 599).read("AXValue")
                current = state()["record"]
                assert current == baseline, (label, baseline, current)
                time.sleep(0.1)
            check(
                True,
                "inspection preserves "
                + label.lower()
                + " record state across repeated UI polls",
            )
            if label == "Modify":
                ax.capture_window(
                    process.pid, BUILD / "selection-modified.png", include_shadow=False
                )
                report["modifiedRowAXValue"] = table.cell(1, order.index(2)).read(
                    "AXValue"
                )
                check(
                    report["modifiedRowAXValue"] == "Record 0002",
                    "inspection reads the value painted by the native list while preserving the separate unsaved buffer",
                )
        check(
            find("Unload", "AXButton").press() == 0,
            "unload the record before native grid actions",
        )
        ax.wait_for(lambda: not state()["record"]["loaded"], "Record remained loaded")
        settle()
        report["beforeSelectionHelp"] = group.read("AXHelp")
        rows = table.slice("AXRows", 0, 1) + table.slice("AXRows", 599, 1)
        before = state()["hooks"]
        check(
            table.set_elements("AXSelectedRows", rows) == 0,
            "select first and last rows through AX",
        )
        ax.wait_for(
            lambda: (
                state().get("selectedCount") == 2 and state().get("hooks") == before + 1
            ),
            "Native highlight set/controller did not accept two rows",
        )
        ax.wait_for(
            lambda: group.read("AXHelp") == "List box selection confirmed",
            "Multi-selection was not confirmed",
            timeout=20,
        )
        check(
            True,
            "native highlight count and original controller confirm multi-selection",
        )
        if args.selection_only:
            report["passed"] = True
            return
        far_index = order.index(600)
        cell = value(1, far_index, "Record 0600")
        check(
            cell.perform("AXScrollToVisible") == 0, "reveal a distant native text cell"
        )
        ax.wait_for(
            lambda: (
                cell.read("AXPosition") is not None
                and any(
                    r.read("AXIndex") == far_index
                    for r in table.read("AXVisibleRows") or []
                )
            ),
            "Distant row was not revealed",
        )
        ax.wait_for(
            lambda: group.read("AXHelp") == "Cell is visible",
            "Reveal did not complete",
            timeout=20,
        )
        check(
            cell.set_string("AXValue", "Changed native value") == 0,
            "set text through the original native editor",
        )
        ax.wait_for(
            lambda: state().get("edited") == "Changed native value",
            "Native editor did not receive complete text",
            timeout=20,
        )
        note = find("Note", "AXTextField")
        check(
            note is not None and note.set_boolean("AXFocused", True) == 0,
            "leave the native editor through the ordinary field",
        )
        ax.wait_for(
            lambda: state().get("farValue") == "Changed native value",
            "Native edit did not persist",
            timeout=20,
        )
        check(state()["changes"] == 1, "native validation/commit handler runs once")
        value(1, far_index, "Changed native value")
        check(True, "accessibility reports the persisted classic field value")
        old_row = table.slice("AXRows", far_index, 1)[0]
        old_id = old_row.read("AXIdentifier")
        check(
            find("Sort", "AXButton").press() == 0,
            "sort through the existing application method",
        )
        sorted_index = 599 if config["named"] else 0
        ax.wait_for(
            lambda: (
                table.slice("AXRows", sorted_index, 1)[0].read("AXIdentifier") == old_id
            ),
            "Stable row identity was lost after sort",
            timeout=20,
        )
        value(1, sorted_index, "Changed native value")
        check(True, "sort preserves stable identity and displays the original record")
        check(
            old_row.read("AXIndex") == sorted_index,
            "retained row follows its record after sorting",
        )
        settle()
        checkbox = ax.wait_for(
            lambda: next(
                (
                    child
                    for child in table.cell(3, sorted_index).read("AXChildren") or []
                    if child.read("AXRole") == "AXCheckBox"
                ),
                None,
            ),
            "Native checkbox missing",
        )
        ax.wait_for(
            lambda: checkbox.read("AXValue") == 0, "Checkbox value did not load"
        )
        check(
            checkbox.press() == 0,
            "activate the original classic-field checkbox through AX",
        )
        ax.wait_for(
            lambda: state().get("farChecked") is True,
            "Native checkbox did not persist",
            timeout=20,
        )
        ax.wait_for(
            lambda: checkbox.read("AXValue") == 1,
            "Accessibility checkbox did not update",
            timeout=20,
        )
        check(
            state()["changes"] == 2,
            "checkbox and text each invoke their existing commit handler once",
        )
        settle()
        retained = table.cell(1, sorted_index)
        check(
            find("Hide", "AXButton").press() == 0,
            "hide the grid through the existing form method",
        )
        ax.wait_for(
            lambda: (
                state().get("gridVisible") is False
                and retained.read("AXSize") in (None, (0.0, 0.0))
            ),
            "Hidden grid kept active cells",
        )
        settle()
        check(
            state()["buttons"].count("Hide") == 1,
            "hide invokes its original handler once before the next action",
        )
        check(
            retained.set_string("AXValue", "Must not edit") != 0,
            "hidden retained cell rejects editing",
        )
        check(find("Hide", "AXButton").press() == 0, "restore the original grid")
        ax.wait_for(
            lambda: state().get("gridVisible") is True and find("Records", "AXTable"),
            "Grid did not return",
        )
        settle()
        check(
            state()["buttons"].count("Hide") == 2,
            "restore invokes its original handler once",
        )
        table = find("Records", "AXTable")
        value(1, sorted_index, "Changed native value")
        check(
            state()["farValue"] == "Changed native value" and state()["changes"] == 2,
            "hidden stale request leaves persisted data and handlers unchanged",
        )
        report["passed"] = True
    finally:
        if vo:
            vo.stop()
        report["final"] = state()
        if "group" in locals() and group:
            try:
                report["finalHelp"] = group.read("AXHelp")
            except RuntimeError:
                pass
        if process.poll() is None:
            if close:
                try:
                    if report["passed"]:
                        settle()
                    close.press()
                    process.wait(timeout=10)
                except (RuntimeError, subprocess.TimeoutExpired):
                    pass
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        report["exit_code"] = process.returncode
        if report["passed"]:
            report["passed"] = process.returncode == 0
            check(report["passed"], "normal form close and desktop exit succeed")
        (BUILD / "selection-desktop-report.json").write_text(
            json.dumps(report, indent=2) + "\n"
        )
    print("PASS: " + str(len(checks)) + " classic-selection AX checks")


if __name__ == "__main__":
    main()
