#!/usr/bin/env python3
"""An ordinary form with no bridge area, described by the plugin alone, through AX and VoiceOver.

Prepares the generic form fixture with --server. Its captions, inputs labelled by them,
checkbox, radio buttons, drop-down list and buttons must be published from the project's
form definition and the text 4D draws. Values written and controls pressed through
accessibility must reach the form, as its Save method records. --baseline records the
window without the plugin or component; a later --run then requires it unchanged.
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
FIXTURE = BUILD / "generic-form-fixture"
PIXELS = BUILD / "generic-form-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "AX bridge generic form"
CLICKED = 4
TITLE_BAR = 28
# Name has the initial focus; its insertion point blinks at the field's start (left 90, top 48).
CARET = (88, 48 + TITLE_BAR - 4, 93, 48 + TITLE_BAR + 20)


def content_changed_pixels(first, second):
    """Changed pixels outside the blinking insertion point."""
    from test_native_messages import rgba
    (size, a), (other, b) = rgba(first), rgba(second)
    if size != other:
        return size[0] * size[1]
    width = size[0]
    left, top, right, bottom = CARET
    return sum(1 for index in range(0, len(a), 4) if a[index:index + 4] != b[index:index + 4]
               and not (left <= (index // 4) % width < right and top <= (index // 4) // width < bottom))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free window for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Operate the form with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_generic_form_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    run_id = json.loads((FIXTURE / "Resources/launch.json").read_text())["runId"]
    plugin = None if args.baseline else sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/GenericForm.4DProject"), "--dataless", "--opening-mode",
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
        current = window()
        found = {}
        for child in (current.read("AXChildren") if current else None) or []:
            identifier = child.read("AXIdentifier") or ""
            if identifier.startswith("axb/form/"):
                found[identifier[len("axb/form/"):]] = child
        return found

    def element(name):
        return published().get(name)

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
        return walk(ax.application(process.pid))

    def events():
        path = FIXTURE / "Resources/events.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()] if path.exists() else []

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
            ax.wait_for(window, "Fixture window", timeout=60)
            front()
            time.sleep(3)
            PIXELS.mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            stop()
        print("Recorded the plugin-free generic form")
        return

    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "voiceover": args.voiceover,
              "checks": [], "pluginSHA256": plugin}

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
        """What VoiceOver's cursor is on. A hint can be spoken after the next move, so the last
        phrase does not always describe the cursor."""
        return vo._osa('tell application "VoiceOver" to get text under cursor of vo cursor')

    def vo_to(predicate, limit=20):
        # VoiceOver starts on 4D's focused object: check where it is, then move right, then back
        # left from the end.
        text = cursor()
        if predicate(text):
            return text
        for direction in ("right", "left"):
            repeated = 0
            for _ in range(limit):
                front(); vo.key(direction, vo.VO)
                time.sleep(0.4)
                previous, text = text, cursor()
                if predicate(text):
                    return text
                repeated = repeated + 1 if text == previous else 0
                if repeated >= 2:
                    break
        raise AssertionError("VoiceOver did not reach the expected element")

    def saved():
        return [e["values"] for e in events() if e.get("object") == "btnSave" and e.get("values")]

    try:
        ax.wait_for(lambda: window() and element("btnDone"), "The form is published", timeout=60)
        front()
        time.sleep(1)
        if not args.voiceover:
            reference = PIXELS / f"baseline-{architecture}.png"
            if reference.exists():
                time.sleep(1.5)
                ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
                changed = content_changed_pixels(reference, PIXELS / f"bridge-{architecture}.png")
                report["changedPixels"] = changed
                check(changed == 0, "the form is pixel-identical to the plugin-free form")
        order = list(published())
        report["published"] = order
        check(order == ["title", "search/inputSearch", "search/btnGo", "labelName", "inputName", "labelCity", "inputCity", "checkActive", "radioRetail", "radioWholesale", "dropdownTier", "widgetSearch/SearchButton_Mac", "widgetSearch/SearchText_Mac",
                        "btnSave", "btnHelp", "btnRefreshOrders", "labelOrders", "listOrders", "tabPages/Details", "tabPages/Notes", "btnDone"],
              "the form's labelled objects are published in reading order; a button with 4D's default name and an invisible button are not")
        name, city = element("inputName"), element("inputCity")
        check(name.read("AXRole") == "AXTextField" and name.read("AXDescription") == "Name" and name.read("AXValue") == "" and
              name.read("AXPlaceholderValue") == "Full name" and city.read("AXDescription") == "City" and city.read("AXValue") == "Lyon",
              "inputs are labelled by their captions, with their values and placeholders")
        check(element("checkActive").read("AXRole") == "AXCheckBox" and element("checkActive").read("AXValue") is False and
              element("radioRetail").read("AXValue") is True and element("radioWholesale").read("AXValue") is False,
              "the checkbox and radio buttons are published with their drawn states")
        check(element("dropdownTier").read("AXRole") == "AXPopUpButton" and element("dropdownTier").read("AXValue") == "Gold" and
              element("btnHelp").read("AXDescription") == "Help" and element("btnRefreshOrders").read("AXDescription") == "Refresh Orders",
              "the drop-down shows its value; an untitled button is labelled by its help tip, or else by its object name")
        table = element("listOrders")

        def rows():
            return [[cell.read("AXValue") for cell in row.read("AXChildren") or []] for row in element("listOrders").read("AXRows") or []]

        def selected():
            return [row.read("AXSelected") for row in element("listOrders").read("AXRows") or []]
        check(table.read("AXRole") == "AXTable" and table.read("AXDescription") == "Orders" and
              [h.read("AXValue") for h in table.read("AXColumnHeaderUIElements") or []] == ["Customer", "Total"] and
              rows() == [["Ada", "10"], ["Grace", "20"], ["Linus", "30"], ["Margaret", "40"]] and not any(selected()),
              "a list box is a table labelled by its caption, with the column titles 4D draws, one renamed at load, and its visible rows' cells")
        if args.voiceover:
            check(phrase_until(lambda ph: TITLE in ph, 0, 40), "VoiceOver reaches the form")
            check(vo_to(lambda ph: "Name" in ph and "edit text" in ph), "VoiceOver reads the Name field by its caption")
            time.sleep(1)
            front(); vo.type_text("Ada")
            ax.wait_for(lambda: element("inputName").read("AXValue") == "Ada", "The typed name", timeout=10)
            check(True, "keys typed at the field enter it in 4D's own field")
            front(); mark = heard.mark(); vo.key("tab")
            check(phrase_until(lambda ph: "City" in ph, mark), "VoiceOver follows 4D's focus to the next field when Tab moves it")
            check(vo_to(lambda ph: "Active" in ph and "checkbox" in ph and "unchecked" in ph), "VoiceOver reads the checkbox and its state")
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            ax.wait_for(lambda: element("checkActive").read("AXValue") is True, "Checked", timeout=10)
            check(True, "VO-Space checks the checkbox through its own handling")
            # Tab on through the radio buttons and the drop-down to Save, a button without a focus ring.
            heard_save = None
            for _ in range(6):
                front(); mark = heard.mark(); vo.key("tab")
                try:
                    heard_save = phrase_until(lambda ph: "Save" in ph and "button" in ph, mark, 4)
                    break
                except AssertionError:
                    pass  # VoiceOver read the radio buttons or the drop-down on the way
            check(heard_save, "VoiceOver follows 4D's focus to a button when Tab moves it")
            check(vo_to(lambda ph: "Save" in ph and "button" in ph), "VoiceOver reaches Save")
            check(vo_to(lambda ph: "Orders" in ph and "table" in ph), "VoiceOver reads the list box as a table labelled by its caption")
            time.sleep(2)  # let VoiceOver finish the table's announcement before interacting
            front(); mark = heard.mark(); vo.key("down", vo.VO + ("shift",))
            check(phrase_until(lambda ph: "Ada" in ph and "Customer" in ph, mark), "interacting with it reads the first row's cell with its column title")
            count = len(events())
            front(); mark = heard.mark(); vo.key("down", vo.VO)
            check(phrase_until(lambda ph: "Grace" in ph, mark), "VO-Down moves to the next row")
            # VoiceOver selects the row its cursor reaches, as in AppKit's tables.
            ax.wait_for(lambda: [e["position"] for e in events()[count:] if e["object"] == "listOrders"][-1:] == [2], "Row 2 selected", timeout=10)
            check([e["position"] for e in events()[count:] if e["object"] == "listOrders"].count(2) == 1,
                  "the row VoiceOver reaches is selected once, through the list box's own handling")
            front(); mark = heard.mark(); vo.key("up", vo.VO + ("shift",))
            phrase_until(lambda ph: ph.strip() != "", mark)
            # Back past the caption, Refresh Orders and Help to Save.
            front(); mark = heard.mark(); vo.key("left", vo.VO); vo.key("left", vo.VO); vo.key("left", vo.VO); vo.key("left", vo.VO)
            check(vo_to(lambda ph: "Save" in ph and "button" in ph), "VoiceOver returns to Save past the button named by its object name")
            front(); vo.key("space", vo.VO)
            ax.wait_for(saved, "Save's record", timeout=10)
            values = saved()[-1]
            check(values["name"] == "Ada" and values["active"] is True, "VO-Space runs Save, which reads the form's values")
            check(vo_to(lambda ph: "Notes" in ph and "radio" in ph), "VoiceOver reads a tab by its drawn label")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: element("labelNotes") is not None and element("inputName") is None, "The Notes page", timeout=10)
            check(element("tabPages/Notes").read("AXValue") is True, "VO-Space on a tab shows its page, and the tab is chosen")
            check(vo_to(lambda ph: "Order Lines" in ph and "table" in ph), "VoiceOver reads a list box without a caption by its object's name")
        else:
            # 4D's keyboard focus, drawn as its focus ring, is the application's focused element.
            focused = lambda: (ax.application(process.pid).read("AXFocusedUIElement") or name).read("AXIdentifier")
            ax.wait_for(lambda: focused() == "axb/form/inputName", "The focused Name field", timeout=10)
            import voiceover_session as keys
            keys.set_guard(keys.guard_frontmost(process.pid, ax))
            front(); keys.key("tab")
            ax.wait_for(lambda: focused() == "axb/form/inputCity", "City focused by Tab", timeout=10)
            front(); keys.key("tab")
            ax.wait_for(lambda: focused() == "axb/form/checkActive", "The checkbox focused by Tab", timeout=10)
            front(); keys.key("tab", ("shift",))
            ax.wait_for(lambda: focused() == "axb/form/inputCity", "City focused by Shift-Tab", timeout=10)
            for _ in range(4):
                front(); keys.key("tab")
            ax.wait_for(lambda: focused() == "axb/form/dropdownTier", "The drop-down focused by Tab", timeout=10)
            check(True, "Tab and Shift-Tab move the application's focused element with 4D's focus, through fields, checkboxes, radio buttons and a drop-down")
            front(); keys.key("tab")
            ax.wait_for(lambda: focused() == "axb/form/btnSave", "Save focused by Tab", timeout=10)
            front(); keys.key("tab")
            ax.wait_for(lambda: focused() == "axb/form/btnHelp", "Help focused by Tab", timeout=10)
            check(True, "Tab moves the focused element to buttons, which 4D draws without a focus ring")
            assert name.set_text("Ada Lovelace") == 0
            ax.wait_for(lambda: element("inputName").read("AXValue") == "Ada Lovelace", "The written name", timeout=10)
            assert element("inputCity").set_text("Paris") == 0
            try:
                ax.wait_for(lambda: element("inputCity").read("AXValue") == "Paris", "The written city", timeout=10)
            except AssertionError:
                report["cityValue"] = element("inputCity").read("AXValue"); report["nameValue"] = element("inputName").read("AXValue"); raise
            check(True, "writing an input's value types it into 4D's own field")
            count = len(events())
            assert element("checkActive").perform("AXPress") == 0
            ax.wait_for(lambda: element("checkActive").read("AXValue") is True, "Checked", timeout=10)
            check([e["event"] for e in events()[count:] if e["object"] == "checkActive"] == [CLICKED], "pressing the checkbox runs its On Clicked and checks it")
            assert element("radioWholesale").perform("AXPress") == 0
            ax.wait_for(lambda: element("radioWholesale").read("AXValue") is True and element("radioRetail").read("AXValue") is False, "Wholesale", timeout=10)
            check(True, "pressing a radio button chooses it and clears the other")
            assert element("dropdownTier").perform("AXPress") == 0
            opened = ax.wait_for(menu, "The drop-down's menu", timeout=10)
            silver = next(item for item in opened.read("AXChildren") or [] if item.read("AXTitle") == "Silver")
            assert silver.perform("AXPress") == 0
            ax.wait_for(lambda: element("dropdownTier").read("AXValue") == "Silver", "Silver", timeout=10)
            check(True, "the drop-down opens 4D's native menu, and choosing an item changes its value")
            count = len(events())
            assert element("listOrders").read("AXRows")[2].perform("AXPress") == 0
            ax.wait_for(lambda: selected() == [False, False, True, False], "Row 3 selected", timeout=10)
            check([e["position"] for e in events()[count:] if e["object"] == "listOrders"] == [3],
                  "pressing a row selects it through the list box's own handling, and the table reports it selected")
            assert element("search/inputSearch").set_text("Ada") == 0
            ax.wait_for(lambda: element("search/inputSearch").read("AXValue") == "Ada", "The search text", timeout=10)
            assert element("search/btnGo").perform("AXPress") == 0
            ax.wait_for(lambda: any(e["object"] == "btnGo" for e in events()), "Go's event", timeout=10)
            check(next(e for e in events() if e["object"] == "btnGo")["text"] == "Ada",
                  "a page subform's own objects are published in its place, and operated within it")
            widget = element("widgetSearch/SearchText_Mac")
            check(widget.read("AXRole") == "AXTextField" and widget.read("AXDescription") == "Search" and
                  element("widgetSearch/SearchButton_Mac").read("AXDescription") == "Search options",
                  "4D Widgets' search picker, from 4D's own component, is a text field labelled Search, beside its Search options button")
            assert widget.set_text("Ada") == 0
            ax.wait_for(lambda: element("widgetSearch/SearchText_Mac").read("AXValue") == "Ada", "The widget's text", timeout=10)
            assert element("btnHelp").perform("AXPress") == 0
            ax.wait_for(lambda: any(e["object"] == "btnHelp" for e in events()), "Help's event", timeout=10)
            assert element("btnRefreshOrders").perform("AXPress") == 0
            ax.wait_for(lambda: any(e["object"] == "btnRefreshOrders" for e in events()), "Refresh Orders' event", timeout=10)
            assert element("btnSave").perform("AXPress") == 0
            ax.wait_for(saved, "Save's record", timeout=10)
            values = saved()[-1]
            check(values == {"name": "Ada Lovelace", "city": "Paris", "active": True, "retail": 0, "wholesale": 1, "tier": 1, "query": "Ada"},
                  "pressing Save runs its method, which reads every value set through accessibility")
            check(element("tabPages/Details").read("AXRole") == "AXRadioButton" and element("tabPages/Details").read("AXValue") is True and
                  element("tabPages/Notes").read("AXValue") is False, "a tab control's tabs are radio buttons named by their drawn labels; the current page's is chosen")
            assert element("tabPages/Notes").perform("AXPress") == 0
            ax.wait_for(lambda: element("labelNotes") is not None and element("inputName") is None and element("tabPages/Notes").read("AXValue") is True,
                        "The Notes page", timeout=10)
            check(True, "pressing a tab shows its page through the tab control's own action, and the tab is chosen")
            check(element("lbOrderLines").read("AXRole") == "AXTable" and element("lbOrderLines").read("AXDescription") == "Order Lines",
                  "a list box without a caption is a table named by the words of its object name")
            assert element("tabPages/Details").perform("AXPress") == 0
            ax.wait_for(lambda: element("inputName") is not None and element("labelNotes") is None, "The Details page", timeout=10)
            check(all(e["runId"] == run_id and e["compiled"] == args.compiled for e in events()), "every event belongs to this run")
            assert element("btnDone").perform("AXPress") == 0
            process.wait(20)
            check(process.returncode == 0, "Done closes the form through its standard action")
        report["passed"] = True
    finally:
        if heard:
            report["speech"] = [ph for _, ph in heard.since(0)]
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name_ = "generic-form-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name_).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} generic form checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
