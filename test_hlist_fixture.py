#!/usr/bin/env python3
"""A classic hierarchical list through accessibility, with the application's own list events.

Prepares tests' hierarchical list fixture with --server, then reads and operates the list only
through the published outline: selection, expansion and collapse of nested groups, and revealing
an item below the visible lines. Each action must run 4D's own list events, recorded by the
fixture's object method. --baseline records the same window without any plugin, component or
helpers; a later --run then requires identical pixels before the first action.
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
FIXTURE = BUILD / "hlist-fixture"
PIXELS = BUILD / "hlist-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "AX bridge hierarchical list"
ON_CLICKED, ON_EXPAND, ON_COLLAPSE, ON_SELECTION_CHANGE = 4, 43, 44, 31


TITLE_BAR = 28


def content_changed_pixels(first, second):
    """Changed pixels below the window's title bar, which AppKit draws."""
    from test_native_messages import rgba
    (size, a), (other, b) = rgba(first), rgba(second)
    if size != other:
        return size[0] * size[1]
    start = TITLE_BAR * size[0] * 4
    return sum(1 for index in range(start, len(a), 4) if a[index:index + 4] != b[index:index + 4])


def scroll_partially(pid, outline, ax):
    """Scroll the list by half a line with a pixel trackpad event, then move the pointer away."""
    import ctypes as c

    class Point(c.Structure):
        _fields_ = [("x", c.c_double), ("y", c.c_double)]
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    graphics.CGEventCreateScrollWheelEvent.restype = c.c_void_p
    graphics.CGEventCreateScrollWheelEvent.argtypes = (c.c_void_p, c.c_uint32, c.c_uint32, c.c_int32)
    graphics.CGEventCreateMouseEvent.restype = c.c_void_p
    graphics.CGEventCreateMouseEvent.argtypes = (c.c_void_p, c.c_uint32, Point, c.c_uint32)
    graphics.CGEventPost.argtypes = (c.c_uint32, c.c_void_p)
    x, y = outline.read("AXPosition"); width, height = outline.read("AXSize")
    for event in (lambda: graphics.CGEventCreateMouseEvent(None, 5, Point(x + width / 2, y + height / 2), 0),
                  lambda: graphics.CGEventCreateScrollWheelEvent(None, 0, 1, -9),
                  lambda: graphics.CGEventCreateMouseEvent(None, 5, Point(x + width + 150, y + height + 60), 0)):
        # Pointer input reaches whatever is under it; post only into the owned window.
        if ax.application(pid).read("AXFrontmost") is not True:
            raise RuntimeError("The fixture lost the foreground; refusing to post input")
        graphics.CGEventPost(0, event())
        time.sleep(0.6)
    time.sleep(1)


def prepare(server, bridge):
    command = [sys.executable, str(ROOT / "prepare_hlist_fixture.py"), "--server", str(server)] + ([] if bridge else ["--no-bridge"])
    subprocess.run(command, check=True)


def events():
    path = FIXTURE / "Resources/events.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()] if path.exists() else []


