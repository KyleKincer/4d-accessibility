#!/usr/bin/env python3
"""Read every control and edit a distant text range in the owned large form."""

import argparse
import json
import subprocess
import sys
import time

from build_component import sha
import doctor
from prepare_large_form import BUILD, FIXTURE, NOTE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import press_key, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error(
            "--run, Accessibility permission and an unlocked desktop are required"
        )
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before launching the owned fixture")
    compiled = json.loads((BUILD / "large-form-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, (
            "Prepared source changed after compilation"
        )
    for key, relative in [
        (
            "native_sha256",
            "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge",
        ),
        (
            "component_sha256",
            "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ",
        ),
    ]:
        assert sha(FIXTURE / relative) == compiled[key], (
            "Prepared package changed after compilation"
        )
    status = FIXTURE / "Resources/status.json"
    status.unlink(missing_ok=True)
    checks = []
    report = {
        "passed": False,
        "checks": checks,
        "native_sha256": compiled["native_sha256"],
        "component_sha256": compiled["component_sha256"],
    }

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def state():
        if process.poll() is not None:
            raise AssertionError("Owned fixture exited unexpectedly")
        if not status.exists():
            return {}
        # The owning form rewrites its synthetic status after each timer tick.
        # Retry an in-progress write instead of treating it as missing state.
        deadline = time.monotonic() + 1
        while True:
            try:
                value = json.loads(status.read_text(encoding="utf-8-sig"))
                break
            except (OSError, ValueError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.01)
        assert not any(value.get(k) for k in ["error", "bridgeError", "failure"]), value
        return value

    project = FIXTURE / "Project/LargeForm.4DProject"
    with (BUILD / "large-form-desktop.log").open("w") as log:
        process = subprocess.Popen(
            [
                "/usr/bin/arch",
                "-arm64",
                "/Applications/4D/4D.app/Contents/MacOS/4D",
                "--project",
                str(project),
                "--dataless",
                "--opening-mode",
                "interpreted",
                "--webadmin-auto-start",
                "false",
            ],
            stdout=log,
            stderr=log,
        )
    close = None
    try:
        ready, report["application_mode_notice_acknowledged"] = wait_for_start(
            process, project, state, BUILD
        )
        check(
            ready["start"]["ok"],
            "automatic discovery starts around the complete large form",
        )
        app = ax.application(process.pid)
        window = ax.wait_for(
            lambda: next(
                (w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE),
                None,
            ),
            "Owned large form missing",
        )

        def find_group():
            pending = [window]
            while pending:
                item = pending.pop()
                if (item.read("AXIdentifier") or "").startswith("axb.window."):
                    return item
                pending.extend(item.read("AXChildren") or [])
            return None

        group = ax.wait_for(find_group, "Large form was not published", timeout=20)
        started = time.perf_counter()
        controls = {e.read("AXDescription"): e for e in group.read("AXChildren") or []}
        report["enumerationSeconds"] = time.perf_counter() - started
        check(
            len(controls) == 602 and all(str(i) in controls for i in range(600)),
            "all 600 ordinary buttons, the long note and Close are independently discoverable",
        )
        close = controls["Close"]
        note = controls["Large note"]
        started = time.perf_counter()
        check(
            note.read("AXValue") == NOTE,
            "the entire 65,546-character note is readable without truncation",
        )
        report["readNoteSeconds"] = time.perf_counter() - started
        check(
            note.read("AXNumberOfCharacters") == len(NOTE),
            "native character count covers the complete note",
        )
        ticks = state()["ticks"]
        check(
            controls["599"].press() == 0,
            "a control beyond the old node limit accepts AXPress",
        )
        ax.wait_for(
            lambda: state()["pressed"] == "Item599",
            "Last button did not reach its existing object method",
            timeout=20,
        )
        check(True, "the real last button handler ran")
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Button action did not settle",
            timeout=15,
        )
        note.set_boolean("AXFocused", True)
        ax.wait_for(
            lambda: state().get("editor") and note.read("AXFocused") is True,
            "Long note did not receive real focus",
            timeout=20,
        )
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Focus action did not settle",
            timeout=15,
        )
        check(
            note.set_range("AXSelectedTextRange", 60000, 10) == 0,
            "selection beyond the old text limit reaches the editor",
        )
        ax.wait_for(
            lambda: (
                state().get("editor", {}).get("selection") == [60000, 10]
                and note.read("AXSelectedTextRange") == (60000, 10)
            ),
            "Actual long-note selection did not change",
            timeout=20,
        )
        check(
            note.read("AXSelectedText") == NOTE[60000:60010],
            "selected text agrees with the actual distant range",
        )
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Selection action did not settle",
            timeout=15,
        )
        check(
            note.set_string("AXSelectedText", "Changed") == 0,
            "partial replacement reaches the existing long-note editor",
        )
        expected = NOTE[:60000] + "Changed" + NOTE[60010:]
        ax.wait_for(
            lambda: (
                state().get("editor", {}).get("text") == expected
                and note.read("AXValue") == expected
            ),
            "Partial long-note replacement failed",
            timeout=20,
        )
        check(
            note.read("AXValue") == expected,
            "the full accessible value preserves both sides of the partial edit",
        )
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Edit action did not settle",
            timeout=15,
        )
        controls["0"].press()
        ax.wait_for(
            lambda: state()["note"] == expected and state()["pressed"] == "Item000",
            "Long note did not commit through the existing control path",
            timeout=20,
        )
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Partial edit commit did not settle",
        )
        bulk = "New long café 🎸 note.\r" * 2500
        before = state()["beforeCount"]
        started = time.perf_counter()
        check(
            note.set_string("AXValue", bulk) == 0,
            "a complete long Unicode replacement is accepted",
        )
        ax.wait_for(
            lambda: (
                state().get("editor", {}).get("text") == bulk
                and note.read("AXValue") == bulk
            ),
            "Whole long-note insertion did not reach the real editor",
            timeout=25,
        )
        report["wholeReplacementSeconds"] = time.perf_counter() - started
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                == "Text entered in the editor; normal validation runs when editing ends"
            ),
            "Long insertion did not confirm",
            timeout=10,
        )
        check(
            state()["beforeCount"] == before + 2
            and state()["bulkInputLength"] == len(bulk.encode("utf-16-le")) // 2 - 1
            and state()["lastInputLength"] == 1,
            "the existing keystroke handler receives the long text and its trailing Return",
        )
        focus = note.read("AXIdentifier")
        press_key(process, project, TITLE, focus, 6, 1 << 20)
        ax.wait_for(
            lambda: state().get("editor", {}).get("text") == expected,
            "Ordinary Undo did not restore the previous note",
            timeout=15,
        )
        check(True, "ordinary Undo restores the entire previous note")
        ax.wait_for(
            lambda: (
                app.read("AXFocusedUIElement") is not None
                and app.read("AXFocusedUIElement").read("AXIdentifier") == focus
            ),
            "The restored editor's focus was not published after Undo",
            timeout=10,
        )
        press_key(process, project, TITLE, focus, 6, (1 << 20) | (1 << 17))
        ax.wait_for(
            lambda: state().get("editor", {}).get("text") == bulk,
            "Ordinary Redo did not restore the long insertion",
            timeout=15,
        )
        check(True, "ordinary Redo restores the long Unicode insertion")
        commits = state()["commits"]
        controls["0"].press()
        ax.wait_for(
            lambda: state()["note"] == bulk and state()["commits"] > commits,
            "Whole replacement did not commit through existing validation",
            timeout=20,
        )
        check(True, "normal editing completion commits the full long value")
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Whole edit commit did not settle",
        )
        before_rejection = state()["beforeCount"]
        check(
            note.set_string("AXValue", "[reject]" + "x" * 5000) == 0,
            "the long rejection case reaches the existing editor",
        )
        ax.wait_for(
            lambda: (
                group.read("AXHelp") == "Application changed or rejected the text entry"
            ),
            "Existing keystroke rejection was not reported",
            timeout=20,
        )

        def rejection_confirmed():
            current = state()
            return (
                "[reject]" not in current.get("editor", {}).get("text", "")
                and current["note"] == bulk
                and current["beforeCount"] == before_rejection + 1
                and current["lastInputLength"] == 5008
            )

        ax.wait_for(
            rejection_confirmed, "Rejected input did not reach the existing handler"
        )
        check(True, "rejected long input never commits its forbidden value")
        check(
            state()["ticks"] > ticks,
            "the original form timer continues while reading and editing the large form",
        )
        ax.wait_for(
            lambda: (
                group.read("AXHelp")
                not in [
                    "Action queued",
                    "Waiting for the application to complete the action",
                ]
            ),
            "Commit action did not settle",
            timeout=15,
        )
        check(close.press() == 0, "the ordinary close action is accepted")
        process.wait(timeout=15)
        check(
            process.returncode == 0,
            "the ordinary close action exits the large form normally",
        )
        report["passed"] = True
    finally:
        if process.poll() is None and not report["passed"]:
            ax.capture_window(process.pid, BUILD / "large-form-last.png")
        if "group" in locals() and group is not None:
            report["lastReceipt"] = group.read("AXHelp")
        (BUILD / "large-form-runtime-report.json").write_text(
            json.dumps(report, indent=2) + "\n"
        )
        if process.poll() is None and close is not None:
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
