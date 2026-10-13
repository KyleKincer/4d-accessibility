#!/usr/bin/env python3
"""List boxes with no grid adapter, in a form with the bridge's area.

Prepares the generic form fixture with --area, so the installer gives its forms the lifecycle
area and the bridge describes them. Each list box has no grid entry in AXB_Configure: the
bridge publishes the rows 4D draws in its place, as for a form without an area. The test
checks the table's name, its column titles, which follow the form's run-time title change,
its rows, a row press that runs On Selection Change, and paging through a longer list on
another page. With --voiceover, VoiceOver reads the table and selects the row it reaches.
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
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "AX bridge generic form"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Read and select rows with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_generic_form_fixture.py"), "--server", str(args.server), "--area"], check=True)
    if not args.run:
        return
    ax.require_test_input()
    run_id = json.loads((FIXTURE / "Resources/launch.json").read_text())["runId"]
    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "checks": [],
              "pluginSHA256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/GenericForm.4DProject"), "--dataless", "--opening-mode",
               "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if vo:
        # Keys reach whatever is frontmost; never post one into another application.
        vo.set_guard(vo.guard_frontmost(process.pid, ax))

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS: " + description, flush=True)

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)
        ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)

    def window():
        return next((w for w in ax.application(process.pid).read("AXWindows") or [] if w.read("AXTitle") == TITLE), None)

    def element(name):
        current = window()
        return current.find("/" + name) if current else None

    def rows(name):
        table = element(name)
        return [[cell.read("AXValue") for cell in row.read("AXChildren") or []] for row in (table.read("AXRows") if table else None) or []]

    def headers(name):
        table = element(name)
        return [header.read("AXTitle") or header.read("AXDescription") or header.read("AXValue")
                for header in (table.read("AXColumnHeaderUIElements") if table else None) or []]

    def phrase_until(predicate, since, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    def vo_to(predicate, limit=30):
        cursor = lambda: vo._osa('tell application "VoiceOver" to get text under cursor of vo cursor')
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

    def events():
        path = FIXTURE / "Resources/events.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()] if path.exists() else []

    try:
        orders = ax.wait_for(lambda: element("listOrders"), "The bridge did not publish the list box", timeout=60)
        identifier = orders.read("AXIdentifier")
        check(identifier.startswith("axb/") and not identifier.startswith("axb/form/") and orders.read("AXRole") == "AXTable",
              "a list box with no grid adapter is a table in the bridge's own description")
        check(orders.read("AXDescription") == "Orders", "it is named by the words of its object name")
        check(element("btnRefreshOrders").read("AXDescription") == "Refresh Orders", "a button nothing labels is named by the words of its object name")
        ax.wait_for(lambda: rows("listOrders")[:4] == [["Ada", "10"], ["Grace", "20"], ["Linus", "30"], ["Margaret", "40"]],
                    "The drawn rows " + repr(rows("listOrders")), timeout=10)
        check(True, "its rows are the rows 4D draws")
        report["headers"] = headers("listOrders")
        check(report["headers"][:2] == ["Customer", "Total"], "its columns are titled as 4D shows them, after the form renames one")
        if vo:
            front()
            check(vo_to(lambda ph: "Orders" in ph and "table" in ph), "VoiceOver reads the list box as the Orders table")
            time.sleep(2)  # let VoiceOver finish the table's announcement before interacting
            front(); mark = heard.mark(); vo.key("down", vo.VO + ("shift",))
            check(phrase_until(lambda ph: "Ada" in ph, mark), "interacting with it reads the first row")
            count = len(events())
            front(); mark = heard.mark(); vo.key("down", vo.VO)
            check(phrase_until(lambda ph: "Grace" in ph, mark), "VO-Down moves to the next row")
            ax.wait_for(lambda: [e["position"] for e in events()[count:] if e["object"] == "listOrders"][-1:] == [2], "Row 2 selected", timeout=10)
            check(True, "the row VoiceOver reaches is selected through the list box's own handling")
            front(); vo.key("up", vo.VO + ("shift",))
            time.sleep(1)
        front()
        count = len(events())
        assert element("listOrders").read("AXRows")[2].perform("AXPress") == 0
        ax.wait_for(lambda: [e["position"] for e in events()[count:] if e["object"] == "listOrders"][-1:] == [3], "Row 3 selected", timeout=10)
        check(True, "pressing a row selects it through the list box's own On Selection Change")
        # The click gives the list box 4D's focus; the next action waits for that description.
        ax.wait_for(lambda: element("listOrders").read("AXFocused") is True, "The list box's focus", timeout=10)
        check(True, "the list box holding 4D's focus is the focused element")
        notes = element("tabPages/tab/2")
        assert notes is not None and notes.perform("AXPress") == 0
        try:
            lines = ax.wait_for(lambda: element("lbOrderLines"), "The Notes page's list box", timeout=15)
        except AssertionError:
            group = window().find("") if window() else None
            raise AssertionError("The Notes page's list box; tab " + repr(element("tabPages/tab/2").read("AXValue")) +
                                 ", receipt " + repr(next((c.read("AXHelp") for c in window().read("AXChildren") or [] if (c.read("AXIdentifier") or "").startswith("axb/")), None)))
        check(lines.read("AXDescription") == "Order Lines" and "AXScrollDownByPage" in lines.actions(),
              "a list box longer than its box offers to scroll a page")

        def line_rows():
            return [row[0] for row in rows("lbOrderLines") if row]

        ax.wait_for(lambda: line_rows()[:1] == ["Line 1"], "The first lines", timeout=10)
        for _ in range(12):
            if "Line 20" in line_rows():
                break
            first = line_rows()[:1]
            assert element("lbOrderLines").perform("AXScrollDownByPage") == 0
            ax.wait_for(lambda: line_rows()[:1] != first or "Line 20" in line_rows(), "A page down", timeout=10)
        check("Line 20" in line_rows() and "Line 1" not in line_rows(), "a page at a time, it scrolls to the last rows")
        check(all(e["runId"] == run_id and e["compiled"] == args.compiled for e in events()), "every event belongs to this run")
        done = element("btnDone")
        assert done is not None and done.perform("AXPress") == 0
        process.wait(20)
        check(process.returncode == 0, "Done closes the form")
        report["passed"] = True
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(20)
        if vo:
            heard.stop()
            vo.stop()
        (BUILD / f"drawn-listbox-{architecture}{'-compiled' if args.compiled else ''}{'-voiceover' if args.voiceover else ''}.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} drawn list box checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
