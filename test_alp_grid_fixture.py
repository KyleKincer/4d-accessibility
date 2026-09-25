#!/usr/bin/env python3
"""Exercise complete logical AreaList grids through the external macOS AX API."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from build_component import sha
from prepare_alp_grid_fixture import BUILD, FIXTURE, ROOT, TITLE
import doctor

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, press_key, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--voiceover", action="store_true", help="Read the entire vendor grid and return to an ordinary field using VoiceOver")
    parser.add_argument("--text", choices=["ascii", "bmp", "supplementary"], default="supplementary", help="Editor character coverage; supplementary remains a required failing gate")
    args = parser.parse_args()
    initial_edit = {"ascii": "Edited far row", "bmp": "Edited café row", "supplementary": "Edited far row 😀"}[args.text]
    replacement = {"ascii": "Piano", "bmp": "Café", "supplementary": "Guitar 🎸"}[args.text]
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, Accessibility permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before launching this owned fixture")
    compiled = json.loads((BUILD / "alp-grid-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, "Prepared source changed after compilation"
    for key, relative in [("native_sha256", "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
                          ("component_sha256", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")]:
        assert sha(FIXTURE / relative) == compiled[key], "Prepared package changed after compilation"
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    final_key = "line-0600" if config.get("keyType", "text") == "text" else 600
    status = FIXTURE / "Resources/runtime-status.json"
    closed = FIXTURE / "Resources/closed.json"
    status.unlink(missing_ok=True)
    closed.unlink(missing_ok=True)
    checks = []
    report = {"passed": False, "textMode": args.text, "compiled": args.compiled, "checks": checks, **config, "native_sha256": compiled["native_sha256"], "component_sha256": compiled["component_sha256"]}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def state():
        if process.poll() is not None:
            raise AssertionError(f"Owned fixture exited unexpectedly: {process.returncode}")
        # The form timer overwrites its diagnostic file. A read during that
        # write is incomplete evidence, not an empty application state.
        deadline = time.monotonic() + 1
        while True:
            try:
                value = json.loads(status.read_text(encoding="utf-8-sig"))
                break
            except FileNotFoundError:
                return {}
            except (OSError, ValueError):
                if time.monotonic() >= deadline:
                    raise AssertionError("Fixture status remained unreadable for one second")
                time.sleep(0.01)
        if value.get("phase") == "failed" or value.get("bridgeError") or value.get("failure"):
            raise AssertionError(f"Fixture failed: {value}")
        return value

    project = FIXTURE / "Project/ALPGridFixture.4DProject"
    with (BUILD / "alp-grid-desktop.log").open("w") as log:
        process = subprocess.Popen(["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
            "--dataless", "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
    close = None
    try:
        ready, report["application_mode_notice_acknowledged"] = wait_for_start(process, project,
            lambda: state() if state().get("runId") == config["runId"] else None, BUILD, area_list_demo=config["licenseMode"] == "demo", area_list_title=config["areaListTitle"])
        check(ready["startResult"].get("ok") is True and ready["compiled"] is args.compiled, "one automatic root starts around the existing repeated AreaList forms")
        report["registration"] = ready.get("registration")
        if config["licenseMode"] == "registered":
            check(ready.get("registration") == 0, "AreaList confirms the existing partner license with AL_Register result zero")
        report["architecture"] = ax.process_architecture(process.pid)
        check(report["architecture"].replace("-", "").startswith("ARM64"), "actual native ARM desktop execution")
        app, window = activate_fixture(process, project, TITLE)
        pending = [window]
        group = None
        while pending:
            item = pending.pop()
            if (item.read("AXIdentifier") or "").startswith("axb.window."):
                group = item
                break
            if item.read("AXRole") != "AXTable":
                pending.extend(item.read("AXChildren") or [])
        assert group is not None

        def find(label):
            return next((e for e in group.read("AXChildren") or [] if any(text == label or text.endswith(": " + label)
                        for text in [e.read("AXDescription") or "", e.read("AXTitle") or ""])), None)

        def first_cell_identifier():
            current = find("Left lines")
            if current is None:
                return None
            try:
                return current.cell(1, 0).read("AXIdentifier")
            except RuntimeError as error:
                # Scope replacement retires the table between indexed reads.
                # Reacquire only this read; never repeat the activation.
                if str(error).endswith(", -25202"):
                    return None
                raise

        def settle():
            def done():
                state()
                return group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action")
            ax.wait_for(done, "AreaList action did not settle", timeout=15)

        def press(label):
            settle()
            assert find(label).press() == 0
            settle()

        close = find("Close")
        report["initial_controls"] = [{"role": e.read("AXRole"), "label": e.read("AXDescription"), "title": e.read("AXTitle")}
                                     for e in group.read("AXChildren") or []]
        left = ax.wait_for(lambda: find("Left lines"), "Left logical AreaList missing", timeout=15)
        right = ax.wait_for(lambda: find("Right lines"), "Right logical AreaList missing", timeout=15)
        check(left.count("AXRows") == right.count("AXRows") == 599, "both AreaLists expose all non-hidden logical rows")
        check(left.count("AXColumns") == right.count("AXColumns") == 5, "readable columns include pictures and styled text while excluding hidden keys and decorative spacers")
        check(state()["leftError"] == state()["rightError"] == 0, "initial provider discovery leaves the vendor error clear")
        if config.get("calculated"):
            calculated = left.cell(0, 598)
            ax.wait_for(lambda: calculated.read("AXValue") == "SKU 0600", "Calculated offscreen value did not load", timeout=15)
            check(True, "calculated columns reuse the display function for uncached rows")
        check(len(left.read("AXVisibleRows")) < 20, "logical rows are separate from the actual viewport")
        editors = [e for e in group.read("AXChildren") or [] if e.read("AXRole") == "AXTextField"]
        check(sorted(e.read("AXValue") for e in editors) == ["Left note", "Right note"], "ordinary fields coexist with repeated grids without child bridge methods")
        # Registered compiled startup can finish On Load before the vendor
        # lays out its first viewport. Measure reads against the live viewport.
        initial_viewport = ax.wait_for(lambda: state() if state().get("leftTop", 0) > 0 and state().get("rightTop", 0) > 0 else None, "AreaList initial viewport did not finish layout")
        first_position = initial_viewport["leftTop"]
        report["initial_viewport"] = {key: initial_viewport[key] for key in ("leftTop", "rightTop", "leftSelected", "rightSelected")}
        if args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / "alp-grid-voiceover", BUILD / "read-fixture-screen")
            report["voiceover"] = vo.steps
            try:
                vo.start()
                caption = vo.key("home")
                for _ in range(20):
                    if "Left lines" in caption and "table" in caption.lower():
                        break
                    caption = vo.key("right")
                check("Left lines" in caption and "table" in caption.lower(), "VoiceOver reaches the first repeated AreaList from ordinary form controls")
                vo.key("down", shift=True)
                first = vo.key("home")
                check("SKU" in first, "VoiceOver reads the first AreaList cell without a loading placeholder")
                end = vo.key("end")
                check("row599of599" in end.replace(" ", ""), "VoiceOver reaches the final logical AreaList row")
                value = vo.key("right")
                check("Left ready" in value, "VoiceOver reads the final picture column's text description")
                ax.wait_for(lambda: any(row.read("AXIndex") == 598 for row in left.read("AXVisibleRows") or []), "VoiceOver did not reveal the actual final vendor row", timeout=15)
                check(state()["rightTop"] == initial_viewport["rightTop"], "VoiceOver reading reveals the final row without moving the other instance")
                vo.key("space")
                ax.wait_for(lambda: state()["leftSelected"] == [final_key], "VoiceOver activation did not select the revealed vendor row", timeout=15)
                check(state()["leftSelected"] == [final_key] and state()["rightTop"] == initial_viewport["rightTop"], "VoiceOver selects and reveals the real row without moving the other instance")
                first = vo.key("home")
                check("SKU" in first, "VoiceOver returns to the beginning of the complete AreaList")
                vo.key("up", shift=True)
                caption = ""
                for _ in range(8):
                    caption = vo.key("right")
                    if "Left note" in caption:
                        break
                check("Left note" in caption, "VoiceOver leaves the vendor grid and reaches the ordinary editor")
                check(state()["leftError"] == state()["rightError"] == 0, "VoiceOver leaves the vendor error state clear")
                report["passed"] = True
            finally:
                vo.stop()
            return
        far = left.cell(1, 598)
        other = right.cell(1, 598)
        amount = left.cell(2, 598)
        ax.wait_for(lambda: far.read("AXValue") == "Left line 0600" and other.read("AXValue") == "Right line 0600", "Offscreen vendor values did not load", timeout=15)
        check(far.read("AXIdentifier") != other.read("AXIdentifier"), "same stable row keys in repeated subforms retain separate identities and values")
        ax.wait_for(lambda: amount.read("AXValue") == "600.25", "Formatted offscreen amount did not load", timeout=15)
        check(not amount.is_settable("AXValue"), "formatted numeric values retain the vendor's read-only behavior")
        styled = left.cell(3, 598)
        ax.wait_for(lambda: styled.read("AXValue") == "Left styled 0600", "Attributed vendor text did not load as readable text", timeout=15)
        check(not styled.is_settable("AXValue"), "styled text retains readable content without exposing vendor markup")
        picture = left.cell(4, 598)
        ax.wait_for(lambda: picture.read("AXValue") == "Left ready" and right.cell(4, 598).read("AXValue") == "Right ready", "Picture descriptions did not run in their owning form", timeout=15)
        check(not picture.is_settable("AXValue"), "picture indicators use application descriptions in each repeated form")
        hidden = left.cell(1, 3)
        ax.wait_for(lambda: hidden.read("AXValue") == "", "Vendor-invisible cell leaked a value", timeout=15)
        check(hidden.read("AXEnabled") is False, "vendor-invisible cell contents and actions remain unavailable")
        check(state()["leftTop"] == first_position and state()["leftSelected"] == [], "offscreen reads do not scroll or select the vendor area")
        protected = left.cell(1, 5)
        ax.wait_for(lambda: protected.read("AXValue") == "", "Protected vendor cell leaked a value", timeout=15)
        check(not protected.is_settable("AXValue"), "protected vendor cells do not advertise an unsafe text editor")
        press("Edit")
        ax.wait_for(lambda: state().get("editor", {}).get("row") == 7, "Existing action did not open the protected vendor editor", timeout=15)
        protected_ticks = state()["timerTicks"]
        ax.wait_for(lambda: state()["timerTicks"] > protected_ticks + 4, "Protected editor did not survive normal publication cycles", timeout=15)
        check(protected.read("AXValue") == "" and protected.read("AXChildren")[0].read("AXValue") == "", "directly focused protected editor never publishes its plaintext")
        ordinary = next(e for e in editors if e.read("AXValue") == "Left note")
        ordinary.set_boolean("AXFocused", True)
        ax.wait_for(lambda: not state().get("editor"), "Protected vendor editor did not close normally", timeout=15)
        settle()
        check(far.perform("AXScrollToVisible") == 0, "offscreen AreaList cell accepts the standard reveal action")
        ax.wait_for(lambda: any(row.read("AXIndex") == 598 for row in left.read("AXVisibleRows") or []), "Vendor did not reveal the final row", timeout=15)
        settle()
        check(state()["rightTop"] == initial_viewport["rightTop"] and state()["leftSelected"] == [], "reveal preserves selection and the other repeated viewport")
        row = left.slice("AXRows", 598, 1)[0]
        check(left.set_elements("AXSelectedRows", [row]) == 0, "complete AreaList selection accepts its logical row")
        ax.wait_for(lambda: state()["leftSelected"] == [final_key], "Selection did not reach the actual AreaList", timeout=15)
        settle()
        check(state()["rightSelected"] == [] and state()["leftSelections"] == 1, "only the owning AreaList and its existing shared handler receive selection")
        check(far.is_settable("AXValue"), "enterable AreaList cells advertise the existing vendor editor")
        if args.text != "supplementary":
            check(far.set_text("Unsafe 😀") == 0, "transport accepts a request the vendor cannot safely implement")
            ax.wait_for(lambda: group.read("AXHelp") == "AreaList cannot safely edit supplementary Unicode in the tested vendor versions", "Unsafe vendor input was not rejected", timeout=15)
            check(state()["leftValue"] == "Left line 0600" and not state().get("editor"), "unsupported input is rejected before opening or changing the editor")
        check(far.set_text(initial_edit) == 0, "standard AXValue starts vendor text entry")
        ax.wait_for(lambda: state().get("editor", {}).get("text") == initial_edit, "Vendor editor did not receive Unicode text", timeout=20)
        settle()
        editor = far.read("AXChildren")[0]
        check(far.read("AXFocused") is True and other.read("AXFocused") is False, "vendor focus identifies the correct repeated grid cell")
        ax.wait_for(lambda: editor.read("AXValue") == initial_edit, "Vendor editor value was not published", timeout=15)
        check(editor.set_range("AXSelectedTextRange", 0, 6) == 0, "standard selected range reaches the vendor editor")
        ax.wait_for(lambda: editor.read("AXSelectedText") == "Edited", "Vendor selection did not update", timeout=15)
        settle()
        if args.text != "supplementary":
            check(editor.set_string("AXSelectedText", "🎸") == 0, "active-editor replacement reaches host validation")
            ax.wait_for(lambda: group.read("AXHelp") == "AreaList cannot safely edit supplementary Unicode in the tested vendor versions", "Unsafe partial replacement was not rejected", timeout=15)
            check(editor.read("AXValue") == initial_edit and editor.read("AXSelectedText") == "Edited", "rejected replacement preserves editor text and selection")
        check(editor.set_string("AXSelectedText", replacement) == 0, "partial replacement uses the existing vendor editor")
        edited = replacement + initial_edit[6:]
        ax.wait_for(lambda: state().get("editor", {}).get("text") == edited, "Vendor partial replacement failed", timeout=20)
        settle()
        check(editor.read("AXSelectedTextRange") == (len(replacement.encode("utf-16-le")) // 2, 0), "vendor editor publishes its actual UTF-16 insertion position")
        check(editor.set_range("AXSelectedTextRange", len((replacement + " ").encode("utf-16-le")) // 2, len(initial_edit.split()[1].encode("utf-16-le")) // 2) == 0, "selection after replacement maps to the vendor's byte offsets")
        ax.wait_for(lambda: editor.read("AXSelectedText") == initial_edit.split()[1], "Selection after replacement did not reach the right text", timeout=15)
        settle()
        press_key(process, project, TITLE, editor.read("AXIdentifier"), 6, modifiers=1 << 20)
        ax.wait_for(lambda: editor.read("AXValue") != edited, "Normal vendor Undo did not change the editor", timeout=15)
        check(True, "the vendor's normal Undo shortcut accepts accessibility edits")
        report["after_undo"] = editor.read("AXValue")
        press_key(process, project, TITLE, editor.read("AXIdentifier"), 6, modifiers=(1 << 20) | (1 << 17))
        ax.wait_for(lambda: editor.read("AXValue") == edited, "Normal vendor Redo did not restore the editor", timeout=15)
        check(True, "the vendor's normal Redo shortcut restores the edit")
        ordinary = next(e for e in editors if e.read("AXValue") == "Left note")
        check(ordinary.set_boolean("AXFocused", True) == 0, "ordinary field accepts focus after vendor editing")
        ax.wait_for(lambda: state().get("leftValue") == edited and not state().get("editor"), "Normal vendor exit did not commit the value", timeout=15)
        settle()
        check(state()["rightValue"] == "Right line 0600", "editing preserves the other repeated grid's data")
        check(state()["leftStarts"] > 0 and state()["leftEnds"] > 0, "the existing vendor entry and exit callbacks run")
        ax.wait_for(lambda: far.read("AXValue") == edited, "Committed value did not refresh", timeout=15)
        check(far.set_text("REJECT") == 0, "normal application validation receives accessibility edits")
        ax.wait_for(lambda: state().get("editor", {}).get("text") == "REJECT", "Rejected test value did not reach the editor", timeout=15)
        settle()
        ordinary.set_boolean("AXFocused", True)
        ax.wait_for(lambda: state()["leftRejections"] > 0, "Existing vendor exit validation did not run", timeout=15)
        settle()
        check(state()["leftValue"] == edited and state().get("editor", {}).get("text") == "REJECT", "rejected exit preserves committed data and keeps the vendor editor open")
        check(far.set_text(edited) == 0, "the same editor can correct the rejected value")
        ax.wait_for(lambda: state().get("editor", {}).get("text") == edited, "Correction did not reach the vendor editor", timeout=15)
        settle()
        ordinary.set_boolean("AXFocused", True)
        ax.wait_for(lambda: not state().get("editor") and state()["leftValue"] == edited, "Corrected value did not commit normally", timeout=15)
        settle()
        ticks = state()["timerTicks"]
        press("Sort")
        ax.wait_for(lambda: state()["leftFirst"] == final_key, "Ordinary AreaList sort handler did not run", timeout=15)
        ax.wait_for(lambda: far.read("AXRowIndexRange") == (0, 1), "Cell identity did not follow the sorted stable key", timeout=15)
        check(True, "vendor sorting preserves logical cell identity at its new position")
        press("Loading")
        ax.wait_for(lambda: far.read("AXSize") in (None, (0, 0)), "Loading retained an active old cell", timeout=15)
        check(find("Right lines").count("AXRows") == 599, "readiness disables only the loading repeated grid")
        press("Loading")
        left = ax.wait_for(lambda: find("Left lines"), "Loaded grid did not return", timeout=15)
        new = left.cell(1, 0)
        check(new.read("AXIdentifier") != far.read("AXIdentifier"), "readiness transition retires the prior grid generation")
        identifier = new.read("AXIdentifier")
        press("Scope")
        ax.wait_for(lambda: (current := first_cell_identifier()) is not None and current != identifier, "New invoice scope did not retire old cells", timeout=15)
        check(new.read("AXSize") in (None, (0, 0)), "old invoice cell has no active geometry after scope change")
        check(state()["timerTicks"] > ticks, "existing form timer continues during grid actions")
        if config.get("calculated"):
            old = find("Left lines").cell(1, 0)
            identifier = old.read("AXIdentifier")
            press("Rebind")
            ax.wait_for(lambda: (current := first_cell_identifier()) is not None and current != identifier, "Column rebind did not retire old cells", timeout=15)
            rebound = find("Left lines").cell(1, 0)
            ax.wait_for(lambda: rebound.read("AXValue") == "Right line 0001", "Rebound column did not publish its new source", timeout=15)
            check(old.read("AXSize") in (None, (0, 0)) and old.set_text("STALE") != 0, "column rebind retires stale editors with unchanged keys and scope")
            check(True, "column rebind publishes its actual new source")
        check(state()["leftError"] == state()["rightError"] == 0, "all provider calls leave the sticky vendor error clear")
        close.press()
        process.wait(timeout=15)
        check(process.returncode == 0 and json.loads(closed.read_text(encoding="utf-8-sig"))["accepted"] is True, "normal standard-action close is accepted by the actual host")
        report["passed"] = True
    finally:
        if process.poll() is None and not report["passed"]:
            if locals().get("group") is not None:
                try:
                    report["failure_help"] = group.read("AXHelp")
                except RuntimeError as error:
                    report["failure_help_error"] = str(error)
            try:
                ax.capture_window(process.pid, BUILD / "alp-grid-last.png")
            except RuntimeError:
                pass
        try:
            report["last_state"] = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        if "group" in locals() and group is not None:
            report["last_receipt"] = group.read("AXHelp")
        if args.voiceover:
            (BUILD / "alp-grid-voiceover-report.json").write_text(json.dumps(report, indent=2) + "\n")
        else:
            (BUILD / "alp-grid-runtime-report.json").write_text(json.dumps(report, indent=2) + "\n")
            (BUILD / ("alp-grid-" + args.text + "-report.json")).write_text(json.dumps(report, indent=2) + "\n")
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
