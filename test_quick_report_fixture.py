#!/usr/bin/env python3
"""4D's Quick Report editor through accessibility and VoiceOver.

Prepares the quick report fixture with --server. The editor must publish its toolbar, the
report's columns and its record count. Its Fields sheet must publish the available fields,
added by pressing them, the report's columns, selected by pressing them, and the buttons
that move them. Its Destination panel must publish the destinations as radio buttons. A
report built this way and executed to HTML must contain the table's data. --baseline
records the editor without any plugin, component or helpers; a later --run then requires
it unchanged.
"""
import argparse
import ctypes as c
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
from build_component import BUILD, sha
FIXTURE = BUILD / "quick-report-fixture"
PIXELS = BUILD / "quick-report-pixels"
OUTPUT = BUILD / "quick-report-output"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "Report"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free editor for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Build a report with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    from test_native_messages import changed_pixels
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_quick_report_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/QuickReport.4DProject"), "--data", str(FIXTURE / "Data/Orders.4DD"), "--create-data",
               "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if vo:
        # Keys reach whatever is frontmost; never post one into another application.
        vo.set_guard(vo.guard_frontmost(process.pid, ax))
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    graphics.CGEventCreateKeyboardEvent.restype = c.c_void_p
    graphics.CGEventCreateKeyboardEvent.argtypes = (c.c_void_p, c.c_uint16, c.c_bool)
    graphics.CGEventSetFlags.argtypes = (c.c_void_p, c.c_uint64)
    graphics.CGEventPostToPid.argtypes = (c.c_int, c.c_void_p)
    graphics.CGEventPost.argtypes = (c.c_uint32, c.c_void_p)

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)
        ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)

    def key(code, flags=0):
        """One key with its modifiers released afterwards, only while 4D is frontmost. macOS's
        Save dialog runs in its own service, so the key goes to the frontmost window, not a process."""
        if ax.application(process.pid).read("AXFrontmost") is not True:
            raise RuntimeError("4D lost the foreground; refusing to post a key")
        for down in (True, False):
            event = graphics.CGEventCreateKeyboardEvent(None, code, down)
            graphics.CGEventSetFlags(event, flags if down else 0)
            graphics.CGEventPost(0, event)
            ax.release(event)
            time.sleep(0.08)

    def window(title=TITLE):
        return next((w for w in ax.application(process.pid).read("AXWindows") or [] if w.read("AXTitle") == title), None)

    def published():
        current = window()
        found = {}
        for child in (current.read("AXChildren") if current else None) or []:
            # Read each identifier once: an element can retire between two reads.
            identifier = child.read("AXIdentifier") or ""
            if identifier.startswith("axb/report/"):
                found[identifier[len("axb/report/"):]] = child
        return found

    def element(key_name):
        return published().get(key_name)

    def press(key_name):
        assert element(key_name).perform("AXPress") == 0, key_name

    def sheet():
        """The report's sheet: its column titles, and each row's cells, the row's title first."""
        table = element("table")
        if table is None:
            return [], []
        headers = [header.read("AXValue") for header in table.read("AXColumnHeaderUIElements") or []]
        return headers, [[cell.read("AXValue") for cell in row.read("AXChildren") or []] for row in table.read("AXRows") or []]

    def cell(title, column):
        table = element("table")
        headers, rows = sheet()
        r = next(i for i, row in enumerate(rows) if row[0] == title)
        return table.read("AXRows")[r].read("AXChildren")[headers.index(column)]

    def menu():
        """The context menu 4D opens over the window."""
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

    def columns(prefix):
        return [value.read("AXValue") if prefix == "column/" else value.read("AXDescription")
                for name, value in published().items() if name.startswith(prefix)]

    def find(node, predicate, depth=0):
        if depth > 10:
            return None
        if predicate(node):
            return node
        for child in node.read("AXChildren") or []:
            found = find(child, predicate, depth + 1)
            if found:
                return found
        return None

    def save_as(path):
        """Save through macOS's own Save dialog: its folder by Go to Folder, then its name."""
        dialog = ax.wait_for(lambda: window("Save"), "The Save dialog", timeout=15)
        front()
        key(5, (1 << 20) | (1 << 17))  # Command-Shift-G
        folder = ax.wait_for(lambda: find(dialog, lambda n: n.read("AXIdentifier") == "PathTextField"), "Go to Folder", timeout=10)
        assert folder.set_text(str(path.parent)) == 0
        time.sleep(0.5)
        key(36)  # Return
        time.sleep(1.5)
        name = ax.wait_for(lambda: find(dialog, lambda n: n.read("AXIdentifier") == "saveAsNameTextField"), "The name field", timeout=10)
        assert name.set_text(path.name) == 0
        time.sleep(0.5)
        save = find(dialog, lambda n: n.read("AXIdentifier") == "OKButton")
        assert save.perform("AXPress") == 0

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
            ax.wait_for(window, "Quick Report editor", timeout=60)
            front()
            time.sleep(3)
            PIXELS.mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            stop()
        print("Recorded the plugin-free Quick Report editor")
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

    def vo_to(predicate, limit=30):
        for _ in range(limit):
            front(); mark = heard.mark(); vo.key("right", vo.VO)
            phrase = phrase_until(lambda ph: ph.strip() != "", mark)
            if predicate(phrase):
                return phrase
        raise AssertionError("VoiceOver did not reach the expected element")

    output = OUTPUT / f"orders-{architecture}{'-compiled' if args.compiled else ''}{'-voiceover' if args.voiceover else ''}.html"
    try:
        ax.wait_for(lambda: window() and element("run"), "The Quick Report editor is published", timeout=60)
        front()
        time.sleep(1)
        if not args.voiceover:
            reference = PIXELS / f"baseline-{architecture}.png"
            if reference.exists():
                time.sleep(1.5)
                ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
                changed = changed_pixels(reference, PIXELS / f"bridge-{architecture}.png")
                report["changedPixels"] = changed
                check(changed == 0, "the Quick Report editor is pixel-identical to the plugin-free editor")
        toolbar = [element(name).read("AXDescription") for name in ("new", "open", "save", "destination", "preview", "run", "options", "fields")]
        check(toolbar == ["New", "Open…", "Save", "Destination", "Preview", "Execute", "Options", "Fields"], "the toolbar's buttons are published by their titles")
        check(element("status").read("AXValue") == "Number of records: 5" and element("table") is None, "the record count is published, and a new report has no sheet")
        if args.voiceover:
            check(phrase_until(lambda ph: TITLE in ph, 0, 40), "VoiceOver reaches the Quick Report editor")
            check(vo_to(lambda ph: "Fields" in ph and "button" in ph), "VoiceOver reaches the Fields button")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: element("sheet/ok"), "The Fields sheet", timeout=10)
            check(vo_to(lambda ph: ph.startswith("Customer") and "button" in ph), "VoiceOver reads the available fields")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: columns("sheet/column/") == ["[Orders]Customer"], "Customer added", timeout=10)
            check(True, "VO-Space on a field adds it to the report's columns")
            check(vo_to(lambda ph: "OK" in ph and "button" in ph), "VoiceOver reaches OK")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: sheet()[0][1:] == ["[Orders]Customer"], "The column", timeout=10)
            check(True, "OK makes the chosen field the report's column")
            # The report's sheet: a table to interact with, whose cells open 4D's menus.
            front(); mark = heard.mark(); vo.key("home", vo.VO)
            phrase_until(lambda ph: ph.strip() != "", mark)
            check(vo_to(lambda ph: "Report" in ph and "table" in ph), "VoiceOver reads the report's sheet as a table")
            time.sleep(2)
            front(); mark = heard.mark(); vo.key("down", vo.VO + ("shift",))
            check(phrase_until(lambda ph: "Title" in ph, mark), "interacting with it reads the first row's title")
            front(); mark = heard.mark(); vo.key("right", vo.VO)
            check(phrase_until(lambda ph: "Customer" in ph, mark), "VO-Right reads the column's title cell")
            # The cell's Show Menu, in VoiceOver's actions menu.
            front(); mark = heard.mark(); vo.key("space", vo.VO + ("cmd",)); time.sleep(1)
            actions = [phrase_until(lambda ph: ph.strip() != "", mark)]
            for _ in range(4):
                if "show menu" in actions[-1].lower():
                    break
                front(); mark = heard.mark(); vo.key("down")
                actions.append(phrase_until(lambda ph: ph.strip() != "", mark))
            report["actionsMenu"] = actions
            check("show menu" in actions[-1].lower(), "VoiceOver's actions menu offers the cell's Show menu")
            front(); vo.key("return")
            ax.wait_for(menu, "The cell's menu", timeout=10)
            titles = [item.read("AXTitle") for item in menu().read("AXChildren") or []]
            front(); mark = heard.mark(); vo.key("down")
            heard_item = phrase_until(lambda ph: "Edit" in ph, mark)
            front(); vo.key("escape")
            ax.wait_for(lambda: menu() is None, "The menu closed", timeout=10)
            check("Edit" in titles and heard_item, "Show menu opens 4D's menu for the cell, which VoiceOver reads")
            front(); mark = heard.mark(); vo.key("up", vo.VO + ("shift",))
            phrase_until(lambda ph: ph.strip() != "", mark)
            # The sheet's elements are gone; start again from the window's top.
            front(); mark = heard.mark(); vo.key("home", vo.VO)
            phrase_until(lambda ph: ph.strip() != "", mark)
            check(vo_to(lambda ph: "Destination" in ph and "button" in ph), "VoiceOver reaches Destination")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: element("destination/html"), "The Destination panel", timeout=10)
            check(vo_to(lambda ph: "Print" in ph and "radio button" in ph and "selected" in ph), "VoiceOver reads the destinations as radio buttons, Print selected")
        else:
            press("fields")
            ax.wait_for(lambda: element("sheet/ok"), "The Fields sheet", timeout=10)
            check({"id", "Customer", "Amount", "Paid", "Due"} <= set(columns("sheet/field/")) and element("sheet/b.remove.one").read("AXDescription") == "Remove column",
                  "the Fields sheet publishes the available fields and the buttons that move them")
            press("sheet/field/Customer")
            ax.wait_for(lambda: columns("sheet/column/") == ["[Orders]Customer"], "Customer added", timeout=10)
            press("sheet/field/Amount")
            ax.wait_for(lambda: columns("sheet/column/") == ["[Orders]Customer", "[Orders]Amount"], "Amount added", timeout=10)
            check(True, "pressing an available field adds it to the report's columns")
            press("sheet/column/[Orders]Customer")
            time.sleep(1)
            press("sheet/b.remove.one")
            ax.wait_for(lambda: columns("sheet/column/") == ["[Orders]Amount"], "Customer removed", timeout=10)
            check(True, "a column pressed, then Remove column, leaves the report")
            press("sheet/field/Customer")
            ax.wait_for(lambda: columns("sheet/column/") == ["[Orders]Amount", "[Orders]Customer"], "Customer added again", timeout=10)
            press("sheet/ok")
            ax.wait_for(lambda: sheet()[0][1:] == ["[Orders]Amount", "[Orders]Customer"], "The report's columns", timeout=10)
            headers, rows = sheet()
            check(element("run") is not None and element("table").read("AXRole") == "AXTable" and element("table").read("AXDescription") == "Report" and
                  [row[0] for row in rows] == ["Title", "Format", "Grand Total"] and rows[0] == ["Title", "Amount", "Customer"] and rows[1] == ["Format", "", ""],
                  "OK returns to the editor, whose sheet is a table: a column per field, titled as 4D draws it, and the row titles first")
            # Edit cells in place, as with a double click and the keyboard.
            cell("Title", "[Orders]Customer").set_string("AXValue", "Client")
            ax.wait_for(lambda: sheet()[1][0][2] == "Client", "The renamed title", timeout=10)
            cell("Format", "[Orders]Amount").set_string("AXValue", "###,##0.00")
            ax.wait_for(lambda: sheet()[1][1][1] == "###,##0.00", "The format", timeout=10)
            check(True, "writing a cell edits it in place: a column's title and its format")
            # A header's Show Menu opens 4D's own context menu for the column.
            assert element("table").read("AXColumnHeaderUIElements")[2].perform("AXShowMenu") == 0
            ax.wait_for(menu, "The column's menu", timeout=10)
            titles = [item.read("AXTitle") for item in menu().read("AXChildren") or []]
            front(); key(53)  # Escape
            ax.wait_for(lambda: menu() is None, "The menu closed", timeout=10)
            check("Delete this column" in titles and "Hide this column" in titles, "a column title's Show Menu opens 4D's menu for the column")
            assert cell("Grand Total", "[Orders]Amount").perform("AXShowMenu") == 0
            ax.wait_for(menu, "The cell's menu", timeout=10)
            titles = [item.read("AXTitle") for item in menu().read("AXChildren") or []]
            front(); key(53)
            ax.wait_for(lambda: menu() is None, "The menu closed", timeout=10)
            check("Clear Contents" in titles, "a cell's Show Menu opens 4D's menu for the cell")
            press("destination")
            ax.wait_for(lambda: element("destination/html"), "The Destination panel", timeout=10)
            destinations = {name: value.read("AXValue") for name, value in published().items() if name.startswith("destination/") and value.read("AXRole") == "AXRadioButton"}
            check(destinations == {"destination/file": False, "destination/printer": True, "destination/html": False}, "the destinations are radio buttons, Print chosen")
            press("destination/html")
            ax.wait_for(lambda: element("destination/html") is None, "The panel closed", timeout=10)
            press("destination")
            ax.wait_for(lambda: element("destination/html"), "The Destination panel", timeout=10)
            check(element("destination/html").read("AXValue") is True, "pressing HTML chooses it")
            press("destination/close")
            ax.wait_for(lambda: element("destination/html") is None, "The panel closed", timeout=10)
            OUTPUT.mkdir(parents=True, exist_ok=True)
            output.unlink(missing_ok=True)
            press("run")
            save_as(output)
            ax.wait_for(output.exists, "The saved report", timeout=20)
            time.sleep(1)
            html = output.read_text(errors="replace")
            check(all(f"Customer {i}" in html for i in range(1, 6)) and all(f"{10 * i}.00" in html for i in range(1, 6)) and "Client" in html,
                  "Execute writes the report the sheet describes, with every record, the edited title and the format")
        report["passed"] = True
    finally:
        if heard:
            report["speech"] = [ph for _, ph in heard.since(0)]
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "quick-report-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} Quick Report checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
