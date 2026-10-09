#!/usr/bin/env python3
"""4D's Query editor through accessibility and VoiceOver.

Prepares the query editor fixture with --server. The editor must publish each criterion's
conjunction, field, comparison and value, the buttons that add and remove criteria, the
destination and the Query and Cancel buttons. A field is chosen from the list its arrow
opens, a comparison and conjunction from their menus, and a value is written; Query then
returns the selection those criteria find. --baseline records the editor without any
plugin, component or helpers; a later --run then requires it unchanged.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
from build_component import BUILD, sha
FIXTURE = BUILD / "query-editor-fixture"
PIXELS = BUILD / "query-editor-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "Query in [Orders]"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free editor for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Build and run a query with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    from test_native_messages import changed_pixels
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_query_editor_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    run_id = json.loads((FIXTURE / "Resources/launch.json").read_text())["runId"]
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    data = FIXTURE / "Data/Orders.4DD"
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/QueryEditor.4DProject"), "--data", str(data), "--create-data", "--opening-mode",
               "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if vo:
        # Keys reach whatever is frontmost; never post one into another application.
        vo.set_guard(vo.guard_frontmost(process.pid, ax))

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)
        ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)

    def window():
        return next((w for w in ax.application(process.pid).read("AXWindows") or [] if w.read("AXTitle") == TITLE), None)

    def published():
        """The published elements by key, with the field list's lines after it."""
        found = {}

        def visit(children):
            for child in children or []:
                identifier = child.read("AXIdentifier") or ""
                if identifier.startswith("axb/query/"):
                    found[identifier[len("axb/query/"):]] = child
                    if child.read("AXRole") == "AXList":
                        visit(child.read("AXChildren"))
        for current in ax.application(process.pid).read("AXWindows") or []:
            visit(current.read("AXChildren"))
        return found

    def element(key):
        return published().get(key)

    def items():
        return {key[len("fields/item/"):]: value for key, value in published().items() if key.startswith("fields/item/")}

    def menu():
        """The pop-up menu 4D shows, outside the menu bar."""
        def walk(node, depth=0):
            if depth > 5 or node.read("AXRole") == "AXMenuBar":
                return None
            if node.read("AXRole") == "AXMenu":
                return node
            for child in node.read("AXChildren") or []:
                found = walk(child, depth + 1)
                if found:
                    return found
        return walk(ax.application(process.pid))

    def choose(key, title):
        """Open a popup's menu through accessibility and press one of its items."""
        check_press = element(key).perform("AXPress")
        opened = ax.wait_for(menu, "The menu of " + key, timeout=10)
        titles = [item.read("AXTitle") for item in opened.read("AXChildren") or [] if item.read("AXTitle")]
        target = next(item for item in opened.read("AXChildren") or [] if item.read("AXTitle") == title)
        assert check_press == 0 and target.perform("AXPress") == 0
        ax.wait_for(lambda: menu() is None and element(key).read("AXValue") == title, key + " shows " + title, timeout=10)
        return titles

    def choose_field(key, name):
        """Open the field list from a line's field and press one field."""
        assert element(key).perform("AXPress") == 0
        listed = ax.wait_for(lambda: items() or None, "The field list", timeout=10)

        def focus():
            current = ax.application(process.pid).read("AXFocusedUIElement")
            label = current.read("AXDescription") if current else None
            return label if label in listed else None
        try:
            focused = ax.wait_for(focus, "Focus in the field list", timeout=5)
        except AssertionError:
            focused = None
        assert listed[name].perform("AXPress") == 0
        ax.wait_for(lambda: not items() and element(key).read("AXValue") == "[Orders]" + name, key + " shows " + name, timeout=10)
        return sorted(listed), focused

    def write(key, value):
        assert element(key).set_text(value) == 0
        ax.wait_for(lambda: element(key).read("AXValue") == value, key + " shows " + repr(value), timeout=10)

    def result():
        path = FIXTURE / "Resources/result.json"
        return json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else None

    def stop():
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(10)

    if args.baseline:
        try:
            ax.wait_for(window, "Query editor", timeout=60)
            front()
            time.sleep(3)
            PIXELS.mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            stop()
        print("Recorded the plugin-free Query editor")
        return

    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "voiceover": args.voiceover,
              "checks": [], "pluginSHA256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS: " + description, flush=True)

    def phrase_until(predicate, since, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    def vo_to(predicate, limit=24):
        """Move the VoiceOver cursor right until it reads a matching phrase. One move can say more
        than one phrase, such as the window's name as VoiceOver returns to it, then the element."""
        for _ in range(limit):
            front(); mark = heard.mark(); vo.key("right", vo.VO)
            phrase = phrase_until(lambda ph: ph.strip() != "", mark)
            time.sleep(0.5)
            phrase = next((ph for _, ph in heard.since(mark) if predicate(ph)), phrase)
            if predicate(phrase):
                return phrase
        raise AssertionError("VoiceOver did not reach the expected element")

    try:
        ax.wait_for(lambda: window() and element("query"), "The Query editor is published", timeout=60)
        front()
        time.sleep(1)
        if not args.voiceover:
            reference = PIXELS / f"baseline-{architecture}.png"
            if reference.exists():
                time.sleep(1.5)
                ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
                changed = changed_pixels(reference, PIXELS / f"bridge-{architecture}.png", caret=True)
                report["changedPixels"] = changed
                check(changed == 0, "the Query editor is pixel-identical to the plugin-free editor")
        elements = published()
        roles = {key: (value.read("AXRole"), value.read("AXDescription")) for key, value in elements.items()}
        report["published"] = roles
        check(roles.get("line1/target") == ("AXPopUpButton", "Field") and roles.get("line1/popup.0") == ("AXPopUpButton", "Comparison") and
              roles.get("line1/box.1") == ("AXTextField", "Value"), "a criterion is published as its field, comparison and value")
        check(roles.get("line1/add") == ("AXButton", "Add line") and roles.get("line1/delete") == ("AXButton", "Remove line") and
              roles.get("destination") == ("AXPopUpButton", "Destination") and roles.get("options") == ("AXPopUpButton", "Query options"),
              "its line buttons, destination and options are labelled")
        check(roles.get("query") == ("AXButton", "Query") and roles.get("cancel") == ("AXButton", "Cancel"), "Query and Cancel are buttons with their titles")
        if args.voiceover:
            check(phrase_until(lambda ph: TITLE in ph, 0, 40), "VoiceOver reaches the Query editor")
            current = element("line1/target").read("AXValue").split("]")[-1]
            check(vo_to(lambda ph: "Field" in ph and "pop up button" in ph), "VoiceOver reads the criterion's field as a pop-up button")
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            ax.wait_for(lambda: items() or None, "The field list", timeout=10)
            check(phrase_until(lambda ph: current in ph, mark), "VO-Space opens the field list on the current field")
            for _ in range(8):
                front(); mark = heard.mark(); vo.key("right", vo.VO)
                if "Customer" in phrase_until(lambda ph: ph.strip() != "", mark):
                    break
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: not items() and element("line1/target").read("AXValue") == "[Orders]Customer", "Customer chosen", timeout=10)
            check(True, "VO-Space on a field in the list chooses it")
            check(vo_to(lambda ph: "Comparison" in ph), "VoiceOver reaches the comparison")
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            ax.wait_for(menu, "The comparison menu", timeout=10)
            for _ in range(6):
                front(); mark = heard.mark(); vo.key("down")
                if "starts with" in phrase_until(lambda ph: ph.strip() != "", mark):
                    break
            front(); vo.key("return")
            ax.wait_for(lambda: element("line1/popup.0").read("AXValue") == "starts with", "starts with chosen", timeout=10)
            check(True, "the comparison is chosen from its menu with the arrow keys and Return")
            check(vo_to(lambda ph: "Value" in ph), "VoiceOver reaches the value")
            time.sleep(1)
            front(); vo.type_text("Customer 3")
            ax.wait_for(lambda: element("line1/box.1").read("AXValue") == "Customer 3", "The typed value", timeout=10)
            check(True, "keys typed at the value enter it in 4D's own field")
            check(vo_to(lambda ph: "Query" in ph and "button" in ph), "VoiceOver reaches the Query button")
            front(); vo.key("space", vo.VO)
            ax.wait_for(result, "The query result", timeout=20)
            outcome = result()
            check(outcome["runId"] == run_id and outcome["ok"] == 1 and outcome["customers"] == ["Customer 3"], "VO-Space on Query runs the query the criteria describe")
            report["speech"] = [ph for _, ph in heard.since(0)]
        else:
            listed, focused = choose_field("line1/target", "Customer")
            check({"Amount", "Customer", "Due", "id", "Note01"} <= set(listed), "the field list publishes the table's fields as buttons")
            report["listFocus"] = focused
            check(focused is not None and focused in listed, "the field list starts on the line's current field")
            check(element("line1/target").read("AXValue") == "[Orders]Customer", "pressing a field in the list makes it the criterion's field")
            # A table longer than the list's box: page down to its last fields and back, then keep Customer.
            assert element("line1/target").perform("AXPress") == 0
            bar = ax.wait_for(lambda: element("fields/scroll"), "The field list's scroll bar", timeout=10)
            check(bar.read("AXRole") == "AXScrollBar" and bar.read("AXDescription") == "Fields" and bar.read("AXValue") == 0 and "Note20" not in items(),
                  "the field list's scroll bar is at the top, with the first fields shown")
            assert bar.perform("AXIncrement") == 0
            ax.wait_for(lambda: "Note20" in items(), "The last fields", timeout=10)
            check("Amount" not in items() and element("fields/scroll").read("AXValue") > 0.5, "incrementing the scroll bar pages down to the table's last fields")
            assert element("fields/scroll").perform("AXDecrement") == 0
            ax.wait_for(lambda: "Customer" in items(), "The first fields", timeout=10)
            assert items()["Customer"].perform("AXPress") == 0
            ax.wait_for(lambda: not items() and element("line1/target").read("AXValue") == "[Orders]Customer", "Customer kept", timeout=10)
            check(True, "decrementing it pages back up to the first fields, and a field there is chosen")
            comparisons = choose("line1/popup.0", "starts with")
            check({"contains", "starts with", "is between"} <= set(comparisons), "the comparison opens 4D's own menu of comparisons for a text field")
            write("line1/box.1", "Customer 3")
            check(True, "writing the value types it into 4D's own field")
            assert element("line1/add").perform("AXPress") == 0
            ax.wait_for(lambda: element("line2/operator"), "A second criterion", timeout=10)
            check(element("line2/operator").read("AXValue") == "And", "Add line adds a criterion, joined with And")
            conjunctions = choose("line2/operator", "Or")
            report["conjunctions"] = conjunctions
            check("Or" in conjunctions, "the conjunction is chosen from its menu")
            choose_field("line2/target", "Amount")
            choose("line2/popup.0", "is strictly greater than")
            write("line2/box.1", "40")
            check(True, "the second criterion is built the same way")
            assert element("line2/add").perform("AXPress") == 0
            ax.wait_for(lambda: element("line3/delete"), "A third criterion", timeout=10)
            assert element("line3/delete").perform("AXPress") == 0
            ax.wait_for(lambda: element("line3/delete") is None and element("line2/box.1"), "The third criterion removed", timeout=10)
            check(element("line2/box.1").read("AXValue") == "40", "Remove line removes only its criterion")
            choose("line1/popup.0", "starts with")
            assert element("query").perform("AXPress") == 0
            ax.wait_for(result, "The query result", timeout=20)
            outcome = result()
            check(outcome["runId"] == run_id and outcome["compiled"] == args.compiled and outcome["ok"] == 1 and
                  outcome["customers"] == ["Customer 3", "Customer 5"], "Query runs the query the criteria describe")
        process.wait(20)
        report["passed"] = True
    finally:
        if heard:
            # Kept on failure too, to show where VoiceOver was.
            report["speech"] = [ph for _, ph in heard.since(0)]
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "query-editor-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} Query editor checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
