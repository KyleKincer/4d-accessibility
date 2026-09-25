#!/usr/bin/env python3
"""Launch and validate only the prepared synthetic 4D logical-grid fixture."""
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
from fixture_desktop import activate_fixture, press_key, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true", help="Run the compiled ARM desktop fixture")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--voiceover", action="store_true", help="Check grid reading, beginning/end navigation, reveal and return to ordinary controls")
    mode.add_argument("--voiceover-probe", action="store_true", help="Record owned VoiceOver navigation instead of the action suite")
    mode.add_argument("--cancel", action="store_true", help="Verify the host's normal Escape cancellation and post-dialog data")
    args = parser.parse_args()
    if not args.run or not ax.trusted() or not doctor.desktop_session()["unlocked"]:
        parser.error("--run, existing Accessibility permission and an unlocked desktop are required")
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before this owned fixture run")
    compiled = json.loads((BUILD / "logical-grid-compile-report.json").read_text())
    assert compiled["passed"]
    for relative, expected in compiled["sources_sha256"].items():
        assert sha(FIXTURE / relative) == expected, "Prepared source changed after compilation"
    assert sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge") == compiled["native_sha256"]
    assert sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ") == compiled["component_sha256"]
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    def source_key(text):
        key_type = config.get("keyType", "text")
        if key_type == "text":
            return text
        minimum, maximum = (-32768, 32767) if key_type == "integer" else (-2147483648, 2147483647)
        return {"line-0001": 1, "line-0600": maximum, "café": minimum, "CAFÉ": minimum + 1, "CAFE": 0, "cafe": maximum - 1}[text]

    status = FIXTURE / "Resources/runtime-status.json"
    status.unlink(missing_ok=True)
    closed = FIXTURE / "Resources/closed.json"
    closed.unlink(missing_ok=True)
    native_error = FIXTURE / "Resources/native-error.json"
    native_error.unlink(missing_ok=True)
    checks = []
    report = {"passed": False, "mode": "voiceover-probe" if args.voiceover_probe else "voiceover" if args.voiceover else "cancel" if args.cancel else "actions", "checks": checks, "compiled": args.compiled, **config, "native_sha256": compiled["native_sha256"], "component_sha256": compiled["component_sha256"]}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        if not condition:
            raise AssertionError(message)

    last_state = {}

    def state():
        nonlocal last_state
        if native_error.exists():
            raise AssertionError("Native 4D error: " + native_error.read_text(encoding="utf-8-sig"))
        try:
            value = json.loads(status.read_text(encoding="utf-8-sig"))
        except (FileNotFoundError, ValueError):
            return last_state
        if value.get("bridgeError") or value.get("failure"):
            raise AssertionError(f"Fixture bridge failed: {value}")
        last_state = value
        return value

    application_path = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
    project = FIXTURE / "Project/LogicalGridFixture.4DProject"
    command = ["/usr/bin/arch", "-arm64", str(application_path), "--project", str(project),
               *(["--data", str(FIXTURE / "synthetic.4dd")] if config.get("kind") == "entity" else ["--dataless"]), "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    with (BUILD / "logical-grid-desktop.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
    close = None
    try:
        ready, report["application_mode_notice_acknowledged"] = wait_for_start(
            process, project, lambda: state() if state().get("runId") == config["runId"] else None, BUILD)
        check(ready.get("start", {}).get("ok") is True and ready["compiled"] is args.compiled, "automatic form starts in the requested desktop mode")
        report["architecture"] = ax.process_architecture(process.pid)
        check(report["architecture"].replace("-", "").startswith("ARM64"), "actual native ARM execution")
        app, window = activate_fixture(process, project, TITLE)
        pending = [window]
        group = None
        while pending:
            item = pending.pop()
            identifier = item.read("AXIdentifier")
            if isinstance(identifier, str) and identifier.startswith("axb.window."):
                group = item
                break
            if item.read("AXRole") != "AXTable":
                pending.extend(item.read("AXChildren") or [])
        check(group is not None, "one root contains both ordinary controls and grid")

        def controls():
            return {item.read("AXDescription") or item.read("AXTitle"): item for item in group.read("AXChildren") or []}

        def find(label, role=None):
            nonlocal group
            # Application reconfiguration uses the public stop/start lifecycle.
            # Resolve the current root rather than retaining a retired group.
            pending = [window]
            while pending:
                candidate = pending.pop()
                identifier = candidate.read("AXIdentifier")
                if isinstance(identifier, str) and identifier.startswith("axb.window."):
                    group = candidate
                    break
                if candidate.read("AXRole") != "AXTable":
                    pending.extend(candidate.read("AXChildren") or [])
            for item in group.read("AXChildren") or []:
                labels = (item.read("AXDescription"), item.read("AXTitle"))
                if config.get("subform"):
                    labels = tuple(value.removeprefix("Grid: ") if isinstance(value, str) else value for value in labels)
                if label in labels and (role is None or item.read("AXRole") == role):
                    return item
            return None

        def current_cell_attribute(column, row, attribute):
            current = find("Invoice lines")
            if current is None:
                return None
            try:
                return current.cell(column, row).read(attribute)
            except RuntimeError as error:
                # A renderer change stops and restarts the bridge. A table
                # can retire between the lookup and the indexed AX read.
                if str(error).endswith(", -25202"):  # kAXErrorInvalidUIElement
                    return None
                raise

        table = ax.wait_for(lambda: find("Invoice lines"), "Logical grid not published")
        close = find("Close")
        if config.get("subform"):
            # 4D initially focuses the subform container. Choose a real entry
            # control before testing actions that preserve keyboard focus.
            ax.wait_for(lambda: state().get("windowActive"), "Initial active window was not published")
            note = find("Note", "AXTextField")
            check(note.set_boolean("AXFocused", True) == 0, "child field accepts initial focus through AX")
            ax.wait_for(lambda: note.read("AXFocused") is True and state().get("focus") == "Note", "Child field did not receive actual keyboard focus")
            check(True, "child focus agrees with the actual 4D entry control")
        ax.wait_for(lambda: state().get("windowActive") and state().get("focused"), "Initial active focus was not published")
        def settle():
            ax.wait_for(lambda: state() and group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"), "Action did not receive provider completion", timeout=30)
        if config.get("slowVisibleSelection"):
            before = [row.read("AXIdentifier") for row in table.read("AXVisibleRows") or []]
            row = table.slice("AXRows", 0, 1)[0]
            check(row.read("AXIdentifier") in before, "selection target is already visible")
            check(row.press() == 0, "visible selection reaches the normal 4D binding")
            ax.wait_for(lambda: state().get("selected") == ["line-0001"], "Visible selection did not reach 4D", timeout=15)
            settle()
            report["selectionReceipt"] = group.read("AXHelp")
            check(report["selectionReceipt"] == "List box selection confirmed",
                  "expensive application callbacks do not cause a false timeout for a visible selection")
            check([item.read("AXIdentifier") for item in table.read("AXVisibleRows") or []] == before,
                  "confirmed visible selection preserves the viewport")
            check(state()["hooks"] == 0, "selection does not invent an application callback")
            close.press()
            process.wait(timeout=15)
            check(process.returncode == 0, "normal host close succeeds after delayed confirmation")
            report["passed"] = True
            return
        if args.voiceover_probe or args.voiceover:
            from voiceover import VoiceOver
            vo = VoiceOver(process, project, TITLE, BUILD / "logical-grid-voiceover", BUILD / "read-fixture-screen")
            report["voiceover"] = vo.steps
            try:
                vo.start()
                vo.key("home")
                vo.key("down", shift=True)
                first = vo.key("home")
                for _ in range(4 if config.get("described") else 8):
                    vo.key("right")
                end = vo.key("end")
                value = vo.key("right")
                if config.get("described"):
                    protected = value
                    readiness = vo.key("left")
                    value = vo.key("left")
                report["voiceover_state"] = state()
                report["end_visible"] = any(row.read("AXIndex") == 598 for row in table.read("AXVisibleRows") or [])
                if args.voiceover:
                    check("Line item 0001" in first, "VoiceOver reads the first visible value without a loading placeholder")
                    if config.get("described"):
                        check(any("Readiness Ready: Line item 0001" in step["caption"] for step in vo.steps), "VoiceOver reads custom descriptions alongside native scalar cells")
                    else:
                        check(any("Line item 0005" in step["caption"] for step in vo.steps), "VoiceOver reads enterable cells as text")
                    check("row599of599" in end.replace(" ", ""), "VoiceOver End reaches the final logical row")
                    check("600.25" in value, "VoiceOver reads the asynchronously loaded final-column value")
                    check(report["end_visible"], "VoiceOver reading reveals the real final row")
                    if config.get("described"):
                        check("Ready: Line item 0600" in readiness and state()["descriptionCalls"] > 0, "VoiceOver reads the custom offscreen description in its owning form context")
                        check("PRIVATE" not in protected and state()["protectedCalls"] == 0, "VoiceOver does not expose or compute protected descriptions")
                    vo.key("space")
                    ax.wait_for(lambda: state()["selected"] == [source_key("line-0600")], "VoiceOver activation did not select the revealed row", timeout=15)
                    check(True, "VoiceOver activation selects the revealed row through the existing handler")
                    first = vo.key("home")
                    ax.wait_for(lambda: any(row.read("AXIndex") == 0 for row in table.read("AXVisibleRows") or []), "VoiceOver Home did not reveal the first row", timeout=15)
                    check("Line item 0001" in first, "VoiceOver returns to the beginning of the complete grid")
                    vo.key("up", shift=True)
                    ordinary = ""
                    for _ in range(4):
                        ordinary = vo.key("right")
                        if "Original note" in ordinary:
                            break
                    check("Original note" in ordinary, "VoiceOver leaves the grid and reaches the ordinary form editor")
                    report["passed"] = True
                report["probe_completed"] = True
            finally:
                vo.stop()
            return
        check(find("Note") is not None and find("Sort") is not None and close is not None, "grid configuration preserves ordinary fields and buttons")
        diagnostics = ax.wait_for(lambda: state().get("diagnostics") if state().get("diagnostics", {}).get("ready") else None, "Grid diagnostics missing")
        check(not diagnostics["issues"], "configured grid and labelled ordinary controls have no false unsupported diagnostics")
        for button, reason in [("Toggle ready", "gridLoading"), ("Toggle valid keys", "gridUnavailable")]:
            check(find(button).press() == 0, "exercise coverage state: " + reason)
            ax.wait_for(lambda: any(i["object"] == "Items" and i["reason"] == reason for i in state()["diagnostics"]["issues"]), "Grid coverage reason missing: " + reason)
            settle()
            check(len(state()["diagnostics"]["issues"]) == 1, "grid reason replaces the generic unsupported diagnostic: " + reason)
            check(find(button).press() == 0, "restore configured grid after " + reason)
            ax.wait_for(lambda: not state()["diagnostics"]["issues"], "Restored grid retained a stale coverage issue")
            settle()
        table = ax.wait_for(lambda: find("Invoice lines"), "Restored grid not published")
        check(table.count("AXRows") == 599, "all 599 non-hidden logical rows are accessible")
        check(table.count("AXColumns") == (4 if config.get("described") else 2), "hidden identity and decorative columns stay out of readable columns")
        described = None
        if config.get("described"):
            described = table.cell(2, 598)
            secret = table.cell(3, 598)
            ax.wait_for(lambda: described.read("AXValue") == "Ready: Line item 0600", "Custom far-row description did not load")
            column = table.slice("AXColumns", 2, 1)[0]
            check("Readiness" in (column.read("AXDescription") or column.read("AXTitle") or ""), "column metadata supplies the meaningful header")
            ax.wait_for(lambda: secret.read("AXValue") != "Loading", "Protected cell did not settle")
            check(secret.read("AXValue") == "" and state()["protectedCalls"] == 0, "protected and hidden columns never invoke their description callbacks")
            check(not described.is_settable("AXValue") and not secret.is_settable("AXValue"), "descriptions preserve read-only semantics")
            initial_selection = state()["selected"]
            initial_hooks = state()["hooks"]
            check(described.perform("AXScrollToVisible") == 0, "custom offscreen column offers standard reveal")
            ax.wait_for(lambda: group.read("AXHelp") == "Cell is visible", "Custom column reveal was not confirmed")
            check(state()["selected"] == initial_selection and state()["hooks"] == initial_hooks, "custom value paging and reveal leave selection and business handlers unchanged")
            old_description = described
            old_id = described.read("AXIdentifier")
            check(find("Descriptions").press() == 0, "replace the application description with an invalid result")
            ax.wait_for(lambda: (identity := current_cell_attribute(2, 598, "AXIdentifier")) is not None and identity != old_id, "Changed renderer did not retire prior cells")
            table = find("Invoice lines")
            described = table.cell(2, 598)
            ax.wait_for(lambda: described.read("AXValue") == "Cell description required", "Invalid description was serialized or ignored")
            ax.wait_for(lambda: any(issue["reason"] == "gridValueDescriptionRequired" for issue in state()["diagnostics"]["issues"]), "Description failure is missing from coverage")
            check(old_description.read("AXSize") in (None, (0.0, 0.0)), "replaced description retires retained cell references")
            check(find("Descriptions").press() == 0, "restore the existing application renderer")
            ax.wait_for(lambda: current_cell_attribute(2, 598, "AXValue") == "Ready: Line item 0600", "Corrected renderer did not recover")
            ax.wait_for(lambda: not state()["diagnostics"]["issues"], "Corrected renderer kept obsolete diagnostics")
            table = find("Invoice lines")
            described = table.cell(2, 598)
            check(state()["protectedCalls"] == 0, "custom renderer replacement still does not read protected or hidden values")
            check(find("Custom editing").press() == 0, "enable native custom-column editing to audit the remaining interaction gap")
            expected_columns = {"ItemStatus", "ItemSecret", "ItemDecoration"}
            ax.wait_for(lambda: {issue.get("column") for issue in state()["diagnostics"]["issues"] if issue["reason"] == "gridCellEditingPending"} == expected_columns, "Enterable custom columns are missing from the coverage report")
            check(state()["customEditable"] and not described.is_settable("AXValue") and not table.cell(3, 598).is_settable("AXValue"), "enterable described columns remain guarded and report their editing gap by column name")
            check(find("Custom editing").press() == 0, "restore read-only native custom columns")
            ax.wait_for(lambda: not state()["diagnostics"]["issues"], "Read-only restoration did not clear editing diagnostics")
            check(True, "coverage follows the actual custom-column editing flags")
            find("Top").press()
            settle()
        check(0 < len(table.read("AXVisibleRows")) < 599, "viewport is separate from complete row count")
        visible_before = [row.read("AXIdentifier") for row in table.read("AXVisibleRows") or []]
        visible_row = table.slice("AXRows", 1, 1)[0]
        selection_hooks = state()["hooks"]
        check(visible_row.read("AXIdentifier") in visible_before and visible_row.press() == 0,
              "select an already visible row through the existing list box")
        ax.wait_for(lambda: group.read("AXHelp") == "List box selection confirmed",
                    "Visible row selection lacked confirmed completion", timeout=15)
        check([row.read("AXIdentifier") for row in table.read("AXVisibleRows") or []] == visible_before,
              "selecting an already visible row preserves the viewport")
        check(state()["hooks"] == selection_hooks + 1,
              "visible selection invokes the settled application handler exactly once")
        check(table.set_elements("AXSelectedRows", []) == 0, "clear the visible-row selection")
        ax.wait_for(lambda: state()["selected"] == [] and group.read("AXHelp") == "List box selection confirmed",
                    "Visible-row selection did not clear", timeout=15)
        far_row = table.slice("AXRows", 598, 1)[0]
        far = table.cell(0, 598)
        identity = far.read("AXIdentifier")
        initial_ticks = state()["timerTicks"]
        ax.wait_for(lambda: state()["timerTicks"] > initial_ticks + 2, "Existing timer stopped")
        check(table.cell(0, 598).read("AXIdentifier") == identity, "unchanged bindings preserve cell identity across refreshes")
        ax.wait_for(lambda: far.read("AXValue") == "Line item 0600", "Far row value did not load", timeout=15)
        check(True, "offscreen final row loads through the owning 4D process")
        amount = table.cell(1, 598)
        ax.wait_for(lambda: amount.read("AXValue") == "600.25", "Far numeric cell did not load", timeout=15)
        check(True, "each offscreen column has its own formatted value")
        if config.get("kind", "array") == "array" or config.get("rowStates"):
            check(table.cell(0, 1).read("AXEnabled") is False and "AXPress" in table.slice("AXRows", 1, 1)[0].actions(), "disabled cells remain noneditable while their row can be selected like native 4D")
        if config.get("rowStates"):
            blocked = table.cell(0, 1)
            conditional = table.cell(0, 2)
            conditional_row = table.slice("AXRows", 2, 1)[0]
            ax.wait_for(lambda: conditional.read("AXValue") == "Line item 0004", "Unselectable row value did not load")
            check(not blocked.is_settable("AXValue") and not conditional.is_settable("AXValue"), "disabled and nonselectable rows initially reject text editing")
            check(conditional.read("AXEnabled") is True and "AXPress" not in conditional_row.actions() and "AXPress" not in conditional.actions(), "nonselectable rows and cells stay readable without advertising unavailable actions")
            check(table.slice("AXRows", 1, 1)[0].press() == 0, "disabled row accepts selection independently of its cell editing restriction")
            ax.wait_for(lambda: state()["selected"] == [source_key("café")] and group.read("AXHelp") == "List box selection confirmed", "Disabled row selection did not match native 4D")
            check(not blocked.is_settable("AXValue"), "selecting a disabled row does not enable its cell editor")
            table.set_elements("AXSelectedRows", [])
            ax.wait_for(lambda: state()["selected"] == [] and group.read("AXHelp") == "List box selection confirmed", "Disabled row selection did not clear")
            if config.get("kind") in ("collection", "entity"):
                nullable = table.cell(0, 5)
                ax.wait_for(lambda: nullable.read("AXValue") == "Line item 0007", "Nullable metadata row did not load")
                check(nullable.read("AXEnabled") is True and nullable.is_settable("AXValue"), "Null row flags and cell-level disabled flags do not restrict a normal native editor")
            check(find("Single click").press() == 0, "enable the application's native single-click editing option")
            ax.wait_for(lambda: state().get("singleClick") == 1 and conditional.is_settable("AXValue"), "Single-click option did not enable the nonselectable editor")
            settle()
            check(conditional.set_text("Unselected 🎸") == 0, "nonselectable row accepts its existing single-click editor")
            ax.wait_for(lambda: state().get("edited") == "Unselected 🎸", "Single-click row editor did not receive supplementary Unicode", timeout=20)
            settle()
            check(source_key("CAFÉ") not in state()["selected"], "editing the nonselectable row does not highlight it")
            find("Note", "AXTextField").set_boolean("AXFocused", True)
            ax.wait_for(lambda: state().get("focus") == "Note", "Single-click row edit did not commit normally")
            settle()
            ax.wait_for(lambda: conditional.read("AXValue") == "Unselected 🎸" and state()["changes"] > 0, "Native commit did not refresh the unselected row value")
            check(True, "native validation commits the unselected row edit")
            find("Single click").press()
            ax.wait_for(lambda: state().get("singleClick") == 0 and not conditional.is_settable("AXValue"), "Disabling single-click edit did not restore its guard")
            settle()
            check(find("Selection none").press() == 0, "switch the existing list box to selection mode None")
            ax.wait_for(lambda: state().get("selectionMode") == 0 and conditional.is_settable("AXValue"), "Selection None did not ignore the unselectable flag")
            settle()
            check(conditional.set_text("No selection mode") == 0, "selection mode None permits the ordinary editor")
            ax.wait_for(lambda: state().get("edited") == "No selection mode", "Selection None editor did not receive input")
            settle()
            find("Note", "AXTextField").set_boolean("AXFocused", True)
            ax.wait_for(lambda: state().get("focus") == "Note", "Selection None edit did not commit")
            settle()
            check(not blocked.is_settable("AXValue"), "disabled rows stay noneditable in selection mode None")
            find("Selection none").press()
            ax.wait_for(lambda: state().get("selectionMode") == 2 and not conditional.is_settable("AXValue"), "Multiple-selection mode did not restore the row restriction")
            settle()
            far_identity = far.read("AXIdentifier")
            check(find("Disable far").press() == 0, "change row metadata through the existing application state")
            ax.wait_for(lambda: state().get("disableFar") is True and far.read("AXEnabled") is False, "Offscreen row did not become disabled")
            check(not far.is_settable("AXValue"), "retained offscreen cell loses editing when its row becomes disabled")
            find("Disable far").press()
            ax.wait_for(lambda: state().get("disableFar") is False and far.is_settable("AXValue"), "Restored row did not regain its editor")
            check(far.read("AXIdentifier") == far_identity, "row-state changes preserve record identity")
            settle()
            far_row.press()
            ax.wait_for(lambda: state()["selected"] == [source_key("line-0600")] and group.read("AXHelp") == "List box selection confirmed", "Initial retained selection did not settle")
            find("Restrict selection").press()
            ax.wait_for(lambda: state().get("unselectFar") is True and "AXPress" not in far_row.actions(), "Selected row did not become unselectable")
            settle()
            first_row = table.slice("AXRows", 0, 1)[0]
            check(first_row.set_boolean("AXSelected", True) == 0, "multi-selection can add a row while retaining a restricted selected row")
            ax.wait_for(lambda: set(state()["selected"]) == {source_key("line-0001"), source_key("line-0600")} and group.read("AXHelp") == "List box selection confirmed", "Adding another row lost or rejected the restricted selection")
            check(first_row.set_boolean("AXSelected", False) == 0, "multi-selection can remove another row while retaining the restricted row")
            ax.wait_for(lambda: state()["selected"] == [source_key("line-0600")] and group.read("AXHelp") == "List box selection confirmed", "Removing another row changed the restricted selection")
            report["restricted_deselection_probe"] = {"before": state(), "nativeSelected": [r.read("AXIdentifier") for r in table.read("AXSelectedRows") or []], "rowSelected": far_row.read("AXSelected"), "rowEnabled": far_row.read("AXEnabled"), "settable": far_row.is_settable("AXSelected"), "rowIdentifier": far_row.read("AXIdentifier"), "beforeHelp": group.read("AXHelp")}
            check(far_row.set_boolean("AXSelected", False) == 0, "a previously selected restricted row can be deselected")
            report["restricted_deselection_probe"]["immediateHelp"] = group.read("AXHelp")
            ax.wait_for(lambda: state()["selected"] == [] and group.read("AXHelp") == "List box selection confirmed", "Restricted selection did not clear")
            find("Restrict selection").press()
            ax.wait_for(lambda: state().get("unselectFar") is False and "AXPress" in far_row.actions(), "Row selection permission did not restore")
            settle()
            find("Restrict during selection").press()
            ax.wait_for(lambda: state().get("restrictOnSelection") is True and group.read("AXHelp") == "Activation dispatched through the control's normal event path", "Selection restriction mode did not activate")
            callback_count = state()["hooks"]
            check(far_row.press() == 0, "select a row whose application callback will restrict it")
            ax.wait_for(lambda: group.read("AXHelp") == "Row became unavailable during selection", "A row restricted by its callback was incorrectly confirmed")
            check(state().get("unselectFar") is True and state()["hooks"] == callback_count + 1, "confirmation rereads row metadata after the single application callback")
            find("Restrict during selection").press()
            ax.wait_for(lambda: state().get("restrictOnSelection") is False and group.read("AXHelp") == "Activation dispatched through the control's normal event path", "Selection restriction mode did not stop")
            table.set_elements("AXSelectedRows", [])
            ax.wait_for(lambda: state()["selected"] == [] and group.read("AXHelp") == "List box selection confirmed", "Callback-restricted selection did not clear")
            find("Restrict selection").press()
            ax.wait_for(lambda: state().get("unselectFar") is False and far.is_settable("AXValue"), "Callback restriction did not restore normally")
            settle()
            if config.get("storedMeta"):
                prior_cell = far
                check(find("Swap stored metadata").press() == 0, "switch the native stored metadata property without a bridge restart")
                ax.wait_for(lambda: state().get("swappedMeta") is True and (t := find("Invoice lines")) is not None and t.cell(0, 598).read("AXIdentifier") != far_identity, "Direct metadata-source replacement did not retire prior cells")
                check(prior_cell.read("AXSize") in (None, (0.0, 0.0)), "retained cells cannot target a replacement stored metadata source")
                table = find("Invoice lines")
                far = table.cell(0, 598)
                far_row = table.slice("AXRows", 598, 1)[0]
                amount = table.cell(1, 598)
                ax.wait_for(lambda: far.read("AXValue") == "Line item 0600" and amount.read("AXValue") == "600.25", "Replacement stored metadata source did not load")
                settle()
            if config.get("kind") in ("collection", "entity") and not config.get("storedMeta"):
                check(state().get("metaCalls", 0) > 0 and state().get("metaArgumentsOK") is True, "the metadata Formula receives the original This/item, key, one-based row and owning Form")
                find("Invalid metadata").press()
                ax.wait_for(lambda: state().get("invalidMeta") is True and any(i.get("reason") == "gridUnavailable" for i in state()["diagnostics"].get("issues", [])), "Invalid metadata result did not disable the grid with a diagnostic")
                check(far.read("AXSize") in (None, (0.0, 0.0)) and far.set_text("Must not edit") != 0, "invalid row metadata retires the cell and rejects further editor requests")
                find("Invalid metadata").press()
                ax.wait_for(lambda: state().get("invalidMeta") is False and (t := find("Invoice lines")) is not None and t.read("AXRowCount") == 599, "Valid row metadata did not restore the grid")
                table = find("Invoice lines")
                far = table.cell(0, 598)
                far_row = table.slice("AXRows", 598, 1)[0]
                amount = table.cell(1, 598)
                ax.wait_for(lambda: far.read("AXValue") == "Line item 0600" and amount.read("AXValue") == "600.25", "Restored grid values did not load")
                settle()
                check(find("Metadata source").press() == 0, "replace the native metadata expression through its normal public command")
                ax.wait_for(lambda: state().get("otherMeta") is True and any(i.get("reason") == "gridUnavailable" for i in state()["diagnostics"].get("issues", [])), "Changed native metadata expression did not reject the old Formula mapping")
                check(far.read("AXSize") in (None, (0.0, 0.0)) and far.set_text("Must not edit") != 0, "a stale metadata mapping cannot authorize input")
                find("Metadata source").press()
                ax.wait_for(lambda: state().get("otherMeta") is False and (t := find("Invoice lines")) is not None and t.read("AXRowCount") == 599, "Restoring the native metadata source did not restore the grid")
                table = find("Invoice lines")
                far = table.cell(0, 598)
                far_row = table.slice("AXRows", 598, 1)[0]
                amount = table.cell(1, 598)
                ax.wait_for(lambda: far.read("AXValue") == "Line item 0600" and amount.read("AXValue") == "600.25", "Restored metadata mapping did not load values")
                settle()
        ticks = state()["timerTicks"]

        selection_hooks = state()["hooks"]
        check(far_row.press() == 0, "select the final row directly from the first viewport")
        ax.wait_for(lambda: state()["selected"] == [source_key("line-0600")], "Direct final-row selection did not update the real binding")
        ax.wait_for(lambda: any(row.read("AXIdentifier") == far_row.read("AXIdentifier") for row in table.read("AXVisibleRows") or []), "Selection must reveal the final row after the selected-items binding settles", timeout=10)
        ax.wait_for(lambda: group.read("AXHelp") == "List box selection confirmed", "Direct selection lacked confirmed completion")
        check(state()["hookSelection"] == [source_key("line-0600")] and state()["hooks"] == selection_hooks + 1, "the shared selection handler reads the settled binding exactly once")
        check(True, "selection confirmation waits for the binding and visible row")
        check(table.set_elements("AXSelectedRows", []) == 0, "clear the selected rows through the existing list box")
        ax.wait_for(lambda: state()["selected"] == [], "Selection did not clear")
        settle()
        initial_hooks = state()["hooks"]
        check("AXScrollToVisible" in far.actions(), "external grid action enumeration includes standard reveal")
        check(far.perform("AXScrollToVisible") == 0, "standard scroll-to-visible action reaches an offscreen cell")
        ax.wait_for(lambda: any(row.read("AXIdentifier") == far_row.read("AXIdentifier") for row in table.read("AXVisibleRows") or []), "4D did not reveal the requested cell", timeout=15)
        settle()
        check(state()["selected"] == [] and state()["hooks"] == initial_hooks, "revealing a value preserves selection and handlers")
        check(not amount.is_settable("AXValue"), "read-only numeric column cannot be edited through accessibility")
        check(far.is_settable("AXValue"), "enterable column advertises the existing cell editor")
        check(far.set_text("Edited far row 😀") == 0, "cell text enters through standard AXValue")
        ax.wait_for(lambda: state().get("edited") == "Edited far row 😀", "Actual 4D cell editor did not receive Unicode text", timeout=20)
        settle()
        check(far.read("AXFocused") is True, "focus identifies the exact edited row and column")
        editor = far.read("AXChildren")[0]
        if args.cancel:
            press_key(process, project, TITLE, editor.read("AXIdentifier"), 53)
            process.wait(timeout=15)
            check(process.returncode == 0, "Escape follows the host's normal dialog cancellation path")
            result = json.loads(closed.read_text(encoding="utf-8-sig"))
            check(result["runId"] == config["runId"] and result["accepted"] is False, "4D reports the owned dialog was cancelled")
            check(result["farValue"] == "Line item 0600", "dialog cancellation discards the in-progress cell edit")
            report["passed"] = True
            return
        ax.wait_for(lambda: editor.read("AXValue") == "Edited far row 😀", "Grid text child did not publish the live editor", timeout=15)
        check(editor.read("AXNumberOfCharacters") == len("Edited far row 😀".encode("utf-16-le")) // 2, "cell editor exposes the correct Unicode text length")
        check(editor.set_range("AXSelectedTextRange", 0, 6) == 0, "standard text selection targets the real cell editor")
        settle()
        report["text_selection"] = {"receipt": group.read("AXHelp"), "selected": editor.read("AXSelectedText"), "range": editor.read("AXSelectedTextRange"), "state": state()}
        ax.wait_for(lambda: editor.read("AXSelectedText") == "Edited", "Cell editor selection did not update", timeout=15)
        settle()
        check(editor.set_string("AXSelectedText", "Guitar 🎸") == 0, "selected cell text can be replaced through the existing editor")
        edited = "Guitar 🎸 far row 😀"
        ax.wait_for(lambda: state().get("edited") == edited and editor.read("AXValue") == edited, "Partial Unicode replacement did not reach the actual cell editor", timeout=20)
        settle()
        check(editor.read("AXSelectedTextRange") == (len("Guitar 🎸".encode("utf-16-le")) // 2, 0), "replacement publishes its real insertion position")
        bar = next(item for item in app.read("AXChildren") or [] if item.read("AXRole") == "AXMenuBar")
        menu = next(item for item in bar.read("AXChildren") or [] if item.read("AXTitle") == "Edit")
        actions = {item.read("AXTitle"): item for child in menu.read("AXChildren") or [] for item in child.read("AXChildren") or []}
        check(actions["Undo"].read("AXEnabled") is True and actions["Undo"].press() == 0, "the existing Undo menu accepts cell-editor changes")
        ax.wait_for(lambda: editor.read("AXValue") != edited, "Undo did not change the cell editor", timeout=15)
        menu.press()
        actions = {item.read("AXTitle"): item for child in menu.read("AXChildren") or [] for item in child.read("AXChildren") or []}
        check(actions["Redo"].read("AXEnabled") is True and actions["Redo"].press() == 0, "the existing Redo menu accepts the undone cell edit")
        ax.wait_for(lambda: editor.read("AXValue") == edited, "Redo did not restore the cell editor", timeout=15)
        check(True, "normal Undo and Redo preserve the editor's Unicode text")
        check(find("Note", "AXTextField").set_boolean("AXFocused", True) == 0, "ordinary field accepts focus after grid editing")
        ax.wait_for(lambda: state().get("farValue") == edited, "Normal editor exit did not commit the row value", timeout=15)
        settle()
        check(state()["changes"] > 0 and state()["edits"] > 0, "existing data-change and after-edit handlers run on commit")
        ax.wait_for(lambda: far.read("AXValue") == edited, "Committed cell value did not refresh", timeout=15)
        check(far.set_text("!should-not-type") == 0, "AX transport accepts a request that application validation may reject")
        ax.wait_for(lambda: state().get("filtered", 0) > 0, "Existing keystroke filter did not run", timeout=15)
        ax.wait_for(lambda: group.read("AXHelp") == "Application changed or rejected the text entry", "Rejected keystroke did not report action failure", timeout=15)
        check(state()["edited"] == edited and state()["farValue"] == edited, "filtered first character stops the remaining text without bypassing validation")
        find("Note", "AXTextField").set_boolean("AXFocused", True)
        ax.wait_for(lambda: state().get("focus") == "Note", "Ordinary focus did not leave rejected grid edit", timeout=15)
        settle()
        check(far_row.press() == 0, "offscreen selection is accepted through standard AXPress")
        ax.wait_for(lambda: state().get("selected") == [source_key("line-0600")], "Real listbox selection did not change", timeout=15)
        settle()
        check(state()["hooks"] > 0, "existing shared selection handler runs")
        check(len(table.read("AXSelectedRows")) == 1, "native selection readback matches 4D")
        for index, text_key in [(3, "CAFE"), (4, "cafe")]:
            key = source_key(text_key)
            cell = table.cell(0, index)
            ax.wait_for(lambda: cell.read("AXValue") != "Loading", "Distinct-key cell did not load", timeout=15)
            check(cell.read("AXEnabled") is True, "enabled key " + str(key) + " keeps its own row state")
            row = table.slice("AXRows", index, 1)[0]
            check(row.press() == 0, "distinct row " + str(key) + " accepts selection")
            ax.wait_for(lambda: state()["selected"] == [key], "Distinct-key selection reached another row", timeout=15)
            settle()
            check(True, "host selection confirms the exact key " + str(key))
        check(find("Sort").press() == 0, "ordinary sort button invokes its existing handler")
        ax.wait_for(lambda: state().get("first") == source_key("line-0600"), "Existing sort handler did not run", timeout=15)
        settle()
        ax.wait_for(lambda: far.read("AXRowIndexRange") == (0, 1), "Far cell identity did not survive real sort", timeout=15)
        check(True, "real 4D sorting preserves the same keyed cell at its new position")
        if config.get("rowStates") and config.get("kind") in ("collection", "entity") and not config.get("storedMeta"):
            expected_meta_key = 600 if config.get("kind") == "entity" else source_key("line-0600")
            ax.wait_for(lambda: state().get("metaFirst", {}).get("key") == expected_meta_key, "Metadata request did not follow the sorted source position")
            check(state().get("metaArgumentsOK") is True and state()["metaFirst"]["row"] == 1, "metadata preserves the original Text or numeric key and receiver after sorting")
        if described is not None:
            ax.wait_for(lambda: described.read("AXRowIndexRange") == (0, 1) and described.read("AXValue") == "Ready: " + edited, "Custom description lost its stable row identity after editing and sorting")
            check(True, "custom description follows the same edited record through real sorting")
        check(state()["timerTicks"] > ticks, "existing form timer continues during paged access and actions")
        check(find("Reject selection").press() == 0, "enable application selection rejection")
        settle()
        ax.wait_for(lambda: state().get("rejectSelection") is True and group.read("AXHelp") == "Activation dispatched through the control's normal event path", "Selection rejection button did not finish its ordinary action")
        selection_hooks = state()["hooks"]
        report["selection_rejection_probe"] = {"state": state(), "rowIdentifier": far_row.read("AXIdentifier"), "rowEnabled": far_row.read("AXEnabled"), "rowSize": far_row.read("AXSize"), "rowActions": far_row.actions()}
        report["selection_rejection_probe"]["pressResult"] = far_row.press()
        check(report["selection_rejection_probe"]["pressResult"] == 0, "the current row accepts the selection-rejection test request")
        ax.wait_for(lambda: group.read("AXHelp") == "Application changed the requested selection", "Changed application selection was falsely confirmed")
        ax.wait_for(lambda: state()["selected"] == [], "The fixture's next timer observation did not reflect the rejected selection")
        check(state()["selected"] == [] and state()["hooks"] == selection_hooks + 1, "selection rejection is confirmed without replaying its handler")
        find("Reject selection").press()
        settle()
        if config.get("kind") == "collection":
            old_identifier = far.read("AXIdentifier")
            check(find("Rebind").press() == 0, "replace collection objects while retaining their keys")
            ax.wait_for(lambda: (replacement := find("Invoice lines")) is not None and replacement.cell(0, 0).read("AXIdentifier") != old_identifier, "Reused keys did not retire replaced object bindings")
            settle()
            check(far.read("AXSize") in (None, (0.0, 0.0)), "a retained cell cannot target a replacement object with the same key")
            table = find("Invoice lines")
            far = table.cell(0, 0)
            ax.wait_for(lambda: far.read("AXValue") == edited, "Replacement object value did not load")
        if config.get("kind") == "entity":
            old_identifier = far.read("AXIdentifier")
            check(find("Rebind").press() == 0, "switch dataclasses with identical primary keys")
            ax.wait_for(lambda: (replacement := find("Invoice lines")) is not None and replacement.cell(0, 0).read("AXIdentifier") != old_identifier, "Dataclass replacement did not retire prior entities")
            settle()
            check(far.read("AXSize") in (None, (0.0, 0.0)), "identical keys in another dataclass cannot reuse an old accessible cell")
            table = find("Invoice lines")
            far = table.cell(0, 0)
            ax.wait_for(lambda: far.read("AXValue") == "Line item 0600", "Replacement dataclass value did not load")
        old_identifier = far.read("AXIdentifier")
        check(find("Scope").press() == 0, "ordinary record-change handler runs")
        def replacement_ready():
            replacement = find("Invoice lines")
            return replacement is not None and replacement.cell(0, 0).read("AXIdentifier") != old_identifier

        ax.wait_for(replacement_ready, "Record change did not retire prior identities", timeout=15)
        check(far.read("AXSize") in (None, (0.0, 0.0)), "retained prior-record cell has no active geometry")
        close = find("Close")
        close.press()
        process.wait(timeout=15)
        check(process.returncode == 0, "normal standard-action close exits the owned 4D host")
        check(json.loads(closed.read_text(encoding="utf-8-sig"))["accepted"] is True, "4D confirms normal acceptance separately from cancellation")
        report["passed"] = True
    finally:
        if process.poll() is None:
            try:
                report["final_state"] = state()
            except AssertionError as error:
                report["final_state_error"] = str(error)
            if "group" in locals() and group is not None:
                report["final_receipt"] = group.read("AXHelp")
            if not report["passed"]:
                report["failure_windows"] = [{"title": item.read("AXTitle"), "role": item.read("AXRole")} for item in ax.application(process.pid).read("AXWindows") or []]
                try:
                    ax.capture_window(process.pid, BUILD / "logical-grid-failure.png")
                except RuntimeError:
                    pass
        destination = "logical-grid-voiceover-report.json" if args.voiceover_probe or args.voiceover else "logical-grid-cancel-report.json" if args.cancel else "logical-grid-runtime-report.json"
        (BUILD / destination).write_text(json.dumps(report, indent=2) + "\n")
        if process.poll() is None:
            if close is not None:
                close.press()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            if process.poll() is None:
                # Exact process launched above, disposable synthetic data only.
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    main()
