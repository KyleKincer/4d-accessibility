#!/usr/bin/env python3
"""Validate complete ordinary controls inside real scrolling 4D page subforms."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from build_component import sha
from prepare_scroll_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import doctor
import mac_ax as ax
from fixture_desktop import wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, existing Accessibility permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before this owned fixture run")
    compiled = json.loads((BUILD / "scroll-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, "Prepared source changed after compilation"
    assert sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge") == compiled["native_sha256"]
    assert sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ") == compiled["component_sha256"]
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    status = FIXTURE / "Resources/state.json"
    error_file = FIXTURE / "Resources/error.json"
    status.unlink(missing_ok=True)
    error_file.unlink(missing_ok=True)
    report = {"passed": False, "mode": "voiceover" if args.voiceover else "actions", "checks": [], **config,
              "native_sha256": compiled["native_sha256"], "component_sha256": compiled["component_sha256"]}

    def check(condition, name):
        report["checks"].append({"name": name, "passed": bool(condition)})
        print(("PASS: " if condition else "FAIL: ") + name, flush=True)
        assert condition, name

    latest_state = {}

    def state():
        nonlocal latest_state
        if error_file.exists():
            raise AssertionError("Native 4D error: " + error_file.read_text(encoding="utf-8-sig"))
        try:
            value = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            # File.setText can be observed between truncation and completion.
            # Retain the last complete sample; timer waits still require a new tick.
            return latest_state
        if value.get("error"):
            raise AssertionError("Bridge error: " + str(value))
        latest_state = value
        return value

    project = FIXTURE / "Project/ScrollFixture.4DProject"
    command = ["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
               "--dataless", "--opening-mode", "interpreted", "--webadmin-auto-start", "false"]
    with (BUILD / "scroll-desktop.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
    close = None
    try:
        ready, report["application_mode_notice_acknowledged"] = wait_for_start(
            process, project, lambda: state() if state().get("runId") == config["runId"] else None, BUILD)
        check(ready.get("start", {}).get("ok") is True, "automatic root starts without child bridge hooks")
        report["architecture"] = ax.process_architecture(process.pid)
        check(report["architecture"].replace("-", "").startswith("ARM64"), "actual native ARM desktop")
        app = ax.application(process.pid)
        window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None), "Exact fixture window missing")
        pending = [window]
        group = None
        while pending:
            element = pending.pop()
            if str(element.read("AXIdentifier")).startswith("axb.window."):
                group = element
                break
            pending.extend(element.read("AXChildren") or [])
        check(group is not None, "ordinary root contains all child contexts")

        def find(label, role=None):
            for element in group.read("AXChildren") or []:
                if element.read("AXDescription") == label and (role is None or element.read("AXRole") == role):
                    return element
            return None

        def settle():
            def completed():
                state()  # Fail immediately on a native fixture error.
                return group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action")
            ax.wait_for(completed, "Action did not finish", timeout=15)

        def send(action):
            settle()
            check(action() == 0, "external accessibility request accepted")
            settle()
            # The host clears a delivered receipt before this independent
            # timer necessarily sees it. Observe native completion, then read
            # application state from a later timer cycle without replaying.
            ticks = state()["timerCalls"]
            ax.wait_for(lambda: state()["timerCalls"] > ticks, "Application state observer did not advance")

        def button(label):
            send(find(label).press)

        def child(side):
            return state()["panel"]["inner"] if side == "Nested" else state()[side.lower()]

        close = find("Close fixture")
        for side in ["Left", "Right", "Nested"]:
            last = ax.wait_for(lambda: find(side + ": Last", "AXTextField"), "Offscreen field missing: " + side)
            check(last.read("AXValue") == side + " last", side + " offscreen field is readable before scrolling")
            check(find(side + ": Last", "AXStaticText") is not None and find(side + ": Remember last") is not None,
                  side + " offscreen labels and buttons remain discoverable")

        if args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / "scroll-voiceover", BUILD / "read-fixture-screen")
            report["voiceover"] = vo.steps
            report["voiceover_states"] = []
            try:
                vo.start()
                vo.key("home")
                children = group.read("AXChildrenInNavigationOrder")
                check(len(children or []) == len(group.read("AXChildren")), "standard reading order contains every form control")
                for _ in range(len(children) - 1):
                    vo.key("right")
                    report["voiceover_states"].append(state())
                captions = "\n".join(step["caption"] for step in vo.steps)
                for side in ["Left", "Right", "Nested"]:
                    check(side + " last" in captions, "VoiceOver reaches the complete " + side + " child")
                check(any(s["scroll"]["Panel"][0] > 0 and s["scroll"]["Panel"][1] > 0 and s["panel"]["scroll"][1] > 0 for s in report["voiceover_states"]),
                      "VoiceOver reveals content through both nested scroll containers")
                check("Close fixture" in vo.steps[-1]["caption"], "VoiceOver reaches the form end without repeating unrelated controls")
                for _ in range(len(children) - 1):
                    vo.key("left")
                check("First" in vo.steps[-1]["caption"], "VoiceOver returns to the beginning of the form")
            finally:
                vo.stop()
            report["passed"] = True
            return

        initial_ticks = state()["timerCalls"]
        for side in ["Left", "Right", "Nested"]:
            first = find(side + ": First", "AXTextField")
            last = find(side + ": Last", "AXTextField")
            label = find(side + ": Last", "AXStaticText")
            send(lambda: first.set_boolean("AXFocused", True))
            ax.wait_for(lambda: first.read("AXFocused") is True, side + " first focus missing")
            check("AXScrollToVisible" in label.actions(), side + " label enumerates standard reveal")
            old_focus = child(side)["focus"]
            send(lambda: label.perform("AXScrollToVisible"))
            check(child(side)["focus"] == old_focus, side + " label reveal preserves actual keyboard focus")
            check(first.read("AXFocused") is True, side + " offscreen keyboard focus remains represented")
            send(lambda: last.set_boolean("AXFocused", True))
            ax.wait_for(lambda: last.read("AXFocused") is True, side + " last focus missing")
            x, y = last.read("AXPosition")
            check(app.at_position(x + 10, y + 10).read("AXIdentifier") == last.read("AXIdentifier"), side + " revealed input owns its visible hit region")
            check(last.read("AXSize") == (240.0, 26.0), side + " real control size survives clipping")
            value = side + " edited 🎸"
            send(lambda: last.set_text(value))
            send(lambda: first.set_boolean("AXFocused", True))
            ax.wait_for(lambda: child(side)["last"] == value, side + " native edit did not commit")
            check(child(side)["edits"] == 1, side + " normal data-change handler runs once")
            send(find(side + ": Remember last").press)
            ax.wait_for(lambda: child(side)["clicks"] == 1, side + " offscreen button did not run")
            check(child(side)["remembered"] == value, side + " revealed button uses its existing handler and binding")
            send(find(side + ": Wide action").press)
            check(child(side)["wideClicks"] == 1, side + " button wider than its viewport uses the visible hit region")

        check(state()["timerCalls"] > initial_ticks, "original form timer continues throughout actions")
        old_left = find("Left: Last", "AXTextField")
        button("Hide left")
        ax.wait_for(lambda: find("Left: Last", "AXTextField") is None, "Hidden child still exposed")
        old_left.set_text("Hidden stale edit")
        time.sleep(.3)
        check(state()["left"]["last"] == "Left edited 🎸", "retained hidden child cannot mutate its data")
        button("Hide left")
        ax.wait_for(lambda: find("Left: Last", "AXTextField") is not None, "Revealed child missing")
        retained = find("Left: Last", "AXTextField")
        button("Replace left")
        ax.wait_for(lambda: find("Left: Last", "AXTextField").read("AXValue") == "Replacement last", "Replacement not published")
        retained.set_text("Replaced stale edit")
        time.sleep(.3)
        check(state()["left"]["last"] == "Replacement last", "replaced child rejects retained edit")
        retained = find("Left: Last", "AXTextField")
        button("Collapse left")
        ax.wait_for(lambda: find("Left: Last", "AXTextField") is None, "Zero-sized child still exposed")
        retained.set_text("Collapsed stale edit")
        time.sleep(.3)
        check(state()["left"]["last"] == "Replacement last", "zero-sized container excludes controls and rejects retained edits")
        button("Collapse left")
        ax.wait_for(lambda: find("Left: Last", "AXTextField") is not None, "Expanded child not exposed")
        retained = find("Right: Last", "AXTextField")
        button("Disable right")
        ax.wait_for(lambda: find("Right: Last", "AXTextField").read("AXEnabled") is False, "Disabled child not reflected")
        retained.set_text("Disabled stale edit")
        time.sleep(.3)
        check(state()["right"]["last"] == "Right edited 🎸", "disabled offscreen child remains readable but rejects input")
        disabled_label = find("Right: First", "AXStaticText")
        check("AXScrollToVisible" in disabled_label.actions(), "disabled child still offers reveal for reading")
        send(lambda: disabled_label.perform("AXScrollToVisible"))
        check(state()["scroll"]["Right"][1] < 20, "disabled child reveals its offscreen label without enabling input")
        button("Disable right")
        retained = find("Nested: Last", "AXTextField")
        identifier = retained.read("AXIdentifier")
        button("Change record")
        ax.wait_for(lambda: find("Nested: Last", "AXTextField").read("AXIdentifier") != identifier, "Ancestor scope did not retire nested child")
        retained.set_text("Stale record edit")
        time.sleep(.3)
        check(state()["panel"]["inner"]["last"] == "Nested edited 🎸", "ancestor record change rejects retained nested edit")
        close = find("Close fixture")  # The record change retired the old root controls too.
        button("Clip window")
        check(close.read("AXRole") == "AXButton", "root controls remain discoverable beyond a cropped window")
        send(lambda: close.perform("AXScrollToVisible"))
        check(group.read("AXHelp") == "Control is outside the form viewport", "root reveal cannot falsely complete outside a non-scrolling window")
        button("Restore window")
        send(lambda: close.perform("AXScrollToVisible"))
        check(group.read("AXHelp") == "Control revealed", "restoring the application layout makes the same root control revealable")
        report["passed"] = True
    finally:
        try:
            report["final_state"] = state()
        except AssertionError as failure:
            report["native_error"] = str(failure)
        if process.poll() is None:
            if not report["passed"]:
                try:
                    ax.capture_window(process.pid, BUILD / "scroll-failure.png")
                except RuntimeError:
                    pass
            if close:
                close.press()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=8)
        (BUILD / ("scroll-voiceover-report.json" if args.voiceover else "scroll-runtime-report.json")).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