def launch(args):
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/HList.4DProject"), "--dataless", "--opening-mode",
               "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    if args.intel:
        command = ["/usr/bin/arch", "-x86_64"] + command
    return subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free window for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Navigate and operate the list with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    from test_native_messages import changed_pixels
    architecture = "x86_64" if args.intel else "arm64"
    prepare(args.server, bridge=not args.baseline)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    process = launch(args)
    if vo:
        # Keys reach whatever is frontmost; never post one into another application.
        vo.set_guard(vo.guard_frontmost(process.pid, ax))

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)

    def window():
        for candidate in ax.application(process.pid).read("AXWindows") or []:
            if candidate.read("AXTitle") == TITLE:
                return candidate

    if args.baseline:
        try:
            ax.wait_for(window, "Fixture window", timeout=60)
            front()
            ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
            time.sleep(3)
            (PIXELS).mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            process.terminate(); process.wait(20)
        print("Recorded the plugin-free hierarchical list window")
        return

    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "voiceover": args.voiceover, "checks": [],
              "pluginSHA256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS: " + description, flush=True)

    def outline():
        front()
        pending = [window()] if window() else []
        while pending:
            element = pending.pop(0)
            if element.read("AXRole") == "AXOutline":
                return element
            pending.extend(child for child in element.read("AXChildren") or [] if isinstance(child, ax.Element))

    def rows():
        """Rows by item key, with level, text, disclosure and selection, after pages load."""
        result = {}
        for row in outline().read("AXRows") or []:
            key = row.read("AXIdentifier").split("/")[-1].replace("%3A", ":")
            cell = (row.read("AXChildren") or [None])[0]
            content = (cell.read("AXChildren") or [None])[0] if cell else None
            text = content.read("AXDescription") if content and content.read("AXRole") == "AXDisclosureTriangle" else (content.read("AXValue") if content else None)
            result[key] = {"row": row, "cell": cell, "level": int(row.read("AXDisclosureLevel") or 0), "text": text,
                           "disclosing": row.read("AXDisclosing"), "selected": row.read("AXSelected") is True}
        return result

    def settled(predicate, message, timeout=20):
        return ax.wait_for(lambda: (lambda r: r if predicate(r) else None)(rows()), message, timeout=timeout)

    def receipt():
        return [child.read("AXHelp") for child in window().read("AXChildren") or [] if child.read("AXHelp")]

    def new_events(since, codes, timeout=10):
        limit = time.time() + timeout
        while time.time() < limit:
            found = events()[since:]
            if all(any(e["event"] == code for e in found) for code in codes):
                return found
            time.sleep(0.2)
        return events()[since:]

    def phrase_until(predicate, since, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    def say(key, modifiers):
        front()
        mark = heard.mark()
        vo.key(key, modifiers)
        return mark

    try:
        tree = outline() or ax.wait_for(outline, "The hierarchical list is published as an outline", timeout=60)
        if args.voiceover:
            check(phrase_until(lambda p: "Product catalog" in p, 0, 40), "VoiceOver reaches the list by its label")
            mark = say("down", vo.VO + ("shift",))
            check(phrase_until(lambda p: "Synthesizers" in p and "row 3 of 14" in p and "level 1" in p, mark),
                  "interacting starts on the selected item, with its position and level")
            mark = say("down", vo.VO)
            check(phrase_until(lambda p: p.startswith("Guitars") and "collapsed" in p and "disclosure triangle" in p, mark),
                  "a collapsed group is read with its state and disclosure triangle")
            since = len(events()); mark = say("space", vo.VO)
            found = new_events(since, [ON_EXPAND])
            check(any(e["event"] == ON_EXPAND for e in found) and phrase_until(lambda p: "Guitars: expanded" in p, mark),
                  "VO-Space expands the group through the list's own On Expand and announces it")
            since = len(events()); mark = say("backslash", vo.VO)
            found = new_events(since, [ON_COLLAPSE])
            check(any(e["event"] == ON_COLLAPSE for e in found) and phrase_until(lambda p: "Guitars: collapsed" in p, mark),
                  "VoiceOver's disclosure command collapses it through On Collapse and announces it")
            mark = say("down", vo.VO)
            check(phrase_until(lambda p: p.startswith("Cables") and "row 5 of 14" in p, mark), "VoiceOver moves to the next item")
            since = len(events()); say("space", vo.VO)
            found = new_events(since, [ON_SELECTION_CHANGE])
            check(any(e["event"] == ON_SELECTION_CHANGE and e["selected"] == 30 for e in found), "VO-Space selects the item through the list's own events")
            # Only the fixture's own speech is recorded; other applications are not.
            run = [p for _, p in heard.since(0)]
            report["speech"] = run[next((i for i, p in enumerate(run) if "Product catalog" in p), len(run)):]
            report["passed"] = True
            print(f"PASS: {len(report['checks'])} hierarchical list checks ({architecture}, {report['mode']}, VoiceOver)")
            return
        check(tree.read("AXRole") == "AXOutline" and tree.read("AXDescription") == "Product catalog", "the list is an outline labeled by its help tip")
        current = settled(lambda r: all(v["text"] not in (None, "", "Loading") for v in r.values()), "Item text loads")
        expected = ["i:1", "i:11", "i:12", "i:2"] + [f"i:{30 + i}" for i in range(10)]
        check(list(current) == expected, "visible items appear in 4D's order, collapsed children omitted")
        check([current[k]["level"] for k in ("i:1", "i:11", "i:12", "i:2", "i:30")] == [0, 1, 1, 0, 0], "each item reports its depth")
        check(current["i:1"]["disclosing"] is True and current["i:11"]["disclosing"] is False and current["i:2"]["disclosing"] is False,
              "expanded and collapsed groups report their state")
        check(current["i:12"]["selected"] and current["i:12"]["text"] == "Synthesizers" and sum(v["selected"] for v in current.values()) == 1,
              "the list's own selection is reported")
        reference = PIXELS / f"baseline-{architecture}.png"
        if reference.exists():
            front()
            ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
            time.sleep(1.5)
            ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
            changed = changed_pixels(reference, PIXELS / f"bridge-{architecture}.png")
            content = content_changed_pixels(reference, PIXELS / f"bridge-{architecture}.png")
            report["changedPixels"] = {"window": changed, "belowTitleBar": content}
            # Under Rosetta, AppKit's own window-title text can differ by one level of
            # antialiasing between packages; the 4D form below it must not change.
            check(content == 0, "the form is pixel-identical to the plugin-free form")

        # A trackpad can leave the list part of a line scrolled, which 4D reports
        # rounded to a whole line. Selection must still reach the requested item.
        scroll_partially(process.pid, tree, ax)
        since = len(events())
        check(rows()["i:33"]["row"].set_boolean("AXSelected", True) == 0, "selecting Straps in a partly scrolled list is accepted")
        found = new_events(since, [ON_SELECTION_CHANGE])
        check(any(e["event"] == ON_SELECTION_CHANGE and e["selected"] == 33 for e in found), "a partly scrolled list selects exactly the requested item")
        current = settled(lambda r: r["i:33"]["selected"], "Straps selected")
        since = len(events())
        check(current["i:31"]["row"].set_boolean("AXSelected", True) == 0, "selecting Stands is accepted through accessibility")
        found = new_events(since, [ON_SELECTION_CHANGE, ON_CLICKED])
        check(any(e["event"] == ON_SELECTION_CHANGE and e["selected"] == 31 for e in found) and any(e["event"] == ON_CLICKED for e in found),
              "the list's own selection and click events run for Stands")
        check(settled(lambda r: r["i:31"]["selected"] and not r["i:12"]["selected"], "Selection published")["i:31"]["selected"], "the new selection is published")
        check(found[-1].get("compiled") is args.compiled, "4D runs in the requested " + report["mode"] + " mode")

        since = len(events())
        check(rows()["i:2"]["row"].set_boolean("AXDisclosing", True) == 0, "expanding Guitars is accepted through accessibility")
        found = new_events(since, [ON_EXPAND])
        check(any(e["event"] == ON_EXPAND and 2 in e["expanded"] for e in found), "the list's own On Expand event runs for Guitars")
        current = settled(lambda r: "i:21" in r and "i:22" in r, "Children published")
        check(list(current)[4:6] == ["i:21", "i:22"] and current["i:21"]["level"] == 1 and current["i:2"]["disclosing"] is True,
              "Guitars' children appear beneath it at the next level")

        since = len(events())
        check(rows()["i:2"]["row"].set_boolean("AXDisclosing", True) == 0, "expanding an expanded group is accepted")
        time.sleep(2)
        check(not any(e["event"] in (ON_EXPAND, ON_COLLAPSE, ON_CLICKED) for e in events()[since:]) and "List item already expanded" in receipt(),
              "an expanded group is left alone, without a click or event")

        since = len(events())
        check(rows()["i:11"]["row"].set_boolean("AXDisclosing", True) == 0, "expanding the nested Keyboards group is accepted")
        new_events(since, [ON_EXPAND])
        current = settled(lambda r: "i:111" in r, "Nested children published")
        check(current["i:111"]["level"] == 2 and current["i:112"]["level"] == 2, "a nested group's children appear two levels deep")

        since = len(events())
        check(rows()["i:2"]["row"].set_boolean("AXDisclosing", False) == 0, "collapsing Guitars is accepted through accessibility")
        found = new_events(since, [ON_COLLAPSE])
        check(any(e["event"] == ON_COLLAPSE for e in found), "the list's own On Collapse event runs")
        current = settled(lambda r: "i:21" not in r and r["i:2"]["disclosing"] is False, "Children removed")
        check("i:22" not in current, "a collapsed group's children leave the outline")

        target = current["i:39"]
        before = target["cell"].read("AXPosition")
        check(target["cell"].perform("AXScrollToVisible") == 0, "revealing Headphones, below the visible lines, is accepted")
        ax.wait_for(lambda: "List item revealed" in receipt() or "List item already visible" in receipt(), "Reveal confirmed", timeout=10)
        after = rows()["i:39"]["cell"].read("AXPosition")
        check(after[1] < before[1], "the list scrolls Headphones into view")
        since = len(events())
        check(rows()["i:39"]["row"].set_boolean("AXSelected", True) == 0, "selecting the revealed item is accepted")
        found = new_events(since, [ON_SELECTION_CHANGE])
        check(any(e["event"] == ON_SELECTION_CHANGE and e["selected"] == 39 for e in found), "the click after scrolling selects exactly Headphones")
        report["passed"] = True
    finally:
        if heard:
            heard.stop()
        if vo:
            vo.stop()
        if process.poll() is None:
            process.terminate()
            process.wait(20)
        name = "hlist-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} hierarchical list checks ({architecture}, {report['mode']})")


if __name__ == "__main__":
    main()
