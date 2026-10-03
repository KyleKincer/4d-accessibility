#!/usr/bin/env python3
"""Exercise explicit grouped disclosure through live 4D and external AX."""
import argparse
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import uuid

from build_component import BUILD, ROOT, sha
from prepare_hierarchy_probe import canonical_sources
from summarize_grouped_outlines import validate_prepared
from test_hierarchy_probe import finish_run, read_json

TITLE = "AX native hierarchy probe"
SOURCES = ("test_grouped_disclosure.py", "build_component.py", "prepare_hierarchy_probe.py", "summarize_grouped_outlines.py",
           "test_hierarchy_probe.py", "test_grouped_outline.py", "test_grid_value_speech.py", "test_outline_value_speech.py",
           "tests/mac_ax.py", "tests/fixture_desktop.py", "tests/voiceover.py", "tests/ReadScreen.swift")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    parser.add_argument("--voiceover-only", action="store_true", help="Run the spoken gate alone; does not accept the full action matrix")
    args = parser.parse_args()
    if args.voiceover_only and not args.voiceover:
        parser.error("VoiceOver-only requires --voiceover")
    mode = "compiled" if args.compiled else "interpreted"
    path = BUILD / ("grouped-disclosure-" + mode + ("-voiceover-only" if args.voiceover_only else "-voiceover" if args.voiceover else "") + ".json")
    report = {"passed": False, "checks": [], "commands": [], "actions": [], "pixels": [], "compiled": args.compiled,
              "actionGate": not args.voiceover_only, "environment": {"macOS": platform.mac_ver()[0], "hostArchitecture": platform.machine()}}
    path.write_text(json.dumps(report) + "\n")
    sources = {name: sha(ROOT / name) for name in SOURCES}
    prepared_path, prepared = validate_prepared(ROOT)
    assert prepared["disclosure"] is True
    report.update({"driverSourceSHA256": sources, "compileReportSHA256": sha(prepared_path), "preparedSourceSHA256": prepared["sources_sha256"],
                   "canonicalSourceSHA256": prepared["canonicalSourceSHA256"], "nativeSourceSHA256": prepared["nativeSourceSHA256"],
                   "componentSourceSHA256": prepared["componentSourceSHA256"], "nativeSHA256": prepared["nativeSHA256"],
                   "componentPackageSHA256": prepared["componentPackageSHA256"], "compiledHostSHA256": prepared["compiledHostSHA256"]})
    sys.path.insert(0, str(ROOT / "tests"))
    import mac_ax as ax
    from fixture_desktop import activate_fixture, capture_fixture_window, press_key, wait_for_start
    from PIL import Image, ImageChops
    ax.require_test_input()
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    fixture = BUILD / "hierarchy-probe"
    project, resources = fixture / "Project/Hierarchy.4DProject", fixture / "Resources"
    run_id = (resources / "run-id.txt").read_text()
    (resources / "launch-variant.txt").write_text("standalone")
    (resources / "read-only.txt").unlink(missing_ok=True)
    report["runId"] = run_id
    for name in ("state.json", "close.json", "closed.json", "error.json", "request.json"):
        (resources / name).unlink(missing_ok=True)

    def state():
        assert not (resources / "error.json").exists(), read_json(resources / "error.json")
        value = read_json(resources / "state.json")
        return value if value and value.get("runId") == run_id else None

    def check(condition, message):
        assert condition, message
        report["checks"].append(message)
        print("PASS:", message, flush=True)

    process, vo, finished = None, None, False
    with (BUILD / ("grouped-disclosure-" + mode + ".log")).open("w") as log:
        try:
            process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless",
                                        "--opening-mode", mode, "--webadmin-auto-start", "false"], stdout=log, stderr=log)
            report["pid"] = process.pid
            ready, report["modeNoticeAcknowledged"] = wait_for_start(process, project, state, BUILD)
            check(ready["compiled"] is args.compiled, "actual desktop mode matches the requested disclosure run")
            app, window = activate_fixture(process, project, TITLE)
            report["window"] = {"title": window.read("AXTitle"), "position": window.read("AXPosition"), "size": window.read("AXSize")}

            def find(predicate):
                pending = [window]
                while pending:
                    item = pending.pop()
                    if predicate(item):
                        return item
                    if item.read("AXRole") not in ("AXOutline", "AXTable"):
                        pending.extend(item.read("AXChildren") or [])

            def table():
                return find(lambda e: e.read("AXRole") == "AXOutline" and e.read("AXDescription") == "Grouped items")

            def root():
                return find(lambda e: e.read("AXRole") == "AXGroup" and str(e.read("AXIdentifier") or "").startswith("axb/"))

            def rows():
                current = ax.wait_for(table, "Current outline unavailable")
                return [row for start in range(0, current.count("AXRows"), 16)
                        for row in current.slice("AXRows", start, min(16, current.count("AXRows") - start))]

            def groups(level=0, label=None):
                current = table()
                return [row for i, row in enumerate(rows()) if row.read("AXDisclosureLevel") == level and row.is_settable("AXDisclosing")
                        and (label is None or current.cell(0, i).read("AXValue") == label)]

            def command(operation, **payload):
                identifier = uuid.uuid4().hex
                temporary = resources / "request.tmp"
                temporary.write_text(json.dumps({"id": identifier, "operation": operation, **payload}))
                temporary.replace(resources / "request.json")
                value = ax.wait_for(lambda: s if (s := state()) and s["command"]["id"] == identifier else None, "Fixture command did not finish")
                time.sleep(.2)
                value = state()
                assert value["command"]["id"] == identifier and not value["command"].get("error")
                report["commands"].append({"operation": operation, "payload": payload, "state": value})
                return value

            def settle():
                time.sleep(.15)
                receipt = ax.wait_for(lambda: help if (r := root()) and (help := r.read("AXHelp"))
                                   and help not in ("Action queued", "Waiting for the application to complete the action") else None,
                                   "Disclosure completion receipt did not arrive", timeout=15)
                serial = state()["sampleSerial"]
                ax.wait_for(lambda: state()["sampleSerial"] > serial, "Independent state did not refresh after the completion receipt")
                return receipt

            def disclose(row, expanded, calls=1, message="Group disclosure confirmed", press=False, content=None):
                before = state()
                index = int(row.read("AXIndex"))
                assert index >= 0 and row.is_settable("AXDisclosing")
                key = before["outline"]["rows"][index]
                position = before["outline"]["positions"][key]
                level = row.read("AXDisclosureLevel") + 1
                check((content.press() if content else row.press() if press else row.set_boolean("AXDisclosing", expanded)) == 0, "external AX accepts the scoped disclosure request")
                receipt = settle()
                after = state()
                new_calls = after["disclosureCalls"][len(before["disclosureCalls"]):]
                report["actions"].append({"rowIdentifier": row.read("AXIdentifier"), "rowKey": key, "backingRow": position,
                                           "breakLevel": level, "expanded": expanded, "press": press,
                                           "disclosureChildPress": content is not None, "receipt": receipt, "before": before, "after": after, "calls": new_calls})
                check(len(new_calls) == calls, "disclosure invokes the application controller exactly as required")
                if new_calls:
                    call = new_calls[0]
                    check(set(call) == {"objectName", "backingRow", "breakLevel", "expanded", "actionID"}
                          and call["objectName"] == "Grouped" and call["backingRow"] == position and call["breakLevel"] == level
                          and call["expanded"] is expanded and call["actionID"], "controller receives only independently resolved native coordinates and intent")
                check(receipt == message if message else receipt != "Group disclosure confirmed", "receipt confirms application state or reports the requested rejection")
                return before, after, position, level

            def image(label):
                destination = BUILD / ("disclosure-" + mode + "-" + label + "-" + uuid.uuid4().hex + ".png")
                captured = capture_fixture_window(process, window, destination)
                return {"path": destination.name, "sha256": sha(destination), "capturedWindow": captured}

            if not args.voiceover_only:
                for case, count in (("singleText", 12), ("singleDate", 12), ("repeated", 17)):
                    command("groupCase", name=case)
                    ax.wait_for(lambda: (t := table()) and t.count("AXRows") == count, "Initial group population unavailable")
                    current, first = table(), groups()[0]
                    content = current.cell(0, int(first.read("AXIndex"))).read("AXChildren")[0]
                    check("AXPress" in first.actions() and "AXPress" in content.actions() and not content.is_settable("AXValue"),
                      case + " permits group activation through its disclosure child without editing")
                    before, after, position, level = disclose(first, False, content=content)
                    check(first.read("AXDisclosing") is False and before["focus"] == after["focus"],
                      case + " disclosure-child activation confirms collapse without transferring focus")
                    integrated = image(case + "-integrated")
                    command("groupExpandAll")
                    command("groupScroll", vertical=before["beforeGroup"]["scroll"][0], horizontal=before["beforeGroup"]["scroll"][1])
                    native_before = state()
                    check(native_before["beforeGroup"]["scroll"] == before["beforeGroup"]["scroll"], case + " ordinary command starts at the identical scroll position")
                    command("groupTargetDisclosure", row=position, level=level, expanded=False)
                    check(state()["beforeGroup"]["scroll"] == after["beforeGroup"]["scroll"], case + " accessibility disclosure retains the native command's scroll adjustment")
                    baseline = image(case + "native")
                    images = [Image.open(BUILD / item["path"]).convert("RGBA") for item in (baseline, integrated)]
                    assert images[0].size == images[1].size
                    diff = ImageChops.difference(*images)
                    changed = sum(n for n, color in diff.getcolors(diff.width * diff.height) if color != (0, 0, 0, 0))
                    check(changed == 0, case + " accessibility collapse matches every pixel of the original targeted native command")
                    report["pixels"].append({"case": case, "baseline": baseline, "integrated": integrated, "changedPixels": changed, "wholeWindow": True, "mask": False, "tolerance": 0})
                    check(after["events"][len(before["events"]):] == state()["events"][len(native_before["events"]):],
                          case + " retains the native command's original event behavior")
                    disclose(groups()[0], True)
                    disclose(groups()[0], True, calls=0, message="Group already has the requested disclosure state")

                command("groupCase", name="repeated")
                command("focusGrouped")
                check(state()["focus"] == "Grouped" and not state()["editing"], "grouped listbox owns keyboard focus without a text editor")
                disclose(groups()[0], False)
                check(state()["focus"] == "Grouped" and not state()["editing"], "disclosure preserves nonediting grouped keyboard focus")
                close = find(lambda e: e.read("AXRole") == "AXButton" and e.read("AXDescription") == "Close probe")
                check(close.set_boolean("AXFocused", True) == 0, "ordinary Close focus ends the grouped-focus case")
                ax.wait_for(lambda: state()["focus"] == "Close", "Close did not receive focus")
                command("groupCase", name="longRepeated")
                ax.wait_for(lambda: (t := table()) and t.count("AXRows") == 75, "Distant repeated groups did not reset after focused disclosure")
                later = groups(label="A")[-1]
                ax.wait_for(lambda: later.read("AXIdentifier") not in {r.read("AXIdentifier") for r in table().read("AXVisibleRows") or []},
                            "Later repeated-caption target did not become offscreen")
                check(True, "later repeated-caption target begins offscreen")
                disclose(later, False, press=True)
                check(groups(label="A")[0].read("AXDisclosing") is True and groups(label="B")[0].read("AXDisclosing") is True,
                      "offscreen disclosure leaves sampled unrelated roots expanded")
                command("groupCase", name="repeated")
                nested = groups(level=1, label="shared")[0]
                retained_leaf = rows()[2]
                retained_cell = table().cell(2, 2)
                disclose(nested, False)
                check(retained_leaf.read("AXRole") is None and retained_cell.read("AXRole") is None, "nested collapse retires disclosed leaf references")
                disclose(nested, True)
                check(not rows()[2].same_as(retained_leaf), "nested reopening publishes fresh leaf references")
                command("groupCollapseNested")
                first = groups()[0]
                disclose(first, False)
                disclose(first, True)
                check(groups(level=1, label="shared")[0].read("AXDisclosing") is False and groups(level=1, label="other")[0].read("AXDisclosing") is True,
                      "nonrecursive root disclosure preserves opposite latent child states")

                command("groupCase", name="repeated")
                command("groupSelectFirstLeaves")
                _, after, _, _ = disclose(groups()[0], False)
                check(after["beforeGroup"]["selection"] == [False] * 8, "native collapse retains its ordinary hidden-descendant deselection")
                command("groupCase", name="repeated")
                note = ax.wait_for(lambda: find(lambda e: e.read("AXRole") == "AXTextField" and e.read("AXDescription") == "Note"), "Unrelated editor unavailable")
                check(note.set_boolean("AXFocused", True) == 0, "unrelated editor accepts its ordinary AX focus")
                settle()
                ax.wait_for(lambda: state()["focus"] == "Note" and state()["editing"], "Unrelated native editor not active")
                original_note = state()["note"]
                pending_note = "Pending α guitar 🎸 value"
                check(note.set_text(pending_note) == 0, "unrelated editor accepts pending Unicode text through its ordinary input path")
                settle()
                ax.wait_for(lambda: state().get("editedText") == pending_note, "Pending note text did not reach the real editor")
                check(note.set_range("AXSelectedTextRange", 8, 3) == 0, "unrelated pending editor accepts a nontrivial text selection")
                settle()
                ax.wait_for(lambda: note.read("AXSelectedTextRange") == (8, 3), "Pending editor selection did not arrive")
                before, after, _, _ = disclose(groups()[0], False)
                check(after["focus"] == before["focus"] and after["editedText"] == before["editedText"] and after["note"] == before["note"]
                      and after["highlight"] == before["highlight"] and after["events"] == before["events"]
                      and after["note"] == original_note and after["editedText"] != after["note"], "disclosure preserves pending native text, highlight, uncommitted value and handlers")
                press_key(process, project, TITLE, note.read("AXIdentifier"), 6, 1 << 20)
                ax.wait_for(lambda: state().get("editedText") == original_note, "Ordinary Undo did not restore the note after disclosure")
                check(state()["focus"] == "Note" and state()["editing"], "ordinary Undo remains available in the preserved native editor")
                check(close.set_boolean("AXFocused", True) == 0, "ordinary focus ends the unrelated editor case")
                settle()
                command("groupCase", name="repeated")
                command("groupEditLeaf")
                ax.wait_for(lambda: state()["editing"], "Native listbox editor did not open")
                before = state()
                check(groups()[0].set_boolean("AXDisclosing", False) == 0, "active-editor disclosure reaches the application guard")
                receipt = settle()
                after = state()
                report["nativeEditorRejection"] = {"before": before, "after": after, "receipt": receipt}
                check(len(after["disclosureCalls"]) == len(before["disclosureCalls"]) and after["editedText"] == before["editedText"]
                      and receipt != "Group disclosure confirmed", "native grid editing rejects disclosure without committing or invoking the controller")

                check(close.set_boolean("AXFocused", True) == 0, "ordinary focus ends the native grid editor case")
                settle()
                for fault in ("ignore", "membership", "caption", "reparent", "scope", "loading", "replace", "remove"):
                    command("groupCase", name="repeated")
                    command("groupControllerRestore")
                    command("groupControllerMode", mode=fault)
                    before, after, _, _ = disclose(groups(level=1, label="shared")[0] if fault == "reparent" else groups()[0], False, message=None)
                    if fault in ("loading", "replace", "remove"):
                        check(after["runtimeGeneration"] != before["runtimeGeneration"], fault + " changes the actual published provider generation")
                    if fault == "remove":
                        check(after["runtimeDisclosure"] is False, "controller removal actually withdraws current disclosure authority")
                    calls = len(state()["disclosureCalls"])
                    time.sleep(.3)
                    check(len(state()["disclosureCalls"]) == calls, fault + " rejection never replays the controller")
                command("groupControllerMode", mode="normal")
                command("groupControllerRestore")
                command("groupCase", name="repeated")
                retained = groups()[0]
                command("groupReady", ready=False)
                ax.wait_for(lambda: table() is None, "Loading grid did not retire outline")
                command("groupReady", ready=True)
                ax.wait_for(table, "Outline did not recover from loading")
                check(retained.read("AXRole") is None and not groups()[0].same_as(retained), "loading and recovery retire old disclosure handles")
            else:
                command("groupCase", name="repeated")
            if args.voiceover:
                from voiceover import VoiceOver
                ocr = BUILD / "ReadScreen"
                subprocess.run(["xcrun", "swiftc", str(ROOT / "tests/ReadScreen.swift"), "-o", str(ocr)], check=True)
                vo = VoiceOver(process, project, TITLE, BUILD / ("disclosure-" + mode + "-captions"), ocr)
                report["voiceover"] = vo.steps
                vo.start()
                caption = vo.key("home")
                for _ in range(8):
                    if "Grouped items" in caption:
                        break
                    caption = vo.key("right")
                check("Grouped items" in caption, "VoiceOver reaches the actual grouped outline")
                caption = vo.key("down", shift=True)
                caption = vo.key("home")
                check("A expanded disclosure triangle" in caption and "row 1 of" in caption, "VoiceOver Home reaches the first expanded root group")
                report["groupActivationCaption"] = caption
                caption = vo.key("down", shift=True)
                report["groupActivationTarget"] = "disclosure"
                report["disclosureActivationCaption"] = caption
                check("a" in caption.lower() and "disclosure" in caption.lower(), "VoiceOver interacts with the standard disclosure control")
                disclosure = table().cell(0, 0).read("AXChildren")[0]
                check(disclosure.read("AXRole") == "AXDisclosureTriangle" and disclosure.read("AXValue") is True,
                      "VoiceOver activation target starts with the current expanded Boolean")
                before = state()
                caption = vo.key("space")
                receipt = settle()
                after = state()
                report["voiceoverCollapse"] = {"before": before, "after": after, "receipt": receipt, "caption": caption,
                    "rowKey": before["outline"]["rows"][0], "expanded": False,
                    "calls": after["disclosureCalls"][len(before["disclosureCalls"]):]}
                check(len(after["disclosureCalls"]) == len(before["disclosureCalls"]) + 1 and groups()[0].read("AXDisclosing") is False
                      and receipt == "Group disclosure confirmed", "VoiceOver activation collapses exactly one root through the application controller")
                check(disclosure.same_as(table().cell(0, 0).read("AXChildren")[0]) and disclosure.read("AXValue") is False,
                      "the retained VoiceOver disclosure target has the confirmed collapsed Boolean")
                def observe_disclosure(initial, expanded):
                    expected = "expanded" if expanded else "collapsed"
                    pattern = re.compile(r"\bA:\s*" + expected + r"\b", re.IGNORECASE)
                    # The announcement may arrive during key() and be replaced
                    # by VoiceOver's ordinary control hint before settle().
                    return initial if pattern.search(initial) else ax.wait_for(
                        lambda: value if pattern.search(value := vo.read_caption()) else None,
                        "VoiceOver did not speak the " + expected + " state without navigation", timeout=10)

                caption = observe_disclosure(caption, False)
                report["voiceoverCollapse"]["caption"] = caption
                report["collapsedCaption"] = caption
                check("A" in caption and "collapsed" in caption.lower(), "VoiceOver announces the collapsed group without cursor movement")
                before = state()
                caption = vo.key("space")
                receipt = settle()
                after = state()
                report["voiceoverExpand"] = {"before": before, "after": after, "receipt": receipt, "caption": caption,
                    "rowKey": before["outline"]["rows"][0], "expanded": True,
                    "calls": after["disclosureCalls"][len(before["disclosureCalls"]):]}
                check(len(after["disclosureCalls"]) == len(before["disclosureCalls"]) + 1 and groups()[0].read("AXDisclosing") is True
                      and receipt == "Group disclosure confirmed", "VoiceOver reactivation expands exactly one root without replay")
                check(disclosure.read("AXValue") is True, "the retained VoiceOver disclosure target has the confirmed expanded Boolean")
                caption = observe_disclosure(caption, True)
                report["voiceoverExpand"]["caption"] = caption
                report["expandedCaption"] = caption
                report["disclosureNavigationIndex"] = len(vo.steps)
                caption = vo.key("up", shift=True)
                report["disclosureExitCaption"] = caption
                caption = vo.key("right")
                check("shared" in caption and "level 1" in caption, "VoiceOver retains the group position and navigates into its disclosed child")
                caption = vo.key("home")
                check("A expanded disclosure triangle" in caption and "row 1 of" in caption,
                      "VoiceOver returns to the first root row for ordinary row activation")
                report["voiceoverRowActions"] = []
                for expanded in (False, True):
                    before = state()
                    caption = vo.key("space")
                    receipt = settle()
                    after = state()
                    check(len(after["disclosureCalls"]) == len(before["disclosureCalls"]) + 1
                          and groups()[0].read("AXDisclosing") is expanded and receipt == "Group disclosure confirmed",
                          "VoiceOver row activation invokes one controller and confirms " + ("expansion" if expanded else "collapse"))
                    caption = observe_disclosure(caption, expanded)
                    report["voiceoverRowActions"].append({"expanded": expanded, "before": before, "after": after,
                        "receipt": receipt, "caption": caption, "rowKey": before["outline"]["rows"][0],
                        "calls": after["disclosureCalls"][len(before["disclosureCalls"]):]})
                report["rowNavigationIndex"] = len(vo.steps)
                caption = vo.key("right")
                check("shared" in caption and "level 1" in caption,
                      "VoiceOver row activation preserves the cursor at the same root group")
                vo.stop()
            check(sources == {name: sha(ROOT / name) for name in SOURCES} and prepared["canonicalSourceSHA256"] == canonical_sources(),
                  "canonical methods and all imported driver sources remain unchanged during the live gate")
            report["finalState"] = state()
            finished = True
        except BaseException as error:
            report["error"] = str(error)
            raise
        finally:
            if vo and vo.owned:
                try:
                    vo.stop()
                except BaseException as error:
                    report["voiceoverCleanupFailure"] = repr(error)
                    finished = False
            if process is not None:
                finish_run(process, resources, run_id, report, path, finished)
            else:
                path.write_text(json.dumps(report, indent=2) + "\n")
    assert report["passed"]


if __name__ == "__main__":
    main()
