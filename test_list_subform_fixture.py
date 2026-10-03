#!/usr/bin/env python3
"""Check native list-subform accessibility in an owned synthetic 4D window."""

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import quote
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET

from build_component import BUILD, ROOT, sha

sys.path.insert(0, str(ROOT / "tests"))
import doctor
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start

FIXTURE = BUILD / "list-subform-fixture"
TITLE = "AX bridge classic list subform"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run under Rosetta")
    parser.add_argument("--inspect-only", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error(
            "--run, Accessibility permission and an unlocked desktop are required"
        )
    ax.require_test_input()
    for name in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential fixture run")
    compiled = json.loads((BUILD / "list-subform-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        actual = sha(FIXTURE / relative)
        if relative.endswith("catalog.4DCatalog") and actual != expected:
            semantic = hashlib.sha256(
                ET.canonicalize(
                    (FIXTURE / relative).read_text(), strip_text=True
                ).encode()
            ).hexdigest()
            assert (
                semantic == compiled["catalog_semantic_sha256"]
            ), "Catalog definitions changed"
        else:
            assert actual == expected, relative
    for relative, key in (
        (
            "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge",
            "native_sha256",
        ),
        (
            "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ",
            "component_sha256",
        ),
        ("Resources/AXB.FormMetadata.json", "metadata_sha256"),
    ):
        assert sha(FIXTURE / relative) == compiled[key], relative
    resources = FIXTURE / "Resources"
    for name in ("runtime-status.json", "errors.json", "close.json", "closed.json"):
        (resources / name).unlink(missing_ok=True)
    checks = []
    report = {
        "passed": False,
        "compiled": args.compiled,
        "config": {
            k: compiled[k]
            for k in (
                "diagnosticsTest",
                "configured",
                "selectionMode",
                "header",
                "rowHeight",
                "noPrimaryKey",
                "tableParent",
                "textKey",
            )
        },
        "checks": checks,
        "driver_sha256": sha(Path(__file__)),
        **{
            k: compiled[k]
            for k in (
                "native_sha256",
                "component_sha256",
                "metadata_sha256",
                "sources_sha256",
                "preparer_sha256",
            )
        },
    }
    last_state = {}
    vo = None
    receipt_stop = threading.Event()
    receipt_thread = None
    if args.voiceover:
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                str(ROOT / "tests/ReadScreen.swift"),
                "-o",
                str(BUILD / "read-fixture-screen"),
            ],
            check=True,
        )

    def check(ok, name):
        checks.append({"name": name, "passed": bool(ok)})
        print(("PASS: " if ok else "FAIL: ") + name, flush=True)
        if not ok:
            raise AssertionError(name)

    def state():
        nonlocal last_state
        if (resources / "errors.json").exists():
            raise AssertionError((resources / "errors.json").read_text())
        try:
            last_state = json.loads(
                (resources / "runtime-status.json").read_text(encoding="utf-8-sig")
            )
        except (FileNotFoundError, ValueError):
            pass
        return last_state

    project = FIXTURE / "Project/Selection.4DProject"
    log = (BUILD / "list-subform-desktop.log").open("w")
    process = subprocess.Popen(
        [
            "/usr/bin/arch",
            "-x86_64" if args.intel else "-arm64",
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
    try:
        ready, report["startup_notice"] = wait_for_start(
            process,
            project,
            lambda: state() if state().get("listForm") == "Rows" else None,
            BUILD,
        )
        check(
            ready["compiled"] is args.compiled,
            "actual requested desktop execution mode",
        )
        report["architecture"] = ax.process_architecture(process.pid)
        check(
            report["architecture"]
            .upper()
            .replace("-", "")
            .replace("_", "")
            .startswith("X8664" if args.intel else "ARM64"),
            "actual requested desktop architecture",
        )
        app, window = activate_fixture(process, project, TITLE)
        group = ax.wait_for(
            lambda: next(
                (
                    e
                    for e in window.read("AXChildren") or []
                    if e.read("AXIdentifier") == "axb/Grid"
                ),
                None,
            ),
            "Bridge group unavailable",
        )

        def control(name):
            return next(
                (
                    e
                    for e in group.read("AXChildren") or []
                    if e.read("AXIdentifier") == "axb/Grid/" + name
                ),
                None,
            )

        def completed(message):
            ax.wait_for(lambda: group.read("AXHelp") == message, message, timeout=20)

        def press(name):
            check(control(name).perform("AXPress") == 0, "AXPress accepted for " + name)
            completed("Activation dispatched through the control's normal event path")

        def leave_editor():
            check(
                control("Note").set_boolean("AXFocused", True) == 0,
                "ordinary field accepts focus request",
            )
            completed("Keyboard focus confirmed")

        def stored():
            before = state().get("inspections", 0)
            press("Inspect")
            return ax.wait_for(
                lambda: (
                    state().get("privateRead")
                    if state().get("inspections", 0) > before
                    and state().get("privateRead", {}).get("done")
                    else None
                ),
                "Fresh stored values unavailable",
                timeout=20,
            )

        table = ax.wait_for(
            lambda: (
                control("Items")
                if control("Items") and control("Items").read("AXRole") == "AXTable"
                else None
            ),
            "Logical list table unavailable",
            timeout=20,
        )
        if compiled.get("diagnosticsTest"):
            expected = {"classicIdentityRequired", "listSubformParentMetadataRequired"}
            def diagnostic_reasons():
                return {issue.get("reason") for issue in state().get("diagnostics", {}).get("unsupported", [])}
            ax.wait_for(lambda: expected <= diagnostic_reasons(), "Parent diagnostics disappeared while the identity binding failed", timeout=20)
            check(expected <= diagnostic_reasons(), "parent metadata and identity failures are both reported")
            check(table.read("AXEnabled") is False, "invalid list is disabled in the public accessibility tree")
            check("AXPress" not in table.actions(), "invalid binding exposes no mutation action")
            leave_editor()
            check(control("Note").read("AXFocused") is True, "ordinary application editor remains usable")
            report["diagnosticReasons"] = sorted(diagnostic_reasons())
            report["passed"] = True
            return
        ax.wait_for(
            lambda: table.count("AXRows") == 600, "Missing logical rows", timeout=20
        )
        check(
            table.count("AXColumns") == 4,
            "every scalar row control becomes a logical column",
        )
        check(
            not table.cell(0, 0).read("AXChildren")[0].is_settable("AXValue"),
            "native read-only field exposes no editing action",
        )
        if compiled["header"]:
            headers = [column.read("AXHeader") for column in table.read("AXColumns")]
            check(
                [header.read("AXDescription") for header in headers]
                == ["ID", "Description", "Amount", "Approved"],
                "existing header captions name every logical column",
            )
            check(
                all(
                    header.read("AXRole") == "AXStaticText"
                    and "AXPress" not in header.actions()
                    for header in headers
                ),
                "static headers remain read-only reading stops",
            )
        first = table.cell(1, 0)
        final = table.cell(1, 599)
        ax.wait_for(
            lambda: first.read("AXValue") == "Record 0001"
            and final.read("AXValue") == "Record 0600",
            "Distant stored values unavailable",
            timeout=20,
        )
        check(True, "first and distant record values load without selecting records")
        check(
            final.read("AXIdentifier")
            == "axb/Grid/Items/cell/"
            + quote("s:Record 0600" if compiled.get("textKey") else "n:600", safe="")
            + "/ItemName",
            "cell locator uses the stored record key",
        )
        ax.wait_for(
            lambda: state().get("privateRead", {}).get("done"),
            "Private reader did not finish",
            timeout=20,
        )
        check(
            state()["before"] == state()["after"],
            "inspection preserves loaded record, selection, position and modified buffer",
        )
        report["initial"] = state()
        if compiled.get("horizontal"):
            check(
                state().get("scrollbars", [False])[0] is True,
                "native horizontal scrollbar is actually displayed",
            )
        if compiled.get("noPrimaryKey"):
            check(
                not state().get("primaryKey"),
                "actual datastore has no declared primary key",
            )
        ax.capture_window(process.pid, BUILD / "list-subform-initial.png")
        if compiled.get("textKey"):
            for text in ("record 0600", "récord 0600", "record@0600"):
                retained = table.cell(1, 599)
                check(
                    retained.set_text(text) == 0,
                    "native editor accepts changed text identity: " + text,
                )
                completed(
                    "Text entered in the editor; normal validation runs when editing ends"
                )
                leave_editor()
                check(
                    stored()["last"] == text,
                    "changed text identity saves through the original editor",
                )
                table = ax.wait_for(
                    lambda: (
                        control("Items")
                        if control("Items")
                        and control("Items").count("AXRows") == 600
                        and control("Items").cell(1, 599).read("AXIdentifier")
                        == "axb/Grid/Items/cell/"
                        + quote("s:" + text, safe="")
                        + "/ItemName"
                        else None
                    ),
                    "Changed text identity stopped the form or did not become an exact live locator",
                    timeout=20,
                )
                ax.wait_for(
                    lambda: table.cell(1, 599).read("AXValue") == text,
                    "Changed-key value unavailable",
                    timeout=20,
                )
                check(
                    retained.perform("AXScrollToVisible") != 0,
                    "old case/accent/wildcard key cannot operate the renamed row",
                )
            report["passed"] = True
            return
        if args.voiceover:
            from voiceover import VoiceOver

            vo = VoiceOver(
                process,
                project,
                TITLE,
                BUILD / "list-subform-voiceover",
                BUILD / "read-fixture-screen",
            )
            vo.start()
            vo.key("home")
            vo.key("down", shift=True)
            vo.key("home")
            vo.key("right")
            end = vo.key("end")
            vo.key("left")
            final_caption = vo.key("left")
            check(
                "row600of600" in end.replace(" ", ""),
                "VoiceOver reaches the final logical record",
            )
            check(
                "Record 0600" in final_caption,
                "VoiceOver reads the distant record text",
            )
            vo.key("right")
            caption = vo.key("right")
            check(
                "Approved" in caption
                and "checkbox" in caption.lower().replace(" ", ""),
                "VoiceOver reads the native checkbox role and caption",
            )
            check(
                "unchecked" in caption.lower(),
                "fresh VoiceOver fixture starts with the unchecked native value",
            )
            # VoiceOver can request a reveal after activation, replacing AXHelp's
            # latest receipt before OCR returns. Capture transitions without
            # replaying input, and require the native result and saved value.
            report["voiceover_help_history"] = []

            def observe_help():
                previous = None
                while not receipt_stop.is_set():
                    help_text = group.read("AXHelp")
                    if help_text != previous:
                        report["voiceover_help_history"].append(help_text)
                        previous = help_text
                    receipt_stop.wait(0.02)

            receipt_thread = threading.Thread(target=observe_help, daemon=True)
            receipt_thread.start()
            vo.key("space")
            ax.wait_for(
                lambda: (
                    table.cell(3, 599).read("AXChildren")[0].read("AXValue") == 1
                    and group.read("AXHelp")
                    in (
                        "List subform checkbox state confirmed",
                        "List subform cell is visible",
                    )
                ),
                "VoiceOver checkbox did not change",
                timeout=20,
            )
            receipt_stop.set()
            receipt_thread.join(timeout=2)
            check(
                "List subform checkbox state confirmed"
                in report["voiceover_help_history"],
                "VoiceOver checkbox receives a successful application completion receipt",
            )
            check(
                sum(
                    e["event"] == 4 and e["object"] == "Approved"
                    for e in state()["events"]
                )
                == 1,
                "VoiceOver activation runs the original checkbox handler once",
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

            report["checkbox_speech"] = ax.wait_for(
                confirmed_speech,
                "VoiceOver did not announce the confirmed checkbox state",
                timeout=20,
            )
            check(True, "VoiceOver announces the confirmed checkbox state")
            leave_editor()
            check(
                stored()["approved"] is True,
                "VoiceOver checkbox result persists through the native editor",
            )
            report["speech"] = vo.steps
            report["passed"] = True
            return
        check(
            final.perform("AXScrollToVisible") == 0,
            "distant cell accepts reveal request",
        )
        completed("List subform cell is visible")
        check(
            state().get("scroll", 0) >= 590,
            "native subform scroll reaches the distant record",
        )
        press("Modify")
        ax.wait_for(
            lambda: state().get("before", {}).get("position") == 2
            and state().get("privateRead", {}).get("done"),
            "Modified buffer inspection incomplete",
            timeout=20,
        )
        mutation = json.loads(
            (resources / "modified-buffer.json").read_text(encoding="utf-8-sig")
        )
        check(
            mutation["modified"] and mutation["name"] == "Unsaved buffer",
            "original handler creates the modified native record",
        )
        check(
            state()["before"] == state()["after"],
            "inspection preserves the native post-paint record state",
        )
        if compiled["selectionMode"] == "multiple" and not compiled["header"]:
            check(
                state()["before"]["modified"]
                and state()["before"]["name"] == "Unsaved buffer",
                "ordinary multiple-selection list retains its unsaved native buffer",
            )
        check(
            state()["privateRead"]["second"] == "Record 0002",
            "isolated reader sees saved data without saving the unsaved buffer",
        )
        report["modified"] = state()
        if args.inspect_only:
            report["passed"] = True
            return
        editor = final.read("AXChildren")[0]
        check(
            editor.is_settable("AXValue"),
            "native enterable row field exposes text editing",
        )
        check(
            editor.set_text("Ax blocked") == 0,
            "native field accepts a request subject to its existing keystroke filter",
        )
        completed("Application changed or rejected the text entry")
        check(
            final.read("AXValue") == "A",
            "original keystroke filter rejects x and stops the action with its actual partial result",
        )
        desired_text = "AX list edit 🎸" + (
            "\nSecond line" if compiled["rowHeight"] > 24 else ""
        )
        check(
            editor.set_text(desired_text) == 0,
            "row field accepts the Unicode text request",
        )
        expected_text = desired_text.replace("\n", "\r")
        ax.wait_for(
            lambda: final.read("AXValue") == expected_text,
            "Native row editor did not accept text",
            timeout=20,
        )
        completed(
            "Text entered in the editor; normal validation runs when editing ends"
        )
        check(
            editor.set_range("AXSelectedTextRange", 13, 2) == 0,
            "row editor accepts a complete supplementary-character selection",
        )
        completed("Editor selection confirmed")
        check(
            editor.read("AXSelectedText") == "🎸",
            "native overlay selection identifies the supplementary character",
        )
        check(
            editor.set_string("AXSelectedText", "🎹") == 0,
            "native overlay accepts partial Unicode replacement",
        )
        expected_text = expected_text.replace("🎸", "🎹")
        ax.wait_for(
            lambda: final.read("AXValue") == expected_text,
            "Partial native replacement did not complete",
            timeout=20,
        )
        completed(
            "Text entered in the editor; normal validation runs when editing ends"
        )
        leave_editor()
        fresh = stored()
        check(
            fresh["last"] == expected_text,
            "leaving the original row editor saves the complete text",
        )
        check(
            sum(
                e["event"] == 20 and e["object"] == "ItemName"
                for e in state()["events"]
            )
            == 1,
            "original text data-change handler runs exactly once",
        )
        checkbox = table.cell(3, 599).read("AXChildren")[0]
        check(
            checkbox.read("AXRole") == "AXCheckBox" and checkbox.read("AXValue") == 0,
            "Boolean row field exposes the current checkbox state",
        )
        check(checkbox.perform("AXPress") == 0, "native checkbox accepts AXPress")
        completed("List subform checkbox state confirmed")
        ax.wait_for(
            lambda: checkbox.read("AXValue") == 1,
            "Confirmed checkbox value did not reach AX",
            timeout=15,
        )
        check(
            checkbox.read("AXValue") == 1, "native checkbox reports its changed state"
        )
        leave_editor()
        fresh = stored()
        check(
            fresh["approved"] is True,
            "checkbox activation persists through the original row control",
        )
        check(
            sum(
                e["event"] == 4 and e["object"] == "Approved" for e in state()["events"]
            )
            == 1,
            "original checkbox click handler runs exactly once",
        )
        mode = compiled["selectionMode"]
        if mode in ("none", "default"):
            check(
                not table.is_settable("AXSelectedRows"),
                "nonselectable list does not expose row selection",
            )
        else:
            desired = [table.slice("AXRows", 599, 1)[0]]
            if mode == "multiple":
                desired.insert(0, table.slice("AXRows", 1, 1)[0])
            check(
                table.set_elements("AXSelectedRows", desired) == 0,
                "native rows accept the selection request",
            )
            completed("List subform selection confirmed")
            check(
                [e.read("AXIdentifier") for e in table.read("AXSelectedRows")]
                == [e.read("AXIdentifier") for e in desired],
                "native selection matches exactly the requested records",
            )
            check(
                table.set_elements("AXSelectedRows", []) == 0,
                "native list accepts clearing its selection",
            )
            completed("List subform selection confirmed")
            check(
                not table.read("AXSelectedRows"),
                "native command-clicks clear selection without a replacement callback",
            )
        retired = table.cell(1, 599)
        press("Rebind")
        ax.wait_for(
            lambda: control("Items").cell(1, 599).read("AXValue") == "600.25",
            "Rebound field value unavailable",
            timeout=20,
        )
        check(
            retired.perform("AXScrollToVisible") != 0,
            "retained cell retires after rebinding the same named row control",
        )
        table = control("Items")
        press("Availability")
        ax.wait_for(
            lambda: table.read("AXEnabled") is False,
            "Disabled parent state unavailable",
        )
        check(
            not table.cell(1, 599).read("AXChildren")[0].is_settable("AXValue"),
            "disabled list exposes no cell edit action",
        )
        press("Availability")
        ax.wait_for(
            lambda: table.read("AXEnabled") is True,
            "List did not regain native enabled state",
        )
        check(
            table.cell(1, 599).read("AXChildren")[0].is_settable("AXValue"),
            "reenabled list restores native cell permission",
        )
        press("Visibility")
        ax.wait_for(lambda: control("Items") is None, "Hidden list remains in the tree")
        check(not table.read("AXRows"), "retained hidden table exposes no live rows")
        press("Visibility")
        table = ax.wait_for(
            lambda: (
                control("Items")
                if control("Items") and control("Items").count("AXRows") == 600
                else None
            ),
            "Shown list did not return",
            timeout=20,
        )
        ax.wait_for(
            lambda: table.cell(1, 599).read("AXValue") == "600.25",
            "Restored field value did not finish loading",
            timeout=20,
        )
        check(True, "restored list keeps its real rebound field")
        if compiled["configured"]:
            retired = table.cell(1, 599)
            press("Ready")
            ax.wait_for(
                lambda: control("Items").read("AXEnabled") is False,
                "Loading list did not disable",
            )
            check(
                retired.perform("AXScrollToVisible") != 0,
                "readiness guard retires the previous live cell",
            )
            press("Ready")
            table = ax.wait_for(
                lambda: (
                    control("Items")
                    if control("Items") and control("Items").count("AXRows") == 600
                    else None
                ),
                "Ready list did not return",
                timeout=20,
            )
            ax.wait_for(
                lambda: table.cell(1, 599).read("AXValue") == "600.25",
                "Ready field value did not finish loading",
                timeout=20,
            )
            check(True, "ready list restores its native field binding")
        report["passed"] = True
    finally:
        receipt_stop.set()
        if receipt_thread:
            receipt_thread.join(timeout=2)
        if vo:
            report["speech"] = vo.steps
            vo.stop()
        try:
            report["final"] = state()
            if "group" in locals():
                report["finalHelp"] = group.read("AXHelp")
        except Exception as error:
            report["passed"] = False
            report["final_error"] = str(error)
        if process.poll() is None:
            (resources / "close.json").write_text("{}")
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)
        log.close()
        report["exit_code"] = process.returncode
        if report["passed"]:
            closed = process.returncode == 0
            checks.append(
                {
                    "name": "ordinary form close and desktop exit succeed",
                    "passed": closed,
                }
            )
            report["passed"] = closed
        (BUILD / "list-subform-desktop-report.json").write_text(
            json.dumps(report, indent=2) + "\n"
        )
        if not report["passed"] and sys.exc_info()[0] is None:
            raise AssertionError(
                "List-subform acceptance failed; see the desktop report"
            )
    if not report["passed"]:
        raise AssertionError("List-subform acceptance failed; see the desktop report")
    print("PASS: " + str(len(checks)) + " list-subform AX checks")


if __name__ == "__main__":
    main()
