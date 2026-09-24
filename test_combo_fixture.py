#!/usr/bin/env python3
"""Exercise combo text, validation and native choices through external AX."""

import argparse
import json
import subprocess
import sys
import time

from build_component import sha
import doctor
from prepare_combo_fixture import BUILD, FIXTURE, ROOT, TITLE

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
    compiled = json.loads((BUILD / "combo-controls-compile-report.json").read_text())
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

    project = FIXTURE / "Project/ComboControls.4DProject"
    with (BUILD / "combo-controls-desktop.log").open("w") as log:
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
        check(ready["start"]["ok"], "automatic bridge starts with combo controls")
        app = ax.application(process.pid)
        window = ax.wait_for(
            lambda: next(
                (w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE),
                None,
            ),
            "Owned combo window missing",
        )
        root = ax.wait_for(
            lambda: next(
                (
                    e
                    for e in descendants(window)
                    if e.read("AXDescription") == "Product choices"
                ),
                None,
            ),
            "Combo root missing",
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
            return next(e for e in elements if e.read("AXDescription") == label)

        close = named("Close")
        controls = [named(label) for label in ["Instrument", "Wood", "Region", "Rating"]]
        check(all(e.read("AXRole") == "AXComboBox" for e in controls),
              "array, object, scalar and numeric controls expose editable combo roles")
        check([e.read("AXValue") for e in controls] == ["Guitar", "Maple", "East", "1.5"],
              "combos read array element zero, object currentValue and formatted scalar values")
        check("must-not-be-published" not in json.dumps(report["tree"]),
              "object-backed combo publishes only its UI value")
        check(all("AXShowMenu" in e.actions() and "AXConfirm" in e.actions() and e.is_settable("AXValue") for e in controls),
              "combos expose both text editing and their normal menu action")
        check(all(e.is_settable("AXSelectedText") and e.is_settable("AXSelectedTextRange") for e in controls),
              "clients can discover the combo's selection and replacement capabilities")
        instrument, wood, region, rating = controls

        def settle():
            ax.wait_for(lambda: root.read("AXHelp") not in
                        (None, "Action queued", "Waiting for the application to complete the action"),
                        "Combo action did not settle", timeout=15)

        def edit(control, value):
            check(control.set_text(value) == 0, "request real combo edit: " + value)
            ax.wait_for(lambda: control.read("AXValue") == value,
                        "Combo editor did not accept " + value, timeout=15)
            settle()
            focused = app.read("AXFocusedUIElement")
            check(isinstance(focused, ax.Element) and focused.read("AXIdentifier") == control.read("AXIdentifier"),
                  "application focus identifies the real combo editor")

        def save():
            before = state().get("saved", 0)
            check(named("Save choices").press() == 0, "normal Save action requested")
            ax.wait_for(lambda: state().get("saved") == before + 1, "Save handler did not run")
            settle()

        edit(instrument, "Guitar 🎸")
        check(instrument.set_range("AXSelectedTextRange", 7, 2) == 0,
              "combo exposes UTF-16 text selection")
        ax.wait_for(lambda: instrument.read("AXSelectedText") == "🎸", "Combo selection did not reach its editor")
        settle()
        check(instrument.set_string("AXSelectedText", "α") == 0, "combo selected text uses native replacement")
        ax.wait_for(lambda: instrument.read("AXValue") == "Guitar α", "Combo replacement failed")
        settle()
        save()
        check(state()["instrument"] == "Guitar α", "array combo commits through element zero")
        edit(wood, "Walnut")
        save()
        check(state()["wood"] == "Walnut" and "Walnut" in state()["woodChoices"],
              "object combo preserves automatic insertion and ordinary commit")
        edit(region, "North")
        save()
        check(state()["region"] == "North", "scalar combo accepts a value outside its suggested choices")
        edit(rating, "2.5")
        save()
        check(state()["rating"] == 2.5, "numeric combo preserves native parsing and display format")
        edit(wood, "Invalid")
        save()
        check(state()["wood"] == "Maple" and state()["rejected"],
              "existing On Data Change validation can reject a combo entry")
        check(any(e == {"object": "Instrument", "event": 17} for e in state()["events"]),
              "combo typing executes its existing On Before Keystroke handler")

        check(instrument.perform("AXShowMenu") == 0, "combo opens its real choice menu through AXShowMenu")
        ax.wait_for(lambda: instrument.read("AXExpanded") is True, "Combo did not expose its expanded state")
        linked = instrument.read("AXLinkedUIElements") or []
        check(len(linked) == 1 and linked[0].read("AXRole") == "AXTable", "expanded combo links to its actual native choice table")
        popup = next(e for e in instrument.read("AXChildren") if e.read("AXRole") == "AXScrollArea")
        check(popup.read("AXParent").same_as(instrument), "native popup belongs to the combo's accessibility subtree")
        occurrences = sum(e.same_as(linked[0]) for w in app.read("AXWindows") or [] for e in descendants(w))
        check(occurrences == 1, "native popup is exposed once through its owning combo")
        choices = linked[0].read("AXRows") or []
        report["choices"] = [next(e.read("AXValue") for e in descendants(row) if e.read("AXValue")) for row in choices]
        check(report["choices"] == ["Guitar", "Bass", "Keyboard"], "native menu exposes every array combo choice")
        last = next(e for e in descendants(choices[-1]) if e.read("AXValue") == "Keyboard")
        position, size = last.read("AXPosition"), last.read("AXSize")
        hit = app.at_position(position[0] + size[0] / 2, position[1] + size[1] / 2)
        check(hit.same_as(last), "screen-position lookup reaches the real dropdown choice outside the combo frame")
        check(choices[1].set_boolean("AXSelected", True) == 0, "existing native table accepts choice selection")
        ax.wait_for(lambda: choices[1].read("AXSelected") is True, "Native list selection did not change")
        settle()
        check(instrument.perform("AXConfirm") == 0, "combo confirms the native selection through its normal Return key")
        ax.wait_for(lambda: state().get("instrument") == "Bass", "Native menu choice did not reach array combo")
        settle()
        check(instrument.read("AXValue") == "Bass" and instrument.read("AXExpanded") is False,
              "confirmed choice updates the real value and collapses the popup")
        before = sum(e == {"object": "Instrument", "event": 20} for e in state()["events"])
        save()
        check(sum(e == {"object": "Instrument", "event": 20} for e in state()["events"]) == before + 1,
              "native keyboard choice preserves ordinary On Data Change on commit")
        check(instrument.perform("AXShowMenu") == 0, "reopen choices before cancellation")
        ax.wait_for(lambda: instrument.read("AXExpanded") is True, "Combo did not reopen")
        settle()
        rows = instrument.read("AXLinkedUIElements")[0].read("AXRows")
        check(rows[2].set_boolean("AXSelected", True) == 0, "highlight a different choice without confirming it")
        ax.wait_for(lambda: rows[2].read("AXSelected") is True, "Choice highlight did not change")
        check(instrument.perform("AXCancel") == 0, "cancel the real dropdown through its normal Escape key")
        ax.wait_for(lambda: instrument.read("AXExpanded") is False, "Combo did not close on cancellation")
        settle()
        check(instrument.read("AXValue") == "Bass" and state()["instrument"] == "Bass",
              "cancelling the dropdown preserves the committed value and open form")
        saved, ticks = state()["saved"], state()["ticks"]
        instrument.perform("AXCancel")
        instrument.perform("AXConfirm")
        ax.wait_for(lambda: state().get("ticks", 0) > ticks + 2, "Closed dropdown action closed the form")
        check(state()["saved"] == saved and instrument.read("AXValue") == "Bass",
              "closed dropdown actions leave the containing form and its value unchanged")
        check(not state()["discovery"]["unsupported"], "combo fixture has no unsupported-control diagnostic")
        if args.voiceover:
            from voiceover import VoiceOver
            check(instrument.set_boolean("AXFocused", True) == 0, "focus Instrument before VoiceOver")
            ax.wait_for(lambda: instrument.read("AXFocused") is True, "Combo focus missing")
            settle()
            vo = VoiceOver(process, project, TITLE, BUILD / "combo-controls-voiceover", BUILD / "read-fixture-screen")
            report["voiceover"] = vo.steps
            try:
                vo.start()
                caption = vo.key("f4")
                check("Instrument" in caption and "Bass" in caption and "combo" in caption.lower(),
                      "VoiceOver reads the combo's name, role and current value")
                vo.key("down", shift=True)
                vo.key("right")
                caption = vo.key("right")
                check("Show choices" in caption, "VoiceOver reaches the combo's visible arrow button")
                vo.key("space")
                ax.wait_for(lambda: instrument.read("AXExpanded") is True, "VoiceOver did not open choices")
                check(True, "VoiceOver opens the actual combo choices")
                caption = vo.key("down", voiceover=False)
                report["popupSpeech"] = caption
                check("Keyboard" in caption, "VoiceOver reads the final native choice during ordinary arrow navigation")
                vo.key("return", voiceover=False)
                ax.wait_for(lambda: instrument.read("AXValue") == "Keyboard" and instrument.read("AXExpanded") is False,
                            "VoiceOver choice did not commit")
                check(True, "VoiceOver confirms the actual dropdown choice through normal keyboard input")
            finally:
                vo.stop()
            if instrument.read("AXExpanded") is True:
                check(instrument.perform("AXCancel") == 0, "dismiss choices after VoiceOver navigation")
                ax.wait_for(lambda: instrument.read("AXExpanded") is False, "VoiceOver popup remained open")
                settle()
        ticks = state()["ticks"]
        ax.wait_for(lambda: state().get("ticks", 0) > ticks + 2, "Existing form timer stopped")
        check(close.press() == 0, "normal Close action requested")
        process.wait(timeout=10)
        check(process.returncode == 0, "owned combo fixture closes normally")
        report["passed"] = True
    finally:
        if process.poll() is None:
            try:
                report["last_state"] = state()
                report["lastReceipt"] = root.read("AXHelp")
                ax.capture_window(process.pid, BUILD / "combo-controls-failure.png")
            except Exception as error:
                report["captureError"] = str(error)
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        (
            BUILD
            / (
                "combo-controls-voiceover-report.json"
                if args.voiceover
                else "combo-controls-runtime-report.json"
            )
        ).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
