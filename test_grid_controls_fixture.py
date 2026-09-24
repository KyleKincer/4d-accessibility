#!/usr/bin/env python3
"""Exercise real 4D grid widgets, focus, native callbacks and rejected edits."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

from build_component import sha
from prepare_grid_fixture import BUILD, FIXTURE, ROOT, TITLE
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
import doctor
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
    compiled = json.loads((BUILD / "logical-grid-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, "Prepared source changed after compilation"
    for path, key in [("Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge", "native_sha256"),
                      ("Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ", "component_sha256")]:
        assert sha(FIXTURE / path) == compiled[key]
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    assert config["cellControls"] and config["rowStates"]
    status = FIXTURE / "Resources/runtime-status.json"
    native_error = FIXTURE / "Resources/native-error.json"
    for path in [status, native_error, FIXTURE / "Resources/closed.json", FIXTURE / "Resources/widget-command.json"]:
        path.unlink(missing_ok=True)
    checks = []
    report = {"passed": False, "mode": "voiceover" if args.voiceover else "actions", **config, "checks": checks, "actions": [],
              "native_sha256": compiled["native_sha256"], "component_sha256": compiled["component_sha256"]}
    last_state = {}

    def state():
        nonlocal last_state
        if native_error.exists():
            raise AssertionError("Native 4D error: " + native_error.read_text(encoding="utf-8-sig"))
        try:
            last_state = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        assert not last_state.get("bridgeError") and not last_state.get("failure"), last_state
        return last_state

    def check(condition, name):
        checks.append({"passed": bool(condition), "name": name})
        print(("PASS: " if condition else "FAIL: ") + name, flush=True)
        assert condition, name

    project = FIXTURE / "Project/LogicalGridFixture.4DProject"
    command = ["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
               *(["--data", str(FIXTURE / "synthetic.4dd")] if config["kind"] == "entity" else ["--dataless"]),
               "--opening-mode", "interpreted", "--webadmin-auto-start", "false"]
    with (BUILD / "grid-controls-desktop.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
    close = None
    group = None
    try:
        ready, report["application_mode_notice_acknowledged"] = wait_for_start(
            process, project, lambda: state() if state().get("runId") == config["runId"] else None, BUILD)
        check(ready.get("start", {}).get("ok") is True and not ready["compiled"], "actual interpreted 4D starts the prepared widget fixture")
        app = ax.application(process.pid)
        report["architecture"] = ax.process_architecture(process.pid)
        window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None), "No owned fixture window")

        if app.read("AXFrontmost") is not True:
            check(app.set_boolean("AXFrontmost", True) == 0, "owned fixture accepts foreground activation")
        ax.wait_for(lambda: app.read("AXFrontmost") is True, "Owned fixture did not become active")
        ax.wait_for(lambda: app.read("AXFocusedWindow") and app.read("AXFocusedWindow").read("AXTitle") == TITLE, "Owned fixture window did not receive keyboard focus")

        def root():
            nonlocal group
            pending = [window]
            while pending:
                node = pending.pop()
                if (node.read("AXIdentifier") or "").startswith("axb.window."):
                    group = node
                    return node
                if node.read("AXRole") != "AXTable":
                    pending.extend(node.read("AXChildren") or [])
            return None

        def find(label, role=None):
            current = root()
            for node in current.read("AXChildren") or []:
                labels = [node.read("AXDescription"), node.read("AXTitle")]
                if label in [s.removeprefix("Grid: ") if isinstance(s, str) else s for s in labels] and (role is None or node.read("AXRole") == role):
                    return node
            return None

        table = ax.wait_for(lambda: find("Invoice lines"), "No accessible grid")
        close = find("Close")
        check(table.count("AXRows") == 599 and table.count("AXColumns") == 5, "all logical rows and widget columns are available")

        def content(column, row, role=None):
            def loaded():
                children = table.cell(column, row).read("AXChildren") or []
                node = children[0] if children else None
                return node if node and (role is None or node.read("AXRole") == role) else None
            return ax.wait_for(loaded, "Typed cell did not load", timeout=20)

        def settle():
            time.sleep(.2)
            return ax.wait_for(lambda: state() and group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action") and group.read("AXHelp"), "Action receipt did not settle", timeout=20)

        def row_state(key="line-0001"):
            return next(row for row in state()["widgets"]["rows"] if row["key"] == key)

        def focus_note():
            check(find("Note", "AXTextField").set_boolean("AXFocused", True) == 0, "ordinary editor accepts keyboard focus")
            ax.wait_for(lambda: find("Note", "AXTextField").read("AXFocused") is True, "Ordinary editor did not receive focus")
            settle()

        def menu():
            focused = app.read("AXFocusedUIElement")
            if focused and focused.read("AXRole") == "AXMenu":
                return focused
            pending = list(app.read("AXWindows") or [])
            while pending:
                node = pending.pop()
                if node.read("AXRole") == "AXMenu":
                    return node
                if node.read("AXRole") != "AXTable":
                    pending.extend(node.read("AXChildren") or [])
            return None

        if config.get("repeated"):
            peer = ax.wait_for(lambda: find("Peer: Invoice lines"), "Repeated sibling grid is missing")
            peer_checkbox = ax.wait_for(lambda: next((n for n in peer.cell(2, 0).read("AXChildren") or [] if n.read("AXRole") == "AXCheckBox"), None), "Repeated sibling checkbox did not load")
            first_checkbox = content(2, 0, "AXCheckBox")
            check(peer_checkbox.read("AXIdentifier") != first_checkbox.read("AXIdentifier"), "identical keys and control names have distinct subform identities")
            for cycle in range(2):
                for is_peer, node, other in [(True, peer_checkbox, first_checkbox), (False, first_checkbox, peer_checkbox)]:
                    check(node.set_boolean("AXFocused", True) == 0, "repeated grid accepts independent cell focus")
                    ax.wait_for(lambda: node.read("AXFocused") is True, "Repeated grid focus was not published")
                    settle()
                    check(other.read("AXFocused") is False and app.read("AXFocusedUIElement").read("AXIdentifier") == node.read("AXIdentifier"), "global focus resolves the owning grid after both retain cell positions")
                    main_before = row_state()["approved"]
                    peer_before = state()["peerWidgets"]["rows"][0]["approved"]
                    expected = not (peer_before if is_peer else main_before)
                    check(node.press() == 0, "repeated grid accepts native checkbox activation")
                    ax.wait_for(lambda: (state()["peerWidgets"]["rows"][0]["approved"] if is_peer else row_state()["approved"]) == expected, "Repeated grid did not change its own binding")
                    settle()
                    focus_note()
                    observed = {"cycle": cycle, "peer": is_peer, "main_before": main_before, "peer_before": peer_before, "expected": expected, "main_after": row_state()["approved"], "peer_after": state()["peerWidgets"]["rows"][0]["approved"], "ax_immediate": node.read("AXValue"), "identifier": node.read("AXIdentifier")}
                    report["actions"].append(observed)
                    ax.wait_for(lambda: node.read("AXValue") == int(expected), "Repeated widget accessibility value did not refresh")
                    observed["ax_settled"] = node.read("AXValue")
                    check((row_state()["approved"] == main_before if is_peer else state()["peerWidgets"]["rows"][0]["approved"] == peer_before) and node.read("AXValue") == int(expected), "repeated activation changes only the owning form binding")

        if args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / "grid-controls-voiceover", BUILD / "read-fixture-screen")
            report["voiceover"] = vo.steps
            try:
                vo.start()
                vo.key("home")
                vo.key("down", shift=True)
                first = vo.key("home")
                check("Line item 0001" in first, "VoiceOver enters the first logical row")
                vo.key("right")
                checkbox = vo.key("right")
                check("checkbox" in checkbox.lower().replace(" ", "") and "Approved" in checkbox, "VoiceOver reads the real checkbox role and caption")
                before = len(state()["widgets"]["events"])
                vo.key("space")
                ax.wait_for(lambda: row_state()["approved"] is True, "VoiceOver did not activate the checkbox")
                report["checkbox_receipt"] = settle()
                check({41, 20}.issubset({event["event"] for event in state()["widgets"]["events"][before:]}), "VoiceOver checkbox activation reaches native validation")
                time.sleep(.5)
                report["checkbox_feedback"] = vo.read_caption()
                check("checked" in report["checkbox_feedback"].lower() and "unchecked" not in report["checkbox_feedback"].lower(), "VoiceOver announces the confirmed checkbox state")
                popup = vo.key("right")
                check("Denied" in popup and "pop" in popup.lower(), "VoiceOver reads the popup's selected label and role")
                vo.key("space")
                choices = ax.wait_for(menu, "VoiceOver popup menu is missing")
                parent = choices.read("AXParent")
                check(parent and parent.read("AXIdentifier") == content(3, 0, "AXPopUpButton").read("AXIdentifier"), "the native menu belongs to its exact accessible popup cell")
                vo.key("down", voiceover=False)
                vo.key("return", voiceover=False)
                ax.wait_for(lambda: row_state()["decision"] is True, "VoiceOver popup choice did not commit")
                check(True, "VoiceOver chooses through the actual native popup menu")
                settle()
                after_menu = vo.key("right")
                check("Mixed" in after_menu and "checkbox" in after_menu.lower().replace(" ", ""), "VoiceOver stays in the grid after choosing a popup item")
                end = vo.key("end")
                check("row599of599" in end.replace(" ", ""), "VoiceOver reaches the final logical row across widget columns")
                vo.key("home")
                for _ in range(3):
                    popup_again = vo.key("right")
                check("Allowed" in popup_again and "pop" in popup_again.lower(), "VoiceOver returns to the same popup with its new value")
                vo.key("space")
                vo.key("escape", voiceover=False)
                after_cancel = vo.key("right")
                check("Mixed" in after_cancel and row_state()["decision"] is True, "cancelling the popup preserves its value and VoiceOver's table context")
                vo.key("home")
                vo.key("up", shift=True)
                for _ in range(5):
                    ordinary = vo.key("right")
                    if "Original note" in ordinary:
                        break
                check("Original note" in ordinary, "VoiceOver leaves widget cells for the ordinary editor")
                report["passed"] = True
            finally:
                vo.stop()
            return

        def toggle(column, expected, key="line-0001", row=0):
            node = content(column, row, "AXCheckBox")
            before = len(state()["widgets"]["events"])
            selected_before = state()["selected"]
            check(node.press() == 0, "native checkbox accepts activation")
            property_name = "approved" if column == 2 else "mixed"
            ax.wait_for(lambda: row_state(key)[property_name] == expected and content(column, row, "AXCheckBox").read("AXValue") == int(expected), "Checkbox state did not change", timeout=20)
            receipt = settle()
            events = state()["widgets"]["events"][before:]
            report["actions"].append({"column": column, "row": row, "expected": expected, "receipt": receipt, "events": events})
            check(receipt == "Cell checkbox state confirmed", "completion follows the actual checkbox state")
            check([event["event"] for event in events] == [41, 20], "existing entry and data-change handlers each run once")
            focus_note()
            check(state()["selected"] == selected_before, "checkbox activation preserves row selection after focus leaves the cell")

        boolean = content(2, 0, "AXCheckBox")
        mixed = content(4, 0, "AXCheckBox")
        popup = content(3, 0, "AXPopUpButton")
        check("Approved; reviewed" in (boolean.read("AXDescription") or ""), "semicolon in a checkbox caption does not create a popup")
        check(mixed.read("AXDescription") == "Mixed", "numeric checkbox uses its column label without speaking its number format")
        check(boolean.read("AXValue") == 0 and popup.read("AXValue") == "Denied", "typed widgets expose their native initial values")
        check(not boolean.is_settable("AXValue") and not popup.is_settable("AXValue"), "widget values cannot bypass native validation through text assignment")
        for row, expected in [(4, 0), (5, 1), (6, 2)]:
            node = content(4, row, "AXCheckBox")
            check(node.read("AXValue") == expected and node.read("AXEnabled") is False and "AXPress" not in node.actions(), "negative numeric state stays readable and disabled: " + str(row + 2))
        blank = content(4, 3)
        ax.wait_for(lambda: table.cell(4, 3).read("AXValue") != "Loading", "Invisible checkbox did not load")
        check(blank.read("AXRole") != "AXCheckBox" and table.cell(4, 3).read("AXValue") == "", "invisible numeric checkbox does not expose a checkbox")
        check(content(2, 1, "AXCheckBox").read("AXEnabled") is False, "disabled row also disables its checkbox")
        check("AXPress" not in content(2, 2, "AXCheckBox").actions(), "nonselectable row preserves native editing restrictions")
        focus_selection = list(state()["selected"])
        focus_events = len(state()["widgets"]["events"])
        check(boolean.set_boolean("AXFocused", True) == 0, "checkbox accepts focus without activation")
        ax.wait_for(lambda: boolean.read("AXFocused") is True, "Checkbox focus was not published")
        settle()
        check(row_state()["approved"] is False, "focusing a checkbox leaves its value unchanged")
        focused = app.read("AXFocusedUIElement")
        check(focused is not None and focused.read("AXIdentifier") == boolean.read("AXIdentifier"), "global accessibility focus identifies the exact cell widget")
        focus_note()
        check(boolean.read("AXFocused") is False, "moving to an ordinary editor clears cell focus")
        report["focus_only"] = {"selection_before": focus_selection, "selection_after": state()["selected"], "events": state()["widgets"]["events"][focus_events:]}
        check(row_state()["approved"] is False and 20 not in [event["event"] for event in report["focus_only"]["events"]], "focus and blur do not change the checkbox binding or send data-change")
        toggle(2, True)
        toggle(2, False)
        for expected in [1, 2, 0]:
            toggle(4, expected)

        before = len(state()["widgets"]["events"])
        popup_selection = state()["selected"]
        check(content(3, 0, "AXPopUpButton").perform("AXShowMenu") == 0, "popup opens its real native choices")
        choices = ax.wait_for(menu, "Native popup choices did not open")
        parent = choices.read("AXParent")
        check(parent and parent.read("AXIdentifier") == content(3, 0, "AXPopUpButton").read("AXIdentifier"), "native menu is a child of the exact popup cell")
        time.sleep(2.2)
        report["held_popup_receipt"] = group.read("AXHelp")
        check(menu() is not None, "native popup remains open beyond the normal action deadline")
        allowed = next(node for node in choices.read("AXChildren") if node.read("AXTitle") == "Allowed")
        check(allowed.press() == 0, "native menu item accepts selection")
        ax.wait_for(lambda: row_state()["decision"] is True and content(3, 0, "AXPopUpButton").read("AXValue") == "Allowed", "Popup did not commit the selected choice")
        popup_receipt = settle()
        check(popup_receipt == "Native cell choices opened", "a delayed popup choice retains the verified menu-opening receipt")
        check([event["event"] for event in state()["widgets"]["events"][before:]] == [41, 20], "popup selection invokes each native entry/data-change callback once")
        focus_note()
        check(state()["selected"] == popup_selection, "popup activation preserves row selection after leaving the cell")
        toggle(2, True, "line-0600", 598)
        check(any(row.read("AXIndex") == 598 for row in table.read("AXVisibleRows") or []), "offscreen activation reveals the real final row")

        check(find("Single click").press() == 0, "enable native single-click editing on a nonselectable row")
        ax.wait_for(lambda: state().get("singleClick") == 1 and "AXPress" in content(2, 2, "AXCheckBox").actions(), "Single-click editing did not enable the restricted row's checkbox")
        settle()
        toggle(2, True, "CAFÉ", 2)
        check("CAFÉ" not in state()["selected"], "editing a nonselectable checkbox does not select its row")
        check(find("Single click").press() == 0, "restore native editing restrictions")
        ax.wait_for(lambda: state().get("singleClick") == 0 and "AXPress" not in content(2, 2, "AXCheckBox").actions(), "Restored restriction did not disable widget activation")
        settle()

        sequence = 0
        def configure(**flags):
            nonlocal sequence
            sequence += 1
            (FIXTURE / "Resources/widget-command.json").write_text(json.dumps({"action": "configure", "sequence": sequence, **flags}))
            ax.wait_for(lambda: state()["widgets"]["sequence"] == sequence, "Application validation configuration was not consumed")
            time.sleep(.2)

        if config["kind"] == "array":
            for alignment, padding, column_padding in [(2, 12, -255), (3, 12, 18), (4, 12, 0)]:
                layout = {"alignment": alignment, "padding": padding, "columnPadding": column_padding}
                configure(layout=layout)
                report["actions"].append({"layout": layout})
                toggle(2, True)
                toggle(2, False)
                for expected in (1, 2, 0):
                    toggle(4, expected)
            configure(layout={"alignment": 1, "padding": 0, "columnPadding": -255})

        check(content(2, 0, "AXCheckBox").set_boolean("AXFocused", True) == 0, "focus a checkbox before changing its entry validation")
        ax.wait_for(lambda: content(2, 0, "AXCheckBox").read("AXFocused") is True, "Checkbox did not retain keyboard focus")
        settle()
        configure(reject=True)
        before = len(state()["widgets"]["events"])
        check(content(2, 0, "AXCheckBox").press() == 0, "request entry rejection on an already-focused cell")
        ax.wait_for(lambda: len(state()["widgets"]["events"]) > before, "Already-focused entry did not invoke validation")
        time.sleep(1.8)
        receipt = settle()
        report["actions"].append({"validation": "alreadyFocusedReject", "receipt": receipt, "value": row_state()["approved"], "events": state()["widgets"]["events"][before:]})
        check(row_state()["approved"] is False and receipt != "Cell checkbox state confirmed", "refused entry cannot reuse a previous cell position to toggle")
        configure()

        check(content(3, 0, "AXPopUpButton").set_boolean("AXFocused", True) == 0, "popup accepts focus independently of opening choices")
        ax.wait_for(lambda: content(3, 0, "AXPopUpButton").read("AXFocused") is True, "Popup did not receive focus")
        settle()
        check(menu() is None and row_state()["decision"] is True, "focusing a popup does not open or change it")
        configure(reject=True)
        before = len(state()["widgets"]["events"])
        check(content(3, 0, "AXPopUpButton").press() == 0, "popup entry invokes normal rejection")
        ax.wait_for(lambda: len(state()["widgets"]["events"]) > before, "Popup rejection handler did not run")
        time.sleep(1.8)
        receipt = settle()
        report["actions"].append({"validation": "popupReject", "receipt": receipt, "events": state()["widgets"]["events"][before:]})
        check(menu() is None and row_state()["decision"] is True and receipt != "Native cell choices opened", "refused popup entry never reports an opened menu")
        configure()

        configure(afterRedirect=True, afterDisable=True)
        focus_note()
        check(content(2, 0, "AXCheckBox").press() == 0, "activate a checkbox whose data-change handler advances focus")
        ax.wait_for(lambda: row_state()["approved"] is True and find("Note", "AXTextField").read("AXFocused") is True, "Data-change handler did not advance focus after editing")
        receipt = settle()
        report["actions"].append({"validation": "afterRedirect", "receipt": receipt, "value": row_state()["approved"]})
        check(receipt == "Cell checkbox state confirmed", "a completed edit remains successful when its handler advances focus and locks the column")
        if config.get("repeated"):
            note = find("Note", "AXTextField")
            check(note.set_text("Edited after grid") == 0, "the observed child editor accepts ordinary text input")
            report["observed_editor_receipt"] = settle()
            ax.wait_for(lambda: note.read("AXValue") == "Edited after grid", "Observed child editor did not accept text", timeout=20)
            check(find("Peer: Note", "AXTextField").read("AXValue") == "Original note", "editing after a native handler preserves the sibling editor")
        configure()
        toggle(2, False)

        for flag in ["reject", "redirect", "revert", "disable", "rebind"]:
            configure(**{flag: True})
            focus_note()
            previous = content(2, 0, "AXCheckBox")
            before = len(state()["widgets"]["events"])
            old_identifier = previous.read("AXIdentifier")
            old_value = row_state()["approved"]
            check(previous.press() == 0, "native entry request reaches application validation: " + flag)
            ax.wait_for(lambda: len(state()["widgets"]["events"]) > before, "Before-entry validation was not invoked")
            time.sleep(1.8)
            receipt = settle()
            report["actions"].append({"validation": flag, "receipt": receipt, "value": row_state()["approved"], "events": state()["widgets"]["events"][before:]})
            # Physical clicks prove that GOTO OBJECT does not reject a checkbox
            # change. Changing only our scope marker also leaves the native
            # click intact, but retires the bridge identity before confirmation.
            expected_value = not old_value if flag in ("redirect", "rebind") else old_value
            check(row_state()["approved"] == expected_value, "entry behavior matches the physical-click reference: " + flag)
            check((receipt == "Cell checkbox state confirmed") == (flag == "redirect"), "completion respects native rejection and scope retirement: " + flag)
            if flag == "rebind":
                table = ax.wait_for(lambda: find("Invoice lines"), "Replacement grid missing")
                ax.wait_for(lambda: content(2, 0, "AXCheckBox").read("AXIdentifier") != old_identifier, "Form replacement retained an old widget")
                check(previous.read("AXSize") in (None, (0.0, 0.0)) and previous.press() != 0, "retained widget cannot act on a replacement form")
            configure()
        close = find("Close")
        check(close.press() == 0, "normal standard-action close is accessible")
        process.wait(timeout=15)
        check(process.returncode == 0, "owned fixture closes normally")
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        if group is not None and process.poll() is None:
            focused = app.read("AXFocusedUIElement")
            report["failure_focus"] = {"global": focused.read("AXIdentifier") if focused else None, "controls": [{"id": n.read("AXIdentifier"), "label": n.read("AXDescription"), "focused": n.read("AXFocused"), "position": n.read("AXPosition"), "size": n.read("AXSize")} for n in group.read("AXChildren") or []]}
        raise
    finally:
        report["final_state"] = last_state
        if group is not None and process.poll() is None:
            report["final_receipt"] = group.read("AXHelp")
        if not report["passed"] and process.poll() is None:
            try:
                ax.capture_window(process.pid, BUILD / "grid-controls-failure.png")
            except RuntimeError:
                pass
        destination = "grid-controls-voiceover-report.json" if args.voiceover else "grid-controls-runtime-report.json"
        (BUILD / destination).write_text(json.dumps(report, indent=2) + "\n")
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
