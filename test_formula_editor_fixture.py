#!/usr/bin/env python3
"""4D's formula editor through accessibility and VoiceOver.

Prepares the formula editor fixture with --server. The editor must publish its lists of fields,
operators and commands with the menus that choose what each shows, the formula, and its buttons.
Pressing a list's line inserts it into the formula, pressing a table or a theme of commands
expands or collapses it, the formula can be written, and OK returns it to the application, which
evaluates it. --baseline records the editor without any plugin, component or helpers; a later
--run then requires it unchanged.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
from build_component import BUILD, sha
FIXTURE = BUILD / "formula-editor-fixture"
PIXELS = BUILD / "formula-editor-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "Formula Editor"
PREFIX = "axb/formula/"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free editor for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Write the formula with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    from test_native_messages import changed_pixels
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_formula_editor_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    run_id = json.loads((FIXTURE / "Resources/launch.json").read_text())["runId"]
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        vo.CODES.setdefault("a", 0)
        heard = vo.Listener()
        vo.start()
        heard.start()
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/FormulaEditor.4DProject"), "--data", str(FIXTURE / "Data/Orders.4DD"), "--create-data",
               "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    app = ax.application(process.pid)
    if vo:
        # Keys reach whatever is frontmost; never post one into another application.
        vo.set_guard(vo.guard_frontmost(process.pid, ax))

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)
        ax.wait_for(lambda: app.read("AXFrontmost") is True, "4D did not come to the front", timeout=15)

    def window():
        return next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None)

    def published():
        current = window()
        found = {}
        for child in (current.read("AXChildren") if current else None) or []:
            identifier = child.read("AXIdentifier") or ""
            if identifier.startswith(PREFIX):
                found[identifier[len(PREFIX):]] = child
        return found

    def element(key):
        return published().get(key)

    def press(key):
        front()
        assert element(key).perform("AXPress") == 0, key

    def formula():
        field = element("formula")
        return field.read("AXValue") if field else None

    def lines(list_name):
        return [key[len(list_name) + 1:] for key in published() if key.startswith(list_name + "/") and key != list_name + "/show"]

    def menu():
        def walk(node, depth=0):
            if depth > 5 or node.read("AXRole") == "AXMenuBar":
                return None
            if node.read("AXRole") == "AXMenu":
                return node
            for child in node.read("AXChildren") or []:
                found = walk(child, depth + 1)
                if found:
                    return found
        return walk(app)

    def choose(popup, title):
        press(popup)
        opened = ax.wait_for(menu, "The menu opens", timeout=10)
        item = next(i for i in opened.read("AXChildren") or [] if i.read("AXTitle") == title)
        assert item.perform("AXPress") == 0, title
        ax.wait_for(lambda: element(popup).read("AXValue") == title, f"{title} chosen", timeout=10)

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
            ax.wait_for(window, "Formula editor", timeout=60)
            front()
            time.sleep(3)
            PIXELS.mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            stop()
        print("Recorded the plugin-free formula editor")
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

    def cursor():
        return vo._osa('tell application "VoiceOver" to get text under cursor of vo cursor') or ""

    def vo_to(predicate, limit=40):
        """Move the VoiceOver cursor to a matching element: the current one, then rightward, then
        leftward from the end, since VoiceOver orders this window's elements by position."""
        text = cursor()
        if predicate(text):
            return text
        for direction in ("right", "left"):
            repeated = 0
            for _ in range(limit):
                front(); vo.key(direction, vo.VO)
                time.sleep(0.5)
                previous, text = text, cursor()
                if predicate(text):
                    return text
                repeated = repeated + 1 if text == previous else 0
                if repeated >= 2:
                    break
        raise AssertionError("VoiceOver did not reach the expected element; last read " + repr(text))

    final = '[Orders]Customer+"/"+String([Orders]Amount*2)'
    try:
        ax.wait_for(lambda: window() and element("bOK"), "The formula editor is published", timeout=60)
        front()
        time.sleep(1)
        if not args.voiceover:
            reference = PIXELS / f"baseline-{architecture}.png"
            if reference.exists():
                time.sleep(1.5)
                ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
                changed = changed_pixels(reference, PIXELS / f"bridge-{architecture}.png", caret=True)
                report["changedPixels"] = changed
                check(changed == 0, "the formula editor is pixel-identical to the plugin-free editor")
        roles = {key: (value.read("AXRole"), value.read("AXDescription") or value.read("AXTitle") or value.read("AXValue")) for key, value in published().items()}
        report["published"] = roles
        check(roles.get("fields/show") == ("AXPopUpButton", "Tables") and element("fields/show").read("AXValue") == "Master Table" and
              {"item/id", "item/Customer", "item/Amount", "item/Paid", "item/Due"} <= set(lines("fields")) and roles["fields/item/Customer"][0] == "AXButton",
              "the table's fields are buttons, after the menu that chooses the tables")
        check(roles.get("operators/show") == ("AXPopUpButton", "Operators") and roles.get("operators/item/Concatenation", ("",))[0] == "AXButton",
              "the operators are buttons, after the menu that chooses their kind")
        check(roles.get("commands/show") == ("AXPopUpButton", "Commands") and roles.get("commands/group/Boolean", ("",))[0] == "AXDisclosureTriangle" and
              element("commands/group/Boolean").read("AXValue") == 0, "the themes of commands are collapsed disclosure triangles")
        check(roles.get("formula", ("",))[0] == "AXTextField" and roles["formula"][1] == "Formula" and formula() == "[Orders]Amount", "the formula is a text field holding the formula")
        check(all(roles.get(name, ("",))[0] == "AXButton" for name in ("bLoad", "bSave", "bCancel", "bOK")) and roles["bOK"][1] == "OK", "Load, Save, Cancel and OK are buttons")
        if args.voiceover:
            check(phrase_until(lambda ph: TITLE in ph, 0, 40), "VoiceOver reaches the formula editor")
            check(vo_to(lambda ph: "Boolean" in ph and "collapsed" in ph), "VoiceOver reads a theme of commands as collapsed")
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            ax.wait_for(lambda: element("commands/item/True"), "Boolean expanded", timeout=10)
            check(element("commands/group/Boolean").read("AXValue") == 1, "VO-Space on it expands it, showing its commands")
            check(vo_to(lambda ph: ph.startswith("Customer") and "button" in ph), "VoiceOver reads the fields")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: "[Orders]Customer" in (formula() or ""), "Customer inserted", timeout=10)
            check(True, "VO-Space on a field inserts it into the formula")
            check(vo_to(lambda ph: "Formula" in ph and "edit text" in ph), "VoiceOver reads the formula as an edit field")
            front(); vo.key("a", ("cmd",)); time.sleep(0.5)
            mark = heard.mark()
            vo.type_text("String([Orders]Amount*3)")
            ax.wait_for(lambda: formula() == "String([Orders]Amount*3)", "The typed formula", timeout=20)
            check(phrase_until(lambda ph: "3" in ph or ")" in ph or "right paren" in ph.lower(), mark), "typing replaces the formula, and VoiceOver echoes it")
            check(vo_to(lambda ph: ph.startswith("OK") and "button" in ph), "VoiceOver reaches OK")
            front(); vo.key("space", vo.VO)
            ax.wait_for(result, "The edited formula", timeout=20)
            outcome = result()
            check(outcome["runId"] == run_id and outcome["ok"] == 1 and outcome["formula"] == "String([Orders]Amount*3)" and
                  outcome["values"] == [str(30 * i) for i in range(1, 6)], "VO-Space on OK returns the formula, which the application evaluates")
        else:
            element("formula").set_text("")
            ax.wait_for(lambda: formula() == "", "The formula cleared", timeout=20)
            check(True, "writing the formula replaces it")
            press("fields/item/Customer")
            ax.wait_for(lambda: formula() == "[Orders]Customer", "Customer inserted", timeout=10)
            check(True, "pressing a field inserts it, as its double click does")
            press("operators/item/Concatenation")
            ax.wait_for(lambda: formula() == "[Orders]Customer+", "Concatenation inserted", timeout=10)
            check(True, "pressing an operator inserts it")
            press("commands/group/Boolean")
            ax.wait_for(lambda: element("commands/item/True") and element("commands/group/Boolean").read("AXValue") == 1, "Boolean expanded", timeout=10)
            check(lines("commands")[:4] == ["group/Boolean", "item/False", "item/Not", "item/True"], "pressing a theme expands it, its commands following it")
            press("commands/group/Boolean")
            ax.wait_for(lambda: not element("commands/item/True") and element("commands/group/Boolean").read("AXValue") == 0, "Boolean collapsed", timeout=10)
            check(True, "pressing it again collapses it")
            choose("commands/show", "Commands by Alphabetical Order")
            check(lines("commands")[:2] == ["item/Abs", "item/Add to date"], "the commands menu lists the commands alphabetically, as buttons")
            press("commands/item/Abs")
            ax.wait_for(lambda: formula() == "[Orders]Customer+Abs", "Abs inserted", timeout=10)
            check(True, "pressing a command inserts it")
            choose("fields/show", "All Tables")
            ax.wait_for(lambda: element("fields/group/[Orders]"), "The tables", timeout=10)
            check(element("fields/group/[Orders]").read("AXValue") == 0 and lines("fields") == ["group/[Orders]"], "the tables menu lists the tables, collapsed")
            press("fields/group/[Orders]")
            ax.wait_for(lambda: element("fields/item/Amount"), "Orders expanded", timeout=10)
            check(element("fields/group/[Orders]").read("AXValue") == 1, "pressing a table shows its fields")
            element("formula").set_text(final)
            ax.wait_for(lambda: formula() == final, "The final formula", timeout=30)
            check(True, "the formula is written as a keyboard user types it")
            press("bOK")
            ax.wait_for(result, "The edited formula", timeout=20)
            outcome = result()
            check(outcome["runId"] == run_id and outcome["compiled"] == args.compiled and outcome["ok"] == 1 and outcome["formula"] == final and
                  outcome["values"] == [f"Customer {i}/{20 * i}" for i in range(1, 6)], "OK returns the formula, which the application evaluates")
        process.wait(20)
        report["passed"] = True
    finally:
        if heard:
            report["speech"] = [ph for _, ph in heard.since(0)]
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "formula-editor-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} formula editor checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
