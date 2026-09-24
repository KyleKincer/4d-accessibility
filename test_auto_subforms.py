#!/usr/bin/env python3
"""External AX coverage of automatically discovered child-form lifetimes."""
import argparse
import json
import subprocess
import sys
import time

from build_component import sha
from prepare_auto_subforms import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
from mac_ax import application, process_architecture, trusted, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--launch", action="store_true", help="Launch and close only this disposable fixture")
    parser.add_argument("--compiled", action="store_true", help="With --launch, require compiled desktop execution")
    args = parser.parse_args()
    if not args.run or not trusted():
        parser.error("--run and Accessibility permission are required")
    pids = subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split()
    if args.compiled and not args.launch:
        parser.error("--compiled requires --launch")
    if args.launch:
        if pids:
            parser.error("Close 4D before launching the owned fixture")
        from fixture_desktop import activate_fixture, wait_for_start
        project = FIXTURE / "Project/AutoSubforms.4DProject"
        status = FIXTURE / "Resources/runtime-status.json"
        status.unlink(missing_ok=True)
        def launch_state():
            try:
                return json.loads(status.read_text(encoding="utf-8-sig"))
            except (OSError, ValueError):
                return None
        with (BUILD / "auto-subforms-desktop.log").open("w") as log:
            process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
                                        "--dataless", "--opening-mode", "compiled" if args.compiled else "interpreted",
                                        "--webadmin-auto-start", "false"], stdout=log, stderr=log)
            try:
                ready, _ = wait_for_start(process, project, launch_state, BUILD)
                if ready.get("compiled") is not args.compiled:
                    raise RuntimeError("Fixture did not start in the requested execution mode")
                activate_fixture(process, project, TITLE)
                subprocess.run([sys.executable, str(ROOT / "test_auto_subforms.py"), "--run"], check=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
        return
    if len(pids) != 1:
        parser.error("Launch the exact disposable AutoSubforms project")
    pid = int(pids[0])
    command = subprocess.check_output(["ps", "-p", str(pid), "-o", "command="], text=True)
    if "--project " + str(FIXTURE / "Project/AutoSubforms.4DProject") not in command:
        parser.error("Refusing another project")
    compiled = json.loads((BUILD / "auto-subforms-compile-report.json").read_text())
    if not compiled["passed"]:
        parser.error("Compile the fixture first")
    for relative, expected in compiled["sources_sha256"].items():
        if sha(FIXTURE / relative) != expected:
            parser.error("Source changed after compilation: " + relative)
    for key, path in [("component_sha256", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"),
                      ("native_sha256", "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")]:
        if sha(FIXTURE / path) != compiled[key]:
            parser.error("Package changed after compilation")
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    report = {"passed": False, **config, "checks": [], "process_architecture": process_architecture(pid),
              "compile_report_sha256": sha(BUILD / "auto-subforms-compile-report.json")}

    def check(value, name):
        report["checks"].append({"name": name, "passed": bool(value)})
        print(("PASS: " if value else "FAIL: ") + name, flush=True)
        if not value:
            raise AssertionError(name)

    def state():
        try:
            data = json.loads((FIXTURE / "Resources/runtime-status.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        if data.get("phase") == "failed" or data.get("failure"):
            raise AssertionError(str(data))
        return data if data.get("runId") == config["runId"] else {}

    try:
        ready = wait_for(lambda: state() if state().get("phase") == "ready" else None, "No current runtime state", 20)
        report["compiled"] = ready["compiled"]
        check(ready["start"]["ok"], "root start discovers all child controls")
        app = application(pid)
        window = next(w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE)
        app.set_boolean("AXFrontmost", True)
        wait_for(lambda: app.read("AXFrontmost") is True and (active := app.read("AXFocusedWindow")) and active.read("AXTitle") == TITLE, "Owned child fixture did not receive window focus")
        group = wait_for(lambda: next((e for e in window.read("AXChildren") or [] if (e.read("AXIdentifier") or "").startswith("axb.window.")), None), "No root provider")

        def elements():
            return group.read("AXChildren") or []

        def find(label, role=None):
            return next((e for e in elements() if e.read("AXDescription") == label and (role is None or e.read("AXRole") == role)), None)

        def field(label):
            return find(label + ": Name", "AXTextField")

        def settle():
            wait_for(lambda: group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"), "Action did not receive a receipt")
            state()

        names = ["Shipping", "Billing", "Scalar", "Unbound", "Nested"]
        if config.get("sharedFocus"):
            check(all(child["sharedButtonBinding"] for child in state()["children"].values()),
                  "all repeated buttons intentionally share the same process binding")
        wait_for(lambda: all(field(name) for name in names), "All five input children were not published")
        check(len([e for e in elements() if e.read("AXRole") == "AXTextField"]) == 5, "shared, scalar, unbound and nested inputs are exposed once")
        check(len({field(name).read("AXIdentifier") for name in names}) == 5, "shared business data does not merge instance identities")
        check(all(not child["hasProviderState"] for child in state()["children"].values()), "automatic child discovery does not write provider state into child business data")
        check(field("Shipping").read("AXValue") == field("Billing").read("AXValue") == "Shared", "repeated children preserve their intentional shared binding")
        check(field("Scalar").read("AXValue") == "Implicit", "scalar-bound child retains its implicit Form object")
        check(field("Unbound").read("AXValue") == "Unbound" and state()["children"]["Unbound"]["nullForm"], "a child with Null Form still exposes its process-bound controls")
        check(field("Nested").read("AXValue") == "Nested", "nested child reads its own data")
        check(abs(field("Billing").read("AXPosition")[0] - field("Shipping").read("AXPosition")[0] - 320) <= 3, "repeated child frames use their own coordinate origin")
        def at_center(element):
            x, y = element.read("AXPosition")
            width, height = element.read("AXSize")
            return app.at_position(x + width / 2, y + height / 2)

        for name in names:
            if config.get("scrollFocus"):
                check(field(name).perform("AXScrollToVisible") == 0, name + " field can be revealed without taking focus")
                settle()
            check(at_center(field(name)).read("AXIdentifier") == field(name).read("AXIdentifier"),
                  name + " child is discoverable by external screen-position lookup")
        for name in (("Billing", "Shipping", "Nested", "Scalar", "Unbound") if config.get("sharedFocus") else ("Billing", "Shipping", "Nested")):
            button = find(name + ": Remember")
            if not config.get("scrollFocus"):
                check(at_center(button).read("AXIdentifier") == button.read("AXIdentifier"),
                      name + " button is discoverable by external screen-position lookup")
            check(button.set_boolean("AXFocused", True) == 0, name + " repeated button accepts a focus request")
            if not config.get("focusObserver", True):
                wait_for(lambda: any(issue["reason"] == "ambiguousFocus" for issue in state().get("diagnostics", {}).get("issues", [])), "Unobserved shared binding did not report ambiguous focus")
                check(not any(e.read("AXFocused") is True for e in elements() if (e.read("AXDescription") or "").endswith(": Remember")),
                      "without the observer no repeated button claims ambiguous native focus")
                paths = {tuple(issue["path"]) for issue in state()["diagnostics"]["issues"] if issue["reason"] == "ambiguousFocus"}
                check(paths == {("Left",), ("Right",), ("Scalar",), ("Unbound",), ("Panel", "Nested")},
                      "ambiguous focus diagnostics identify every affected form path")
                find("Close fixture").press()
                wait_for(lambda: str(pid) not in subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split(), "Negative-control fixture did not close", 10)
                report["passed"] = True
                return
            wait_for(lambda: button.read("AXFocused") is True, name + " repeated button focus was not identified")
            settle()
            check(app.read("AXFocusedUIElement").read("AXIdentifier") == button.read("AXIdentifier")
                  and sum(e.read("AXFocused") is True for e in elements()) == 1,
                  name + " button focus identifies exactly one instance")
            if config.get("sharedFocus"):
                check(not any(issue["reason"] == "ambiguousFocus" for issue in state().get("diagnostics", {}).get("issues", [])),
                      name + " observed focus has no ambiguous-focus diagnostic")
            if config.get("scrollFocus"):
                check(at_center(button).read("AXIdentifier") == button.read("AXIdentifier"),
                      name + " focused button is revealed at its current position")
        shipping, billing = field("Shipping"), field("Billing")
        check(billing.set_text("Billing edit 🎸") == 0, "edit requested in the second shared-data child")
        wait_for(lambda: billing.read("AXValue") == "Billing edit 🎸", "Shared child editor did not accept text")
        settle()
        focus = app.read("AXFocusedUIElement")
        check(focus and focus.read("AXIdentifier") == billing.read("AXIdentifier"), "keyboard and application AX focus identify the actual repeated child")
        check(sum(e.read("AXFocused") is True for e in elements()) == 1, "only one repeated child claims keyboard focus")
        check(shipping.read("AXValue") == "Shared" and field("Scalar").read("AXValue") == "Implicit"
              and field("Unbound").read("AXValue") == "Unbound" and field("Nested").read("AXValue") == "Nested",
              "uncommitted text stays on the actual editor instead of every same-named child")
        check(billing.set_range("AXSelectedTextRange", 0, 7) == 0, "selection requested inside the second shared-data child")
        wait_for(lambda: billing.read("AXSelectedTextRange") == (0, 7), "Repeated child selection did not change")
        settle()
        check(billing.read("AXSelectedText") == "Billing", "selected text belongs to the actual repeated-child editor")
        check(billing.set_string("AXSelectedText", "Office") == 0, "selected text replacement requested inside the child")
        wait_for(lambda: billing.read("AXValue") == "Office edit 🎸", "Repeated child selection was not replaced")
        settle()
        check(shipping.read("AXValue") == "Shared", "selection replacement does not publish the other child's uncommitted buffer")
        billing.set_text("Billing edit 🎸")
        wait_for(lambda: billing.read("AXValue") == "Billing edit 🎸", "Repeated child text did not restore")
        settle()
        check(find("Billing: Remember").press() == 0, "button requested inside the second child")
        wait_for(lambda: state()["children"]["Right"]["clicked"] == 1, "Child's ordinary button method did not run")
        settle()
        check(state()["children"]["Left"]["name"] == state()["children"]["Right"]["name"] == "Billing edit 🎸", "normal commit updates the shared business value in both children")
        right_origin = state()["children"]["Right"]["origin"]
        check(any(e["object"] == "Name" and e["origin"] == right_origin for e in state()["events"]), "normal validation runs in the targeted child context")
        check(field("Nested").set_text("Nested edit") == 0, "edit requested two levels deep")
        wait_for(lambda: field("Nested").read("AXValue") == "Nested edit", "Nested editor did not change")
        settle()
        find("Nested: Remember").press()
        wait_for(lambda: state()["children"]["Nested"]["clicked"] == 1, "Nested button did not run")
        settle()
        check(state()["children"]["Nested"]["name"] == "Nested edit", "nested input commits through its normal editor")
        for name in ("Scalar", "Unbound"):
            value = name + " edit 🎹"
            check(field(name).set_text(value) == 0, name + " child accepts an editor action")
            wait_for(lambda: field(name).read("AXValue") == value, name + " editor did not receive text")
            settle()
            check(app.read("AXFocusedUIElement").read("AXIdentifier") == field(name).read("AXIdentifier"),
                  name + " child owns application accessibility focus")
            find(name + ": Remember").press()
            wait_for(lambda: state()["children"][name]["clicked"] == 1, name + " ordinary button did not run")
            settle()
            check(state()["children"][name]["name"] == value, name + " edit commits through the normal binding")
        old_left, right_id = field("Shipping"), field("Billing").read("AXIdentifier")
        old_button = find("Shipping: Remember")
        old_id = old_left.read("AXIdentifier")
        find("Replace left").press()
        wait_for(lambda: field("Shipping") and field("Shipping").read("AXIdentifier") != old_id, "Same-form/data replacement kept old identity")
        settle()
        wait_for(lambda: state().get("invalidated"), "Replacement result was not published by the host timer")
        check(state()["invalidated"]["matchedParents"] == 1, "replacement boundary finds the owning parent")
        check(field("Billing").read("AXIdentifier") == right_id, "replacing one child preserves its sibling identity")
        old_left.set_text("Stale replacement edit")
        time.sleep(.3)
        check(field("Shipping").read("AXValue") == "Billing edit 🎸", "retained control cannot edit its same-data replacement")
        def check_observed_lifetime(previous, boundary):
            current = find("Shipping: Remember")
            check(current.read("AXIdentifier") != previous.read("AXIdentifier"), boundary + " gives the button a new identity")
            current.set_boolean("AXFocused", True)
            wait_for(lambda: current.read("AXFocused") is True, boundary + " did not observe the new button's focus")
            settle()
            previous.set_boolean("AXFocused", True)
            time.sleep(.2)
            check(current.read("AXFocused") is True and previous.read("AXFocused") is not True,
                  boundary + " cannot transfer observed focus back to a retired button")
        if config.get("sharedFocus"):
            check_observed_lifetime(old_button, "replacement")
        hidden = field("Shipping")
        find("Hide left").press()
        wait_for(lambda: field("Shipping") is None, "Hidden child remains published")
        hidden.set_text("Hidden edit")
        time.sleep(.3)
        check(state()["children"]["Left"]["name"] == "Billing edit 🎸", "hidden ancestor blocks retained child actions")
        find("Hide left").press()
        wait_for(lambda: field("Shipping"), "Child did not return")
        settle()
        find("Disable right").press()
        wait_for(lambda: field("Billing").read("AXEnabled") is False, "Disabled ancestor is not reflected")
        field("Billing").set_text("Disabled edit")
        time.sleep(.3)
        check(state()["children"]["Right"]["name"] == "Billing edit 🎸", "disabled ancestor blocks child edits")
        find("Disable right").press()
        wait_for(lambda: field("Billing").read("AXEnabled") is True, "Child did not re-enable")
        settle()
        old_nested, old_id = field("Nested"), field("Nested").read("AXIdentifier")
        old_button = find("Shipping: Remember")
        find("Change record").press()
        wait_for(lambda: (current := field("Nested")) and current.read("AXIdentifier") != old_id,
                 "Root scope did not invalidate descendants")
        old_nested.set_text("Previous record")
        time.sleep(.3)
        check(field("Nested").read("AXValue") == "Nested edit", "declarative record scope rejects retained descendant actions")
        if config.get("sharedFocus"):
            check_observed_lifetime(old_button, "record change")
        check(state()["ticks"] > 5, "ordinary parent timer remains active")
        parent_id = group.read("AXIdentifier")
        parent_field = field("Billing")
        find("Open shared-data window").press()
        other_window = wait_for(lambda: next((w for w in app.read("AXWindows") or []
            if w.read("AXTitle") == "AX bridge shared-data root"), None), "Shared-data dialog did not open")
        other_group = wait_for(lambda: next((e for e in other_window.read("AXChildren") or []
            if (e.read("AXIdentifier") or "").startswith("axb.window.")), None), "Shared-data window has no provider")
        check(other_group.read("AXIdentifier") != parent_id, "two roots sharing business data have independent sessions")
        check(parent_field.read("AXEnabled") is False, "modal shared-data window blocks parent actions")
        other_field = next(e for e in other_group.read("AXChildren") or [] if e.read("AXRole") == "AXTextField")
        check(other_field.set_text("Other root 🎻") == 0, "shared-data root editor accepts normal input")
        wait_for(lambda: other_field.read("AXValue") == "Other root 🎻", "Shared-data root editor did not change")
        wait_for(lambda: other_group.read("AXHelp") not in (None, "Action queued", "Waiting for the application to complete the action"), "Shared root edit has no receipt")
        next(e for e in other_group.read("AXChildren") or [] if e.read("AXDescription") == "Remember shared value").press()
        def shared_state():
            try:
                return json.loads((FIXTURE / "Resources/shared-root.json").read_text(encoding="utf-8-sig"))
            except (OSError, ValueError):
                return {}
        wait_for(lambda: shared_state().get("remembered") == "Other root 🎻", "Shared-data root did not commit through its handler")
        check(shared_state()["start"]["ok"], "second root started without detaching its parent")
        next(e for e in other_group.read("AXChildren") or [] if e.read("AXDescription") == "Close shared window").press()
        wait_for(lambda: all(w.read("AXTitle") != "AX bridge shared-data root" for w in app.read("AXWindows") or []), "Shared-data window did not close")
        wait_for(lambda: (current := field("Billing")) and current.read("AXValue") == "Other root 🎻"
                 and current.read("AXEnabled") is True, "Parent provider did not resume after the shared-data dialog closed")
        check(group.read("AXIdentifier") == parent_id, "closing the shared-data root preserves the original parent session")
        other_field.set_text("Closed root edit")
        time.sleep(.3)
        check(field("Billing").read("AXValue") == "Other root 🎻", "retained child-window editor cannot edit the shared parent data")
        if config.get("sharedFocus"):
            check(field("Shipping").set_text("Redirect shared focus") == 0, "edit the first repeated field before its native data-change redirect")
            wait_for(lambda: field("Shipping").read("AXValue") == "Redirect shared focus", "Redirect probe text did not arrive")
            settle()
            find("Shipping: Remember").set_boolean("AXFocused", True)
            wait_for(lambda: field("Billing").read("AXFocused") is True, "Native data-change handler did not redirect to the sibling editor")
            settle()
            check(app.read("AXFocusedUIElement").read("AXIdentifier") == field("Billing").read("AXIdentifier")
                  and field("Shipping").read("AXFocused") is False,
                  "handler-driven focus between shared editors identifies the actual sibling")
        check(find("Close fixture").press() == 0, "ordinary close requested")
        wait_for(lambda: str(pid) not in subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split(), "Fixture did not close", 10)
        check(True, "root close retires all automatic children")
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        try:
            report["finalState"] = state()
        except Exception as state_error:
            report["finalStateError"] = str(state_error)
        if "group" in locals():
            report["finalReceipt"] = group.read("AXHelp")
            focused = app.read("AXFocusedUIElement")
            report["focusedIdentifier"] = focused.read("AXIdentifier") if focused else None
            close = find("Close fixture")
            if close:
                close.press()
            elif window.read("AXTitle") == TITLE and (native_close := window.read("AXCloseButton")):
                native_close.press()
            wait_for(lambda: str(pid) not in subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True).stdout.split(), "Failed fixture did not close", 10)
        raise
    finally:
        suffix = "implicit" if config["implicit"] else "object"
        if config.get("sharedFocus"):
            suffix += "-shared-focus"
        if config.get("scrollFocus"):
            suffix += "-scroll"
        if not config.get("focusObserver", True):
            suffix += "-unobserved"
        (BUILD / f"auto-subforms-{suffix}-report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
