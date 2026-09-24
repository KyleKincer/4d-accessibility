#!/usr/bin/env python3
"""Validate real 4D steppers, rulers and progress through external AX/VoiceOver."""

import argparse
import json
import re
import subprocess
import time
import sys
from pathlib import Path

import doctor
from build_component import sha

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
FIXTURE = BUILD / "adjustable-controls-fixture"
TITLE = "AXB adjustable controls"
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error(
            "--run, Accessibility permission and an unlocked desktop are required"
        )
    if (
        subprocess.run(
            ["pgrep", "-x", "4D"], capture_output=True, check=False
        ).returncode
        == 0
    ):
        parser.error("Close 4D before launching the owned fixture")
    compiled = json.loads(
        (BUILD / "adjustable-controls-compile-report.json").read_text()
    )
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, relative
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
        assert sha(FIXTURE / relative) == compiled[key]
    status = FIXTURE / "Resources/status.json"
    status.unlink(missing_ok=True)
    checks = []
    report = {
        "passed": False,
        "checks": checks,
        **{k: compiled[k] for k in ["native_sha256", "component_sha256"]},
    }

    def check(condition, name):
        checks.append({"passed": bool(condition), "name": name})
        print(("PASS: " if condition else "FAIL: ") + name, flush=True)
        assert condition, name

    def state():
        try:
            value = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        assert not any(
            value.get(k) for k in ["error", "bridgeError", "bridgeFailure"]
        ), value
        return value

    def descendants(element):
        children = element.read("AXChildren") or []
        return children + [e for child in children for e in descendants(child)]

    project = FIXTURE / "Project/Adjustable.4DProject"
    with (BUILD / "adjustable-controls-desktop.log").open("w") as log:
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
        ready, report["notice"] = wait_for_start(process, project, state, BUILD)
        check(
            ready["start"]["ok"],
            "automatic bridge starts with typed adjustable controls",
        )
        app = ax.application(process.pid)
        window = ax.wait_for(
            lambda: next(
                (w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE),
                None,
            ),
            "Owned adjustable window missing",
        )
        root = ax.wait_for(
            lambda: next(
                (
                    e
                    for e in descendants(window)
                    if e.read("AXDescription") == "Adjustable controls"
                ),
                None,
            ),
            "Adjustable bridge root missing",
        )
        ax.wait_for(lambda: app.read("AXFrontmost") is True and any(e.read("AXDescription") == "Text" and e.read("AXFocused") is True for e in descendants(root)), "Initial form focus did not settle")
        elements = descendants(root)
        named = lambda name: next(
            e for e in elements if e.read("AXDescription") == name
        )
        close = named("Close")
        sequence = 0

        def command(**values):
            nonlocal sequence
            sequence += 1
            values["sequence"] = sequence
            path = FIXTURE / "Resources/command.json"
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(values))
            temporary.replace(path)
            return ax.wait_for(lambda: state() if state().get("sequence") == sequence else None, "Fixture command was not handled")
        check(
            named("DateStepper").read("AXValue") == ready["dateText"]
            and named("DateStepper").read("AXMinValue") is None,
            "date stepper has its formatted value without a fictitious numeric range",
        )
        check(
            named("TimeStepper").read("AXValue") == 32400
            and named("TimeStepper").read("AXValueDescription") == ready["timeText"],
            "time stepper exposes seconds and readable time",
        )
        check(
            named("Ruler").read("AXMinValue") == 0
            and named("Ruler").read("AXMaxValue") == 100,
            "slider exposes its actual numeric bounds",
        )
        discovery = ax.wait_for(
            lambda: state().get("discovery"), "Discovery report missing"
        )
        check(
            any(
                n["objectName"] == "ReadOnly"
                and n.get("missingLabel")
                and "labelledBy" not in n
                for n in discovery["nodes"]
            ),
            "punctuation separators are never inferred as a control label",
        )
        check(discovery["unsupported"] == [{"object": "UnconfiguredProgress", "type": 27, "reason": "adjustmentCallbackRequired"}], "unconfigured interactive progress is readable and explicitly reports the missing controller")
        check(state()["invalidAdjustment"] == {"ok": False, "error": "invalidControlAdjustment"}, "invalid adjustment callback is rejected before startup")
        check(named("UnconfiguredProgress").read("AXValue") == 5 and not named("UnconfiguredProgress").actions(), "unconfigured progress exposes its value without promising an unreliable action")
        check(named("Progress").read("AXOrientation") == "AXHorizontalOrientation" and named("Vertical").read("AXOrientation") == "AXVerticalOrientation", "progress publishes actual horizontal and vertical orientation")
        check(named("DateRuler").read("AXValue") == ready["rulerDateText"] and named("DateProgress").read("AXValueDescription") == ready["progressDateText"], "date sliders describe the actual date")
        check(named("ReadOnlyDateProgress").read("AXRole") == "AXProgressIndicator" and named("ReadOnlyDateProgress").read("AXValueDescription") == ready["progressDateText"] and named("ReadOnlyDateProgress").read("AXMaxValue") == 29, "read-only date progress exposes its date and actual range")
        check(named("ReadOnlyTimeProgress").read("AXValue") == 32400 and named("ReadOnlyTimeProgress").read("AXValueDescription") == ready["timeText"] and named("ReadOnlyTimeProgress").read("AXOrientation") == "AXVerticalOrientation", "read-only time progress exposes seconds, readable time and vertical orientation")
        for name, expected in [
            ("Stepper", 6),
            ("DateStepper", "2026-09-26"),
            ("TimeStepper", 33000),
            ("Ruler", 30),
            ("LongStepper", 6),
            ("Progress", 6),
            ("Vertical", 6),
            ("TimeProgress", 36000),
            ("FractionalProgress", 0.6),
            ("DateRuler", "2026-09-25"),
            ("DateProgress", "2026-09-25"),
        ]:
            element = named(name)
            check(
                element.read("AXRole")
                == ("AXIncrementor" if "Stepper" in name or name == "DateRuler" else "AXSlider"),
                name + " has its native accessibility role",
            )
            check(
                set(element.actions()) == {"AXIncrement", "AXDecrement"}
                and not element.is_settable("AXValue"),
                name + " advertises its real adjustment actions",
            )
            before = state()["objects"][name]["value"]
            count = len(state()["events"])
            check(element.perform("AXIncrement") == 0, name + " accepts one increment")
            ax.wait_for(
                lambda name=name, expected=expected: (
                    state().get("objects", {}).get(name, {}).get("value") == expected
                ),
                name + " increment did not reach the real control",
            )
            ax.wait_for(
                lambda: "Control value confirmed" in (root.read("AXHelp") or ""),
                name + " increment has no confirmed receipt",
            )
            check(
                len(state()["events"]) == count + 1,
                name + " runs its existing handler exactly once",
            )
            check(
                state()["events"][-1]["event"] == ("20" if "Ruler" in name else "4" if "Stepper" in name else "accessibility"),
                name + " uses native events or its explicitly configured controller",
            )
            check(element.perform("AXDecrement") == 0, name + " accepts one decrement")
            ax.wait_for(
                lambda name=name, before=before: (
                    state().get("objects", {}).get(name, {}).get("value") == before
                ),
                name + " decrement did not reach the real control",
            )
            ax.wait_for(
                lambda: "Control value confirmed" in (root.read("AXHelp") or ""),
                name + " decrement has no confirmed receipt",
            )
            check(
                len(state()["events"]) == count + 2,
                name + " decrement uses the existing handler exactly once",
            )
        before = state()
        # Exercise the actual mouse path independently of the AX callback.
        # 4D POST CLICK is not a reliable progress-control input path.
        import ctypes as c
        class Point(c.Structure):
            _fields_ = [("x", c.c_double), ("y", c.c_double)]
        graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        create = ax.signature(graphics, "CGEventCreateMouseEvent", c.c_void_p, c.c_void_p, c.c_uint32, Point, c.c_uint32)
        post = ax.signature(graphics, "CGEventPost", None, c.c_uint32, c.c_void_p)
        element = named("Progress")
        position, size = element.read("AXPosition"), element.read("AXSize")
        point = Point(position[0] + size[0] * 0.8, position[1] + size[1] / 2)
        assert app.read("AXFrontmost") is True and process.poll() is None
        assert ax.system().at_position(point.x, point.y).same_as(element)
        down, up = create(None, 1, point, 0), create(None, 2, point, 0)
        try:
            post(1, down)
            time.sleep(0.1)
        finally:
            post(1, up)
            ax.release(down)
            ax.release(up)
        ax.wait_for(lambda: state()["objects"]["Progress"]["value"] == 8, "Ordinary progress click did not reach the shared controller")
        check(len(state()["events"]) == len(before["events"]) + 1 and state()["events"][-1]["event"] == "4", "ordinary mouse handling calls the same controller once with its original click event")
        command(action="value", object="Progress", value=5)
        for name in ["UnconfiguredProgress", "ReadOnly", "Disabled", "ReadOnlyProgress", "ReadOnlyDateProgress", "ReadOnlyTimeProgress", "DisabledProgress"]:
            element = named(name)
            before = state()
            check(
                not set(element.actions()).intersection(["AXIncrement", "AXDecrement"]),
                name + " does not advertise adjustment",
            )
            # AppKit can acknowledge an unadvertised AX message even when the
            # provider returns NO. Confirm unchanged application state instead.
            element.perform("AXIncrement")
            ax.wait_for(
                lambda before=before: state().get("ticks", 0) > before["ticks"] + 2,
                "Existing form timer stopped",
            )
            after = state()
            check(
                after["objects"][name]["value"] == before["objects"][name]["value"]
                and len(after["events"]) == len(before["events"]),
                name + " cannot change or execute its handler",
            )
        for name, value in [("Rejected", 4), ("RejectedProgress", 5)]:
            before = state()
            check(named(name).perform("AXIncrement") == 0, name + " reaches an existing rejecting handler")
            ax.wait_for(lambda: len(state()["events"]) == len(before["events"]) + 1, name + " handler missing")
            ax.wait_for(lambda: "Application did not accept the adjustment" in (root.read("AXHelp") or ""), "Rejected adjustment lacks a rejected receipt")
            after = state()
            check(after["objects"][name]["value"] == value and len(after["events"]) == len(before["events"]) + 1, name + " validation keeps its original value without replaying the handler")
        command(action="rejectTyped", value=True)
        for name in ["LongStepper", "TimeProgress", "DateProgress"]:
            before = state()
            named(name).perform("AXIncrement")
            ax.wait_for(lambda: len(state()["events"]) == len(before["events"]) + 1, name + " rejecting controller was not called")
            ax.wait_for(lambda: "Application did not accept the adjustment" in (root.read("AXHelp") or ""), name + " falsely confirmed an unchanged typed value")
            check(state()["objects"][name]["value"] == before["objects"][name]["value"], name + " rejects unchanged typed values without false success")
        command(action="rejectTyped", value=False)
        for name in ["Progress", "Vertical"]:
            for start, operation, end in [(9, "AXIncrement", 10), (1, "AXDecrement", 0)]:
                command(action="value", object=name, value=start)
                ax.wait_for(lambda: named(name).read("AXValue") == start, "Limit setup did not refresh")
                named(name).perform(operation)
                ax.wait_for(lambda: state()["objects"][name]["value"] == end, name + " did not reach its endpoint")
                ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Endpoint change was not confirmed")
                check(named(name).read("AXValue") == end, name + " reaches endpoint " + str(end))
                named(name).perform(operation)
                ax.wait_for(lambda: "Control is at its limit" in (root.read("AXHelp") or ""), "Endpoint repeat did not confirm its limit")
                check(state()["objects"][name]["value"] == end, name + " stays at endpoint " + str(end))
            command(action="value", object=name, value=5)
        for _ in range(3):
            command(action="value", object="Progress", value=5)
            ax.wait_for(lambda: named("Progress").read("AXValue") == 5, "Numeric reset did not publish")
            named("Progress").perform("AXIncrement")
            ax.wait_for(lambda: state()["objects"]["Progress"]["value"] == 6, "Numeric adjustment after reset failed")
            ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Numeric reset adjustment lacked a receipt")
            check(True, "numeric progress repeatedly advances after a programmatic reset")
        command(action="value", object="Progress", value=5)
        dense = named("DenseProgress")
        before = state()
        dense.perform("AXIncrement")
        ax.wait_for(lambda: state()["objects"]["DenseProgress"]["value"] == 5001, "Subpixel step did not move forward")
        ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Subpixel step was not confirmed")
        check(len(state()["events"]) == len(before["events"]) + 1, "fine progress step changes exactly one unit through one controller call")
        command(action="shiftDateRange", value=True)
        before = state()
        offset = named("DateProgress").read("AXValue")
        named("DateProgress").perform("AXIncrement")
        ax.wait_for(lambda: state()["objects"]["DateProgress"]["value"] == "2026-09-25", "Date range handler did not change the date")
        ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Date change was not confirmed after its handler shifted the range")
        check(named("DateProgress").read("AXValue") == offset and len(state()["events"]) == len(before["events"]) + 1, "date adjustment confirms the actual date when the handler also shifts its range")
        command(action="shiftDateRange", value=False)
        ax.wait_for(lambda: named("DateProgress").read("AXValue") == 23, "Restored date range did not publish")
        named("DateProgress").perform("AXIncrement")
        ax.wait_for(lambda: state()["objects"]["DateProgress"]["value"] == "2026-09-25", "Date increment after range reset failed")
        ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Reset increment lacked a receipt")
        check(True, "date progress still advances after its native range is restored")
        command(action="shiftDateRange", value=False)
        for name in ["DateProgress"]:
            for start, operation, end, date in [(28, "AXIncrement", 29, "2026-09-30"), (1, "AXDecrement", 0, "2026-09-01")]:
                command(action="dateValue", object=name, value=start)
                ax.wait_for(lambda: named(name).read("AXValue") == start, "Date endpoint setup did not publish")
                named(name).perform(operation)
                ax.wait_for(lambda: state()["objects"][name]["value"] == date, name + " did not reach its date endpoint")
                ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Date endpoint lacked a receipt")
                check(named(name).read("AXValue") == end, name + " reaches date endpoint " + date)
            command(action="dateValue", object=name, value=23)
        command(action="dateValue", object="DateRuler", value=29)
        ax.wait_for(lambda: named("DateRuler").read("AXValue") == "9/30/26", "Date ruler boundary did not publish")
        named("DateRuler").perform("AXIncrement")
        ax.wait_for(lambda: state()["objects"]["DateRuler"]["value"] == "2026-10-01", "Date ruler must preserve 4D's unbounded keyboard behavior")
        ax.wait_for(lambda: "Control value confirmed" in (root.read("AXHelp") or ""), "Unbounded date adjustment lacked a receipt")
        check(named("DateRuler").read("AXMaxValue") is None, "date ruler does not advertise bounds that its native keyboard path ignores")
        command(action="dateValue", object="DateRuler", value=23)
        field = named("Text")
        check(
            field.set_boolean("AXFocused", True) == 0,
            "ordinary text focus still works alongside adjustable controls",
        )
        ax.wait_for(
            lambda: field.read("AXFocused") is True,
            "Ordinary field did not receive focus",
        )
        check(
            field.set_text("Edited alongside steppers") == 0,
            "ordinary text editing still uses its normal editor",
        )
        ax.wait_for(
            lambda: field.read("AXValue") == "Edited alongside steppers",
            "Ordinary editor did not change",
        )
        if args.voiceover:
            from voiceover import VoiceOver

            vo = VoiceOver(
                process,
                project,
                TITLE,
                BUILD / "adjustable-controls-voiceover",
                BUILD / "read-fixture-screen",
            )
            report["voiceover"] = vo.steps

            def heard(number):
                caption = vo.read_caption()
                return (
                    caption if re.search(r"\b" + str(number) + r"\b", caption) else None
                )

            try:
                vo.start()
                for _ in range(3):
                    caption = vo.key("right")
                    if "Stepper" in caption:
                        break
                check(
                    "Stepper" in caption
                    and "4 items" in caption
                    and "%" not in caption,
                    "VoiceOver reads a quantity with its actual units",
                )
                vo.key("down", shift=True)
                vo.key("up")
                ax.wait_for(
                    lambda: (
                        state().get("objects", {}).get("Stepper", {}).get("value") == 6
                    ),
                    "VoiceOver increment did not reach the stepper",
                )
                check(
                    bool(
                        ax.wait_for(
                            lambda: heard(6),
                            "VoiceOver did not speak the changed quantity",
                        )
                    ),
                    "VoiceOver speaks the confirmed increment",
                )
                vo.key("down")
                ax.wait_for(
                    lambda: (
                        state().get("objects", {}).get("Stepper", {}).get("value") == 4
                    ),
                    "VoiceOver decrement did not reach the stepper",
                )
                check(
                    bool(
                        ax.wait_for(
                            lambda: heard(4),
                            "VoiceOver did not speak the decremented quantity",
                        )
                    ),
                    "VoiceOver speaks the confirmed decrement",
                )
                vo.key("up", shift=True)
                caption = vo.key("right")
                check(
                    "DateStepper" in caption, "VoiceOver navigates to the date stepper"
                )
                vo.key("down", shift=True)
                vo.key("up")
                ax.wait_for(
                    lambda: (
                        state().get("objects", {}).get("DateStepper", {}).get("value")
                        == "2026-09-26"
                    ),
                    "VoiceOver date adjustment did not use the normal control",
                )
                caption = vo.read_caption()
                check("26" in caption, "VoiceOver reads the adjusted date")
                vo.key("down")
                ax.wait_for(
                    lambda: (
                        state().get("objects", {}).get("DateStepper", {}).get("value")
                        == "2026-09-24"
                    ),
                    "VoiceOver date decrement did not use the normal control",
                )
                vo.key("up", shift=True)
                caption = vo.key("right")
                check(
                    "TimeStepper" in caption, "VoiceOver navigates to the time stepper"
                )
                vo.key("down", shift=True)
                vo.key("up")
                ax.wait_for(
                    lambda: (
                        state().get("objects", {}).get("TimeStepper", {}).get("value")
                        == 33000
                    ),
                    "VoiceOver time adjustment did not use the normal control",
                )
                caption = vo.read_caption()
                check(
                    "09:10" in caption,
                    "VoiceOver reads time rather than an unrelated percentage",
                )
                vo.key("up", shift=True)
                for _ in range(8):
                    caption = vo.key("right")
                    if "Ruler" in caption:
                        break
                check("Ruler" in caption, "VoiceOver reaches the ruler slider")
                vo.key("down", shift=True)
                vo.key("up")
                ax.wait_for(
                    lambda: (
                        state().get("objects", {}).get("Ruler", {}).get("value") == 30
                    ),
                    "VoiceOver slider increment did not use normal keyboard handling",
                )
                check(
                    bool(
                        ax.wait_for(
                            lambda: heard(30),
                            "VoiceOver did not speak the slider value",
                        )
                    ),
                    "VoiceOver speaks the adjusted slider value",
                )
                vo.key("up", shift=True)
                for _ in range(5):
                    caption = vo.key("right")
                    if "Progress" in caption:
                        break
                check("Progress" in caption, "VoiceOver reaches interactive progress")
                vo.key("down", shift=True)
                vo.key("up")
                ax.wait_for(lambda: state()["objects"]["Progress"]["value"] == 6, "VoiceOver progress increment did not reach the controller")
                check(bool(ax.wait_for(lambda: heard(6), "VoiceOver did not speak changed progress")), "VoiceOver speaks the confirmed progress value")
                vo.key("up", shift=True)
                for name in ["DateRuler", "DateProgress"]:
                    for _ in range(16):
                        caption = vo.key("right")
                        if name in caption:
                            break
                    check(name in caption and "9/24/26" in caption, "VoiceOver reaches " + name + " and reads its actual date")
                    vo.key("down", shift=True)
                    vo.key("up")
                    ax.wait_for(lambda: state()["objects"][name]["value"] == "2026-09-25", name + " did not adjust through VoiceOver")
                    check(bool(ax.wait_for(lambda: "9/25/26" in vo.read_caption(), "VoiceOver did not speak the adjusted date")), "VoiceOver speaks the confirmed date for " + name)
                    vo.key("up", shift=True)
            finally:
                vo.stop()
        check(
            close.press() == 0,
            "ordinary close action still works alongside adjustable controls",
        )
        process.wait(timeout=10)
        check(process.returncode == 0, "owned adjustable fixture closes normally")
        report["passed"] = True
    finally:
        try:
            report["last_state"] = state()
        except AssertionError as error:
            report["last_state_error"] = str(error)
        if process.poll() is None:
            try:
                ax.capture_window(
                    process.pid, BUILD / "adjustable-controls-failure.png"
                )
                if close:
                    close.press()
                    process.wait(timeout=5)
            except (
                AssertionError,
                RuntimeError,
                OSError,
                subprocess.TimeoutExpired,
            ) as error:
                report["cleanup_error"] = str(error)
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        (
            BUILD
            / (
                "adjustable-controls-voiceover-report.json"
                if args.voiceover
                else "adjustable-controls-runtime-report.json"
            )
        ).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
