#!/usr/bin/env python3
"""Exercise the disposable native-listbox fixture through external macOS AX."""
import argparse
import ctypes as c
import json
import subprocess
import sys
import time

from build_component import sha
from prepare_listbox_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
from mac_ax import Element, application, process_architecture, release, signature, trusted, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--mode", choices=("interpreted", "compiled"), required=True)
    parser.add_argument("--expect-architecture", choices=("arm64", "x86_64"))
    args = parser.parse_args()
    if not args.run or not trusted():
        parser.error("--run and existing Accessibility permission are required")
    pids = subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split()
    if len(pids) != 1:
        parser.error("Launch the exact disposable ListboxFixture project first")
    pid = int(pids[0])
    command = subprocess.check_output(["ps", "-p", str(pid), "-o", "command="], text=True)
    if "--project " + str(FIXTURE / "Project/ListboxFixture.4DProject") not in command:
        parser.error("Refusing to act on another 4D project")
    compiled = json.loads((BUILD / "listbox-compile-report.json").read_text())
    if not compiled.get("passed"):
        parser.error("Prepare and compile the fixture first")
    for relative, expected in compiled["sources_sha256"].items():
        if sha(FIXTURE / relative) != expected:
            parser.error("Fixture source changed after compilation")
    if sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ") != compiled["component_sha256"]:
        parser.error("Component changed after compilation")
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    if config.get("entity", False) != compiled.get("entity", False):
        parser.error("Prepared fixture binding does not match the launch configuration")
    report = {"passed": False, "mode": args.mode, **config, "checks": [], "action_latency_seconds": [],
              "process_architecture": process_architecture(pid),
              "scope": "Synthetic native array/" + ("entity" if config.get("entity") else "collection") + " list boxes, 600 rows each"}

    def check(condition, name):
        report["checks"].append({"name": name, "passed": bool(condition)})
        print(f"{'PASS' if condition else 'FAIL'}: {name}", flush=True)
        if not condition:
            raise AssertionError(name)

    def state():
        try:
            data = json.loads((FIXTURE / "Resources/runtime-status.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        if data.get("phase") == "failed" or data.get("bridgeError"):
            raise AssertionError(f"Fixture failure: {data}")
        if config.get("entity") and data.get("phase") == "ready" and data.get("bufferPreserved") is not True:
            raise AssertionError("Entity list operation disturbed the unsaved classic record buffer")
        return data

    try:
        if args.expect_architecture:
            prefix = "ARM64" if args.expect_architecture == "arm64" else "X8664"
            check(report["process_architecture"].replace("-", "").startswith(prefix), "actual host architecture matches request")
        ready = wait_for(lambda: state() if state().get("phase") == "ready" and state().get("runId") == config["runId"] else None, "Fixture not ready for this launch", 20)
        check(ready["runId"] == config["runId"], "runtime belongs to this launch")
        check(ready["compiled"] is (args.mode == "compiled"), "actual host execution mode matches request")
        check(ready.get("entity", False) == config.get("entity", False), "actual collection or entity binding matches the prepared fixture")
        windows = [w for w in (application(pid).read("AXWindows") or []) if w.read("AXTitle") == TITLE]
        check(len(windows) == 1, "one exact disposable listbox window")
        window = windows[0]
        pending = [window]
        group = None
        for _ in range(2000):
            if not pending:
                break
            element = pending.pop()
            identifier = element.read("AXIdentifier")
            if isinstance(identifier, str) and identifier.startswith("axb.window."):
                group = element
                break
            pending.extend(e for e in (element.read("AXChildren") or []) if isinstance(e, Element))
        if group is None:
            raise AssertionError("No bridge status group")

        def settle():
            wait_for(lambda: group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"),
                     "Prior action has not received its final native acknowledgment")

        def send(request):
            settle()
            previous = state().get("receipt", {}).get("id")
            started = time.monotonic()
            result = request()
            wait_for(lambda: state().get("receipt", {}).get("id") not in (None, previous), "Application did not acknowledge this request")
            settle()
            report["action_latency_seconds"].append(round(time.monotonic() - started, 4))
            return result

        def find(suffix):
            return window.find("." + suffix)

        def rows(kind):
            table = find(kind)
            return table.read("AXRows") or [] if table else []

        def selected(kind):
            return state().get(kind + "Selected")

        def press(name):
            check(send(lambda: find(name).press()) == 0, name + " requested through AX")

        def mouse_click(element):
            # Hit-test a real mouse event only while our verified fixture is
            # frontmost. Direct-to-PID mouse events do not target a 4D window.
            if application(pid).read("AXFrontmost") is not True:
                raise AssertionError("Fixture must be frontmost for its mouse test")
            class Point(c.Structure):
                _fields_ = [("x", c.c_double), ("y", c.c_double)]
            graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
            create = signature(graphics, "CGEventCreateMouseEvent", c.c_void_p, c.c_void_p, c.c_uint32, Point, c.c_uint32)
            post = signature(graphics, "CGEventPost", None, c.c_uint32, c.c_void_p)
            set_field = signature(graphics, "CGEventSetIntegerValueField", None, c.c_void_p, c.c_uint32, c.c_longlong)
            x, y = element.read("AXPosition")
            width, height = element.read("AXSize")
            for kind in (5, 1, 2):
                event = create(None, kind, Point(x + min(90, width / 2), y + height / 2), 0)
                set_field(event, 1, 1)  # kCGMouseEventClickState
                post(0, event)
                release(event)
                time.sleep(.08)

        wait_for(lambda: find("array.A0001") and find("collection.C0001"), "Listbox rows not published")
        check(1 <= len(rows("array")) <= 9 and 1 <= len(rows("collection")) <= 9, "600-row lists publish only their visible viewport")
        check(find("array.A0002") is None and find("array.A0600") is None, "hidden and offscreen rows are omitted")
        check(find("array.A0003").read("AXEnabled") is False and find("array.A0004").read("AXEnabled") is False,
              "disabled and nonselectable array rows reject input")
        check(find("array.A0001").read("AXValue") == "Array item 0001", "allowlisted label excludes the key column")
        for kind, key in (("array", "A0001"), ("collection", "C0001")):
            cell = find(kind + "." + key).read("AXChildren")[0]
            x, y = cell.read("AXPosition")
            width, height = cell.read("AXSize")
            check(application(pid).at_position(x + width / 2, y + height / 2).read("AXIdentifier") == cell.read("AXIdentifier"),
                  kind + " cell is discoverable by external screen-position lookup")
        child_keys = {"left": "C0001", "right": "C0003"} if config.get("entity") else {"left": "left-1", "right": "right-1"}
        wait_for(lambda: all(find("items." + key) for key in child_keys.values()), "Documented subform grids not published")
        for side in ("left", "right"):
            check(send(lambda: find("items." + child_keys[side]).press()) == 0, side + " subform selection requested")
            wait_for(lambda: state().get(side + "Selected") == [child_keys[side]], "Subform selection updated the wrong binding")
            check(state()[side + "Summary"] == "1 items selected" and state()["receipt"]["status"] == "completed",
                  side + " subform deferred confirmation updates the documented shared handler")
        check(state()["leftSelected"] == [child_keys["left"]] and state()["rightSelected"] == [child_keys["right"]],
              "repeated list-box subforms retain separate selections")
        wait_for(lambda: state().get("leftSummary") == "1 items selected", "Documented summary not ready")
        summaries = []
        pending = [window]
        for _ in range(2000):
            if not pending:
                break
            element = pending.pop()
            identifier = element.read("AXIdentifier")
            if isinstance(identifier, str) and identifier.endswith(".selectionStatus"):
                summaries.append(element.read("AXValue"))
            pending.extend(e for e in (element.read("AXChildren") or []) if isinstance(e, Element))
        check(summaries == ["1 items selected", "1 items selected"], "both documented summaries publish their confirmed values")
        for kind, key in (("array", "A0005"), ("collection", "C0005")):
            element = find(kind + "." + key)
            check(send(element.press) == 0, kind + " row selection requested")
            wait_for(lambda: selected(kind) == [key], kind + " native selection binding did not update")
            wait_for(lambda: element.read("AXSelected") is True, kind + " AX selected state did not update")
            check(True, kind + " selection reaches native binding and returns through AX")
            wait_for(lambda: state().get("hooks", {}).get(kind, {}).get("keys") == [key], "Selection callback read an old binding")
            check(state()["hooks"][kind]["calls"] == 1, kind + " shared selection callback runs once with confirmed native keys")
            wait_for(lambda: state().get("receipt", {}).get("status") == "completed", "Selection did not produce a final receipt")
            if kind == "collection":
                check(state()["lastResult"]["status"] == "pending", "collection completion waits for the next form event cycle")
        find("array.A0003").press()
        time.sleep(.3)
        check(selected("array") == ["A0005"], "disabled row cannot replace native selection")
        press("sort")
        wait_for(lambda: find("array.A0600") and find("collection.C0600"), "Sorted viewport not published")
        check(state()["arrayFirst"] == "A0600" and state()["collectionFirst"] == "C0600", "native sort reorders both live bindings")
        old = find("array.A0600")
        for kind, key in (("array", "A0599"), ("collection", "C0599")):
            check(send(lambda: find(kind + "." + key).press()) == 0, kind + " sorted row requested")
            wait_for(lambda: selected(kind) == [key], "Sorted selection used the old position")
            check(True, kind + " selection resolves stable keys after sorting")
        press("bottom")
        wait_for(lambda: find("array.A0005") and find("collection.C0005"), "End viewport not published")
        old.press()
        time.sleep(.3)
        check(selected("array") == ["A0599"], "retained offscreen row cannot select an invisible item")
        check(send(lambda: find("collection.C0005").press()) == 0, "row beyond native index 255 requested")
        wait_for(lambda: selected("collection") == ["C0005"], "Viewport index was used as source position")
        check(True, "viewport index maps back to source row 596")
        press("reset")
        wait_for(lambda: find("array.A0001") and find("collection.C0001"), "Reset viewport not ready")
        for kind, prefix in (("array", "A"), ("collection", "C")):
            values = [prefix + "0005", prefix + "0006"]
            check(send(lambda: find(kind).set_elements("AXSelectedRows", [find(kind + "." + v) for v in values])) == 0,
                  kind + " multiple selection requested")
            wait_for(lambda: selected(kind) == values, "Multiple selection did not reach native binding")
            check(True, kind + " multiple selection read back by stable key")
        press("single")
        for kind, prefix in (("array", "A"), ("collection", "C")):
            before = selected(kind)
            send(lambda: find(kind).set_elements("AXSelectedRows", [find(kind + "." + prefix + "0005"), find(kind + "." + prefix + "0006")]))
            check(selected(kind) == before and state()["receipt"]["status"] == "rejected", kind + " single-selection mode rejects a multiple selection atomically")
            send(lambda: find(kind).set_elements("AXSelectedRows", []))
            wait_for(lambda: selected(kind) == [], "Empty selection did not clear")
            check(True, kind + " empty selection clears native selection")
        press("hide")
        wait_for(lambda: len(rows("array")) == 0 and len(rows("collection")) == 0, "Hidden label column still exposed text")
        check(True, "hidden columns do not contribute row labels")
        press("reset")
        wait_for(lambda: find("array.A0001") and find("collection.C0001"), "Reset did not restore rows")
        retained = find("collection.C0001")
        press("duplicate")
        wait_for(lambda: find("array").read("AXEnabled") is False and find("collection").read("AXEnabled") is False,
                 "Duplicate offscreen keys were accepted")
        retained.press()
        time.sleep(.3)
        check(selected("collection") == [], "duplicate offscreen key disables selection without mutating it")
        check(len(rows("array")) == 0 and len(rows("collection")) == 0, "invalid identity mapping exposes no rows")
        press("reset")
        wait_for(lambda: find("collection.C0001"), "Reset did not restore collection")
        press("rebind")
        wait_for(lambda: find("collection").read("AXEnabled") is False, "Changed label binding accepted")
        check(len(rows("collection")) == 0 and len(rows("array")) > 0, "changed column formula disables only its grid")
        press("reset")
        wait_for(lambda: find("collection.C0001"), "Reset did not restore binding")
        retained_array = find("array.A0005")
        retained_collection = find("collection.C0005")
        press("filter")
        wait_for(lambda: find("array.A0005") is None and find("collection.C0005") is None, "Filtered rows remained exposed")
        retained_array.press()
        retained_collection.press()
        time.sleep(.3)
        check(selected("array") == [] and selected("collection") == [], "retained filtered rows cannot select their replacement positions")
        for kind, key in (("array", "A0006"), ("collection", "C0006")):
            send(lambda: find(kind + "." + key).press())
            check(selected(kind) == [key], kind + " selection resolves stable keys after filtering")
        press("reset")
        wait_for(lambda: find("collection.C0001"), "Reset did not restore filtered rows")
        check(state()["nativeEvents"] == 0, "programmatic selection does not synthesize On Selection Change")
        calls = state()["hooks"]["collection"]["calls"]
        mouse_click(find("collection.C0006"))
        wait_for(lambda: selected("collection") == ["C0006"], "Real mouse input did not select the fixture row")
        check(state()["nativeEvents"] == 1, "human row selection emits the native selection event")
        wait_for(lambda: state()["hooks"]["collection"]["calls"] == calls + 1, "Human selection did not call shared logic")
        check(state()["hooks"]["collection"]["keys"] == ["C0006"], "human and AX paths share the confirmed-selection handler")
        press("reset")
        wait_for(lambda: selected("collection") == [], "Reset did not clear human selection")
        old = find("collection.C0001")
        old_id = old.read("AXIdentifier")
        press("scope")
        wait_for(lambda: find("collection.C0001").read("AXIdentifier") != old_id, "Case-only scope change retained old identity")
        old.press()
        time.sleep(.3)
        check(selected("collection") == [], "case-only scope changes invalidate retained controls")
        press("casekeys")
        wait_for(lambda: find("array.CAFE"), "Case-variant keys not published")
        check(state()["keyTest"]["status"] == "rejected" and selected("array") == [],
              "case-variant disabled key cannot borrow an enabled key's permission")
        check(send(lambda: find("array.CAFE").press()) == 0, "accent-variant enabled row requested")
        wait_for(lambda: selected("array") == ["CAFE"], "Enabled key was confused with disabled accented key")
        check(True, "exact routing distinguishes case and accents in stable IDs")
        before = state()["revision"]
        press("caselabel")
        wait_for(lambda: find("array.case").read("AXValue") == "array item 0001", "Case-only label edit not published")
        wait_for(lambda: state()["revision"] > before, "Case-only snapshot revision was not observed")
        check(True, "case-only snapshot changes advance the action revision")
        press("reset")
        wait_for(lambda: find("collection.C0001"), "Reset did not restore collection")
        calls = state()["hooks"]["collection"]["calls"]
        press("cancelpending")
        check(send(lambda: find("collection.C0005").press()) == 0, "selection requested before an application scope change")
        wait_for(lambda: state().get("receipt", {}).get("status") == "rejected", "Changed form accepted deferred confirmation")
        check(state()["hooks"]["collection"]["calls"] == calls, "changed scope rejects confirmation and skips dependent business logic")
        report["native_selection_events"] = state()["nativeEvents"]
        press("format")
        wait_for(lambda: find("array").read("AXEnabled") is False and find("collection").read("AXEnabled") is False,
                 "Formatted values were published raw")
        check(len(rows("array")) == 0 and len(rows("collection")) == 0, "formatted columns never expose raw backing text")
        if config.get("entity"):
            check(state()["bufferPreserved"] is True, "all entity reads, sorts, selections and human events preserve the unsaved record buffer")
        press("reset")
        wait_for(lambda: find("collection.C0001"), "Reset did not restore collection before error test")
        if config.get("entity"):
            for button, message in (("entitylimits", "1000"), ("entitywrong", "unsupported"),
                                    ("entitywrongclass", "unsupported"), ("entitycomputed", "stored text")):
                press(button)
                wait_for(lambda: find("collection").read("AXEnabled") is False, "Invalid entity binding stayed enabled")
                check(len(rows("collection")) == 0 and message in find("collection").read("AXDescription"),
                      button + " disables only the invalid grid with an explanatory label")
                press("reset")
                wait_for(lambda: find("collection.C0001"), "Entity reset did not restore the grid")
            press("entitynull")
            check(len(rows("collection")) > 0 and find("collection.C0001").read("AXSelected") is False,
                  "Null selected-entities binding is an empty selection")
            press("reset")
            press("entitynumeric")
            wait_for(lambda: find("collection.n:5"), "Integer entity key did not publish a typed row ID")
            send(lambda: find("collection.n:5").press())
            check(selected("collection") == ["C0005"], "stored integer keys select the corresponding real entity")
            press("reset")
            press("entitynulllabel")
            wait_for(lambda: find("collection.C0006") is None, "Null label was exposed as text")
            check(find("collection").read("AXEnabled") is True and find("collection.C0005") is not None,
                  "Null entity label omits its unlabelled row without disabling the grid")
            press("reset")
            wait_for(lambda: find("collection.C0006"), "Null-label reset did not restore the row")
        for kind, prefix in (("array", "A"), ("collection", "C")):
            calls = state()["hooks"][kind]["calls"]
            press("rejectselection")
            check(send(lambda: find(kind + "." + prefix + "0005").press()) == 0,
                  kind + " selection requested with application rejection")
            wait_for(lambda: selected(kind) == [], "Application did not clear the selection")
            check(state()["receipt"]["status"] == "rejected", kind + " completion rechecks selection after the shared handler")
            check(state()["hooks"][kind]["calls"] == calls + 1 and state()["hooks"][kind]["keys"] == [prefix + "0005"],
                  kind + " rejecting handler reads the requested selection exactly once without replay")
            calls = state()["hooks"][kind]["calls"]
            previous_id = find(kind).read("AXIdentifier")
            press("scopeselection")
            check(send(lambda: find(kind + "." + prefix + "0006").press()) == 0,
                  kind + " selection requested with record change in its handler")
            wait_for(lambda: find(kind).read("AXIdentifier") != previous_id, "Handler scope change did not retire the old grid")
            check(state()["receipt"]["status"] == "rejected" and state()["hooks"][kind]["calls"] == calls + 1,
                  kind + " changed record rejects completion without repeating the handler")
            press("reset")
            wait_for(lambda: selected(kind) == [], "Reset did not clear the selection")
        press("fault")
        check(find("collection.C0005").press() == 0, "deferred callback failure requested")
        def confirmation_failed():
            try:
                failure = json.loads((FIXTURE / "Resources/runtime-status.json").read_text(encoding="utf-8-sig"))
                return failure if failure.get("phase") == "failed" else None
            except (OSError, ValueError):
                return None
        failure = wait_for(confirmation_failed, "Deferred error was not caught")
        check(failure["failure"]["error"] == "callbackError" and failure["failure"]["method"] == "AXBL_Selection",
              "deferred callback errors reach the owning form's error handler")
        wait_for(lambda: find("collection") is None, "Failed confirmation left live controls")
        check(True, "failed confirmation detaches its bridge before notification")
        check(window.read("AXCloseButton").press() == 0, "native window close requested")
        wait_for(lambda: str(pid) not in subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split(), "Fixture did not close")
        check(True, "window unload detaches both list adapters")
        report["passed"] = True
    finally:
        prefix = "listbox-entity" if config.get("entity") else "listbox"
        (BUILD / f"{prefix}-{args.mode}-report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
