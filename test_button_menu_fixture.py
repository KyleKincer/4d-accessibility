#!/usr/bin/env python3
"""Buttons with pop-up menus through accessibility and VoiceOver.

Prepares the button menu fixture with --server. A button with a linked menu, and a
separated one whose style draws its arrow, must offer Show Menu. It opens the menu the
button's own On Alternative Click shows, which stays open as a native menu; choosing an
item returns it to the method, and dismissing returns nothing. A separated button's
press still runs its On Clicked. A separated menu without a drawn arrow is reported.
--baseline records the window without any plugin, component or helpers; a later --run
then requires an unchanged form before the first action.
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
FIXTURE = BUILD / "button-menu-fixture"
PIXELS = BUILD / "button-menu-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "AX bridge button menus"
ALTERNATIVE_CLICK, CLICKED = 38, 4


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free window for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Open and choose from a menu with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    from test_native_messages import changed_pixels
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_button_menu_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
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
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/ButtonMenus.4DProject"), "--dataless", "--opening-mode",
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
        for candidate in ax.application(process.pid).read("AXWindows") or []:
            if candidate.read("AXTitle") == TITLE:
                return candidate

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
        print("Recorded the plugin-free button menu window")
        return

    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "voiceover": args.voiceover,
              "checks": [], "pluginSHA256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS: " + description, flush=True)

    def root():
        current = window()
        return next((child for child in current.read("AXChildren") or [] if (child.read("AXIdentifier") or "").startswith("axb/")), None) if current else None

    def button(title):
        return next((child for child in root().read("AXChildren") or [] if child.read("AXRole") == "AXButton" and title in (child.read("AXTitle"), child.read("AXDescription"))), None)

    def menu():
        """The pop-up menu 4D shows, outside the menu bar."""
        def walk(element, depth=0):
            if depth > 4 or element.read("AXRole") == "AXMenuBar":
                return None
            if element.read("AXRole") == "AXMenu":
                return element
            for child in element.read("AXChildren") or []:
                found = walk(child, depth + 1)
                if found:
                    return found
        return walk(ax.application(process.pid))

    def items():
        current = menu()
        return [item for item in current.read("AXChildren") or [] if item.read("AXTitle")] if current else []

    def events():
        path = FIXTURE / "Resources/events.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()] if path.exists() else []

    def since(count, key):
        return [e for e in events()[count:] if key in e]

    def idle():
        ax.wait_for(lambda: root().read("AXHelp") not in ("Action queued", "Waiting for the application to complete the action"), "Bridge idle", timeout=10)

    def phrase_until(predicate, since_mark, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since_mark):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since_mark)][-5:]))

    try:
        ax.wait_for(root, "The form is published", timeout=60)
        front()
        export = ax.wait_for(lambda: button("Export"), "Export is published", timeout=20)
        search, plain = button("Search"), button("Plain")
        check("AXShowMenu" in export.actions() and "AXPress" in export.actions(), "a button with a linked menu offers Show Menu")
        check("AXShowMenu" in search.actions() and "AXPress" in search.actions(), "a separated menu whose arrow is drawn offers Show Menu beside Press")
        check("AXShowMenu" not in plain.actions() and "AXPress" in plain.actions(), "a separated menu without a drawn arrow offers only Press")
        reference = PIXELS / f"baseline-{architecture}.png"
        if reference.exists() and not args.voiceover:
            time.sleep(1.5)
            ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
            changed = changed_pixels(reference, PIXELS / f"bridge-{architecture}.png")
            report["changedPixels"] = changed
            check(changed == 0, "the form is pixel-identical to the plugin-free form")
        if args.voiceover:
            reached = phrase_until(lambda ph: TITLE in ph, 0, 40)
            check(reached, "VoiceOver reaches the form")
            # Export has the initial focus; otherwise move to it.
            heardExport = reached if "Export" in reached else None
            for _ in range(0 if heardExport else 6):
                front(); mark = heard.mark(); vo.key("right", vo.VO)
                phrase = phrase_until(lambda ph: ph.strip() != "", mark)
                if "Export" in phrase:
                    heardExport = phrase
                    break
            check(heardExport and "button" in heardExport, "VoiceOver reads the Export button")
            # A linked button's click is its menu: VO-Space opens it.
            count = len(events())
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            ax.wait_for(lambda: [i.read("AXTitle") for i in items()] == ["PDF", "CSV"], "The menu's items", timeout=10)
            check(phrase_until(lambda ph: "PDF" in ph or "menu" in ph.lower(), mark), "VO-Space opens the linked button's own menu")
            front(); mark = heard.mark(); vo.key("down"); vo.key("down")
            check(phrase_until(lambda ph: "CSV" in ph, mark), "VoiceOver reads the menu's items")
            front(); vo.key("return")
            ax.wait_for(lambda: since(count, "choice"), "The choice", timeout=10)
            check(since(count, "choice")[0]["choice"] == "csv" and since(count, "event")[0]["event"] == ALTERNATIVE_CLICK,
                  "Return chooses the item, and the button's On Alternative Click receives it")
            # A separated button's menu is its Show Menu action, in VoiceOver's actions menu.
            ax.wait_for(lambda: menu() is None, "The menu closed", timeout=10)
            front(); mark = heard.mark(); vo.key("right", vo.VO)
            check(phrase_until(lambda ph: "Search" in ph, mark), "VoiceOver moves to the separated Search button")
            count = len(events())
            front(); mark = heard.mark(); vo.key("space", vo.VO + ("cmd",)); time.sleep(1)
            actions = [phrase_until(lambda ph: ph.strip() != "", mark)]
            for _ in range(4):
                if "show menu" in actions[-1].lower():
                    break
                front(); mark = heard.mark(); vo.key("down")
                actions.append(phrase_until(lambda ph: ph.strip() != "", mark))
            report["actionsMenu"] = actions
            check("show menu" in actions[-1].lower(), "VoiceOver's actions menu offers Show menu")
            front(); vo.key("return")
            ax.wait_for(lambda: [i.read("AXTitle") for i in items()] == ["Exact", "Fuzzy"], "The separated button's menu", timeout=10)
            front(); mark = heard.mark(); vo.key("down"); vo.key("down")
            check(phrase_until(lambda ph: "Fuzzy" in ph, mark), "VoiceOver reads the separated button's menu")
            front(); vo.key("return")
            ax.wait_for(lambda: since(count, "choice"), "The choice", timeout=10)
            check(since(count, "choice")[0]["choice"] == "fuzzy" and [e["event"] for e in since(count, "event")] == [ALTERNATIVE_CLICK],
                  "choosing from it reaches the separated button's On Alternative Click, not its On Clicked")
        else:
            count = len(events())
            check(export.perform("AXShowMenu") == 0, "Show Menu is accepted")
            ax.wait_for(lambda: [i.read("AXTitle") for i in items()] == ["PDF", "CSV"], "The menu's items", timeout=10)
            check(since(count, "event") == [{"object": "Export", "event": ALTERNATIVE_CLICK, "runId": run_id, "compiled": args.compiled}],
                  "Show Menu runs the button's On Alternative Click once, and its menu stays open")
            csv = next(i for i in items() if i.read("AXTitle") == "CSV")
            check(csv.perform("AXPress") == 0, "a menu item is pressed through accessibility")
            ax.wait_for(lambda: since(count, "choice"), "The choice", timeout=10)
            check(since(count, "choice")[0]["choice"] == "csv" and menu() is None, "the method receives the chosen item and the menu closes")
            idle()
            check(root().read("AXHelp") == "Activation dispatched through the control's normal event path", "the bridge reports the dispatch")
            diagnostics = next((e["diagnostics"] for e in events() if "diagnostics" in e), None)
            issues = {(i.get("object"), i.get("reason")) for i in (diagnostics or {}).get("issues", [])}
            check(("Plain", "buttonMenuArrowPending") in issues, "the separated menu without a drawn arrow is reported as unsupported")
            count = len(events())
            check(search.perform("AXShowMenu") == 0, "Show Menu on a separated button is accepted")
            ax.wait_for(lambda: [i.read("AXTitle") for i in items()] == ["Exact", "Fuzzy"], "The separated button's menu", timeout=10)
            check(menu().perform("AXCancel") == 0, "the open menu can be dismissed")
            ax.wait_for(lambda: since(count, "choice"), "The dismissal", timeout=10)
            check(since(count, "event")[0]["event"] == ALTERNATIVE_CLICK and since(count, "choice")[0]["choice"] == "" and menu() is None,
                  "a separated button's arrow runs On Alternative Click; dismissing returns no choice")
            idle()
            count = len(events())
            check(search.perform("AXPress") == 0, "pressing the separated button is accepted")
            ax.wait_for(lambda: since(count, "event"), "On Clicked", timeout=10)
            time.sleep(1)
            check([e["event"] for e in since(count, "event")] == [CLICKED] and menu() is None, "pressing a separated button runs its On Clicked, not its menu")
        report["passed"] = True
    finally:
        if heard:
            report["speech"] = [ph for _, ph in heard.since(0)]
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "button-menu-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} button menu checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
