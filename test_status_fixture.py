#!/usr/bin/env python3
"""Exercise semantic groups, live progress and image descriptions through AX."""

import argparse
import json
import subprocess
import sys
import time

from build_component import sha
import doctor
from prepare_status_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, AX permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before launching the owned fixture")
    compiled = json.loads((BUILD / "status-controls-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected
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

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def state():
        if process.poll() is not None:
            raise AssertionError("Owned fixture exited")
        try:
            result = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        assert not any(result.get(k) for k in ["error", "bridgeError", "failure"]), (
            result
        )
        return result

    def descendants(element):
        result = []
        for child in element.read("AXChildren") or []:
            result.append(child)
            result.extend(descendants(child))
        return result

    project = FIXTURE / "Project/StatusControls.4DProject"
    with (BUILD / "status-controls-desktop.log").open("w") as log:
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
        check(ready["start"]["ok"], "automatic bridge starts with semantic controls")
        app = ax.application(process.pid)
        window = ax.wait_for(
            lambda: next(
                (w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE),
                None,
            ),
            "Owned status window missing",
        )
        root = ax.wait_for(
            lambda: next(
                (
                    e
                    for e in descendants(window)
                    if e.read("AXDescription") == "Shipment details"
                ),
                None,
            ),
            "Semantic root missing",
        )
        elements = descendants(root)
        report["tree"] = [
            {
                "role": e.read("AXRole"),
                "label": e.read("AXDescription"),
                "value": e.read("AXValue"),
            }
            for e in elements
        ]

        def named(label):
            return next(e for e in elements if e.read("AXDescription") == label or (e.read("AXRole") == "AXImage" and (e.read("AXDescription") or "").startswith(label + ": ")))

        order, shipping, name = (
            named("Order"),
            named("Shipping"),
            named("Customer name"),
        )
        ship, progress, busy, image = [
            named(label)
            for label in [
                "Ship order",
                "Packing progress",
                "Sending invoice",
                "Shipment",
            ]
        ]
        close = named("Close")
        check(
            order.read("AXRole") == "AXGroup" and shipping.read("AXRole") == "AXGroup",
            "real group-box captions become named AX groups",
        )
        check(
            shipping.read("AXParent").read("AXIdentifier")
            == order.read("AXIdentifier"),
            "nested group boxes form the actual semantic hierarchy",
        )
        check(
            name.read("AXParent").read("AXIdentifier") == shipping.read("AXIdentifier")
            and ship.read("AXParent").read("AXIdentifier")
            == shipping.read("AXIdentifier"),
            "ordinary field and button belong to their innermost group",
        )
        check(
            len(elements) == 11 and len(root.read("AXChildren")) == 2,
            "grouping preserves every supported visible control and omits hidden/decorative images",
        )
        check(
            progress.read("AXRole") == "AXProgressIndicator"
            and progress.read("AXValue") == 35,
            "progress exposes its real numeric value",
        )
        check(
            progress.read("AXMinValue") == 0 and progress.read("AXMaxValue") == 100,
            "progress exposes its actual range",
        )
        check(
            progress.read("AXValueDescription") == "35 items packed",
            "progress can describe its units using one model formula",
        )
        check(
            not progress.is_settable("AXValue") and "AXPress" not in progress.actions(),
            "read-only progress cannot accept editing actions",
        )
        check(
            busy.read("AXRole") == "AXProgressIndicator"
            and busy.read("AXValue") is None
            and busy.read("AXValueDescription") == "In progress",
            "spinner announces activity without a fictitious percentage",
        )
        check(
            image.read("AXRole") == "AXImage"
            and image.read("AXValue") == "Waiting to ship",
            "image status uses the existing model description",
        )
        check(not image.is_settable("AXValue"), "status image is read-only")
        discovery = ax.wait_for(
            lambda: state().get("discovery"), "No live discovery report"
        )
        check(
            any(
                n.get("objectName") == "Undescribed" and n.get("missingLabel")
                for n in discovery["nodes"]
            ),
            "missing image text remains an explicit integration diagnostic",
        )
        check(
            not discovery["unsupported"],
            "supported status families leave no unimplemented-control diagnostic",
        )
        pos, size = ship.read("AXPosition"), ship.read("AXSize")
        hit = app.at_position(pos[0] + size[0] / 2, pos[1] + size[1] / 2)
        check(
            hit.read("AXIdentifier") == ship.read("AXIdentifier"),
            "screen-position lookup reaches a button inside nested groups",
        )
        check(
            name.set_text("Grace") == 0,
            "grouped field accepts the ordinary editor action",
        )
        ax.wait_for(
            lambda: name.read("AXValue") == "Grace",
            "Grouped editor did not receive text",
            timeout=15,
        )
        ax.wait_for(
            lambda: (
                root.read("AXHelp")
                not in (
                    None,
                    "Action queued",
                    "Waiting for the application to complete the action",
                )
            ),
            "Editor action did not settle",
            timeout=15,
        )
        check(
            ship.press() == 0,
            "group geometry does not block the existing button action",
        )
        ax.wait_for(
            lambda: state().get("pressed") == 1,
            "Existing grouped button handler did not run",
            timeout=15,
        )
        ax.wait_for(
            lambda: (
                progress.read("AXValue") == 100 and image.read("AXValue") == "Shipped"
            ),
            "Live status did not update",
        )
        check(
            state()["name"] == "Grace",
            "grouped button commits the real editor through normal focus loss",
        )
        check(
            progress.read("AXValueDescription") == "100 items packed"
            and busy.read("AXValueDescription") == "Idle",
            "progress and activity descriptions follow the existing handler",
        )
        for label, key in [("Apply to selection", "mixed"), ("Include alternatives", "flatMixed")]:
            checkbox = named(label)
            position, size = checkbox.read("AXPosition"), checkbox.read("AXSize")
            actual = ax.system().at_position(position[0] + 8, position[1] + size[1] / 2)
            check(actual.same_as(checkbox), "system-wide hit testing reaches the unobscured checkbox: " + label)
            check(checkbox.read("AXRole") == "AXCheckBox" and checkbox.read("AXValue") == 2,
                  "mixed checkbox exposes the native third state: " + label)
            for expected in (0, 1, 2):
                calls = state()["checkboxCalls"]
                check(checkbox.press() == 0, "checkbox accepts its normal activation: " + label)
                ax.wait_for(lambda: state().get(key) == expected and state().get("checkboxCalls") == calls + 1
                            and checkbox.read("AXValue") == expected and root.read("AXHelp") == "Control state confirmed",
                            "Checkbox state or existing handler did not complete", timeout=15)
                check(state()["checkboxCalls"] == calls + 1,
                      f"checkbox reaches state {expected} through exactly one existing handler: {label}")
        if args.voiceover:
            from voiceover import VoiceOver

            vo = VoiceOver(
                process,
                project,
                TITLE,
                BUILD / "status-controls-voiceover",
                BUILD / "read-fixture-screen",
            )
            report["voiceover"] = vo.steps
            try:
                vo.start()
                # VoiceOver follows the focused editor into both nested groups.
                vo.key("up", shift=True)
                vo.key("up", shift=True)
                caption = vo.key("home")
                for _ in range(14):
                    if "Order" in caption and "group" in caption.lower():
                        break
                    caption = vo.key("right")
                check(
                    "Order" in caption and "group" in caption.lower(),
                    "VoiceOver finds the named outer group",
                )
                caption = vo.key("down", shift=True)
                for _ in range(6):
                    if "Shipping" in caption and "group" in caption.lower():
                        break
                    caption = vo.key("right")
                check(
                    "Shipping" in caption and "group" in caption.lower(),
                    "VoiceOver can enter the nested shipping group",
                )
                caption = vo.key("down", shift=True)
                if "Customer name" not in caption:
                    caption = vo.key("right")
                check(
                    "Customer name" in caption and "Grace" in caption,
                    "VoiceOver reads the grouped editor's committed value",
                )
                caption = vo.key("right")
                check("Apply to selection" in caption and "mixed" in caption.lower(),
                      "VoiceOver announces a mixed checkbox distinctly from checked")
                vo.key("space")
                ax.wait_for(lambda: state().get("mixed") == 0, "VoiceOver did not activate the mixed checkbox")
                check(named("Apply to selection").read("AXValue") == 0,
                      "VoiceOver activation follows the normal three-state cycle")
                caption = vo.key("right")
                check("Ship order" in caption, "VoiceOver reaches the existing grouped button")
                caption = vo.key("right")
                check("Include alternatives" in caption and "mixed" in caption.lower(),
                      "VoiceOver reaches the mixed checkbox that does not accept keyboard focus")
                vo.key("space")
                ax.wait_for(lambda: state().get("flatMixed") == 0, "VoiceOver did not activate the flat checkbox")
                check(named("Include alternatives").read("AXValue") == 0,
                      "VoiceOver can activate a checkbox without moving keyboard focus")
                def announced():
                    spoken = vo.read_caption()
                    return spoken if "unchecked" in spoken.lower() and "Include alternatives" in spoken else None
                caption = ax.wait_for(announced, "VoiceOver did not announce the updated flat checkbox", timeout=10)
                vo.steps.append({"event": "value notification", "caption": caption})
                check(True, "VoiceOver announces the unfocused checkbox's asynchronous value change")
                vo.key("up", shift=True)
                captions = []
                for _ in range(5):
                    captions.append(vo.key("right"))
                spoken = " ".join(captions)
                check(
                    "100 items packed" in spoken,
                    "VoiceOver reads progress with application units",
                )
                check("Idle" in spoken, "VoiceOver reads the stopped activity state")
                check(
                    "Shipped" in spoken,
                    "VoiceOver reads the image's updated status description",
                )
            finally:
                vo.stop()
        ticks = state()["ticks"]
        ax.wait_for(
            lambda: state().get("ticks", 0) > ticks + 2, "Existing form timer stopped"
        )
        check(close.press() == 0, "ordinary close remains outside the semantic groups")
        process.wait(timeout=10)
        check(process.returncode == 0, "owned semantic fixture closes normally")
        report["passed"] = True
    finally:
        if process.poll() is None:
            try:
                report["last_state"] = state()
                report["last_help"] = root.read("AXHelp")
                ax.capture_window(process.pid, BUILD / "status-controls-failure.png")
            except Exception as error:
                report["captureError"] = str(error)
            if close:
                try:
                    close.press()
                    process.wait(timeout=5)
                except Exception:
                    pass
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        (
            BUILD
            / (
                "status-controls-voiceover-report.json"
                if args.voiceover
                else "status-controls-runtime-report.json"
            )
        ).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
