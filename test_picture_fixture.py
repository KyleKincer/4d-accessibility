#!/usr/bin/env python3
"""4D's picture-based controls through accessibility, with the application's own events.

Prepares the picture-controls fixture with --server. Button grids are published as groups of
cell buttons, labeled from configuration or numbered, and each press must run the grid's own
On Clicked with that cell's value. A picture button advances its state; a spinner is a progress
indicator; a picture popup menu is a popup whose choices the plugin offers in a menu of its own,
each chosen through 4D's palette and the control's own On Clicked; a splitter is a splitter. --baseline records the same
window without any plugin, component or helpers; a later --run then requires an unchanged form.
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
FIXTURE = BUILD / "picture-fixture"
PIXELS = BUILD / "picture-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "AX bridge picture controls"
ON_CLICKED = 4
TITLE_BAR = 28


def events():
    path = FIXTURE / "Resources/events.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()] if path.exists() else []


# The spinner animates continuously, so its rectangle differs between any two captures.
ANIMATED = [(260, 90 + TITLE_BAR, 292, 122 + TITLE_BAR)]


def content_changed_pixels(first, second):
    """Changed pixels below the window's title bar, which AppKit draws, outside animated controls."""
    from test_native_messages import rgba
    (size, a), (other, b) = rgba(first), rgba(second)
    if size != other:
        return size[0] * size[1]
    width = size[0]
    changed = 0
    for index in range(TITLE_BAR * width * 4, len(a), 4):
        if a[index:index + 4] != b[index:index + 4]:
            x, y = (index // 4) % width, (index // 4) // width
            if not any(left <= x < right and top <= y < bottom for left, top, right, bottom in ANIMATED):
                changed += 1
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free window for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Navigate and press a cell with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_picture_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/Pictures.4DProject"), "--dataless", "--opening-mode",
               "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
            ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
            time.sleep(3)
            PIXELS.mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            stop()
        print("Recorded the plugin-free picture controls window")
        return

    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "voiceover": args.voiceover,
              "checks": [], "pluginSHA256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS: " + description, flush=True)

    def root():
        front()
        current = window()
        return next((child for child in current.read("AXChildren") or [] if (child.read("AXIdentifier") or "").startswith("axb/")), None) if current else None

    def published():
        """Published elements by object name, with button-grid cells under their group."""
        result = {}
        for element in root().read("AXChildren") or []:
            name = (element.read("AXIdentifier") or "").split("/")[-1]
            result[name] = {"element": element, "role": element.read("AXRole"), "label": element.read("AXDescription"), "value": element.read("AXValue"),
                            "cells": [{"element": cell, "label": cell.read("AXDescription"), "role": cell.read("AXRole"),
                                       "position": cell.read("AXPosition"), "identifier": cell.read("AXIdentifier")}
                                      for cell in element.read("AXChildren") or []]}
        return result

    def pressed(element, name, timeout=10):
        # The bridge runs one action at a time; wait for the previous one to finish.
        ax.wait_for(lambda: root().read("AXHelp") not in ("Action queued", "Waiting for the application to complete the action"), "Bridge idle", timeout=10)
        since = len(events())
        if ax.application(process.pid).read("AXFrontmost") is not True:
            raise RuntimeError("The fixture lost the foreground; refusing to press")
        assert element.press() == 0
        limit = time.time() + timeout
        while time.time() < limit:
            found = [e for e in events()[since:] if e["object"] == name and e["event"] == ON_CLICKED]
            if found:
                return found[-1]
            time.sleep(0.2)
        return None

    def phrase_until(predicate, since, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    try:
        ax.wait_for(root, "The form is published", timeout=60)
        controls = ax.wait_for(lambda: (lambda p: p if "Align" in p and len(p["Align"]["cells"]) == 3 else None)(published()), "Button grid cells", timeout=20)
        align, palette = controls["Align"], controls["Palette"]
        check(align["role"] == "AXGroup" and align["label"] == "Alignment", "a button grid is a group labeled by its help tip")
        check([c["label"] for c in align["cells"]] == ["Left", "Center", "Right"] and all(c["role"] == "AXButton" for c in align["cells"]),
              "its cells are buttons labeled from configuration, in 4D's cell order")
        xs = [c["position"][0] for c in align["cells"]]
        check(xs == sorted(xs) and len({c["position"][1] for c in align["cells"]}) == 1, "a 3-column, 1-row grid lays its cells out in one row")
        check([c["identifier"].split("/")[-2:] for c in align["cells"]] == [["cell", "1"], ["cell", "2"], ["cell", "3"]], "each cell has a stable path")
        check([c["label"] for c in palette["cells"]] == ["Palette 1", "Palette 2", "Palette 3", "Palette 4"], "an unlabeled grid's cells are numbered after the grid")
        p = [c["position"] for c in palette["cells"]]
        check(p[0][1] == p[1][1] < p[2][1] == p[3][1] and p[0][0] == p[2][0] < p[1][0] == p[3][0], "a 2 by 2 grid's cells are numbered row by row")
        check(controls["Mode"]["role"] == "AXButton" and controls["Mode"]["label"] == "Mode", "a picture button is a button")
        check(controls["Busy"]["role"] == "AXProgressIndicator" and controls["Busy"]["label"] == "Loading", "a spinner is a progress indicator")
        color = controls["Color"]
        check(color["role"] == "AXPopUpButton" and color["label"] == "Color" and color["value"] == "Blue",
              "a picture popup menu is a popup labeled by its help tip, showing its chosen cell's label")
        check(controls["Divider"]["role"] == "AXSplitter", "a splitter is a splitter")
        reference = PIXELS / f"baseline-{architecture}.png"
        if reference.exists() and not args.voiceover:
            front()
            ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
            time.sleep(1.5)
            ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
            changed = content_changed_pixels(reference, PIXELS / f"bridge-{architecture}.png")
            report["changedPixels"] = changed
            check(changed == 0, "the form is pixel-identical to the plugin-free form")
        if args.voiceover:
            check(phrase_until(lambda ph: "AX bridge picture controls" in ph, 0, 40), "VoiceOver reaches the form")
            # Find the alignment grid with VoiceOver's own navigation, then press a cell.
            # VoiceOver starts on the default button, last in reading order.
            for _ in range(10):
                front(); mark = heard.mark(); vo.key("left", vo.VO)
                time.sleep(1.5)
                if any(ph.startswith("Alignment") for _, ph in heard.since(mark)):
                    break
            check(any(ph.startswith("Alignment group") for _, ph in heard.since(0)), "VoiceOver reads the grid as a labeled group")
            front(); mark = heard.mark(); vo.key("down", vo.VO + ("shift",))
            check(phrase_until(lambda ph: "Left button" in ph, mark), "interacting with the grid reads its first cell")
            front(); mark = heard.mark(); vo.key("right", vo.VO)
            check(phrase_until(lambda ph: "Center button" in ph, mark), "VoiceOver moves to the next cell")
            since = len(events()); front(); vo.key("space", vo.VO)
            limit = time.time() + 10
            while time.time() < limit and not any(e["object"] == "Align" and e["event"] == ON_CLICKED for e in events()[since:]):
                time.sleep(0.2)
            found = [e for e in events()[since:] if e["object"] == "Align" and e["event"] == ON_CLICKED]
            check(found and found[-1]["value"] == 2, "VO-Space presses the cell through the grid's own On Clicked")
            # Leave the grid, find the color menu, and choose its last cell from the keyboard.
            front(); vo.key("up", vo.VO + ("shift",))
            for _ in range(10):
                front(); mark = heard.mark(); vo.key("right", vo.VO)
                time.sleep(1.5)
                if any("Color pop up button" in ph for _, ph in heard.since(mark)):
                    break
            # Never press with the cursor anywhere else: Done would close the form.
            check(any("Blue" in ph and "Color pop up button" in ph for _, ph in heard.since(mark)), "VoiceOver reads the picture popup as a labeled popup with its chosen cell")
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            check(phrase_until(lambda ph: "Blue" in ph, mark), "VO-Space opens its choices at the current one")
            front(); mark = heard.mark(); vo.key("down"); vo.key("down")
            check(phrase_until(lambda ph: "Violet" in ph, mark), "the arrow keys move through the labeled choices")
            since = len(events()); front(); vo.key("return")
            limit = time.time() + 10
            while time.time() < limit and not any(e["object"] == "Color" and e["event"] == ON_CLICKED for e in events()[since:]):
                time.sleep(0.2)
            found = [e for e in events()[since:] if e["object"] == "Color" and e["event"] == ON_CLICKED]
            check(found and found[-1]["value"] == 3, "Return chooses the cell through the control's own On Clicked")
            run = [ph for _, ph in heard.since(0)]
            report["speech"] = run[next((i for i, ph in enumerate(run) if "AX bridge picture controls" in ph), len(run)):]
        else:
            event = pressed(align["cells"][2]["element"], "Align")
            check(event and event["value"] == 3, "pressing Right runs the grid's own On Clicked with value 3")
            event = pressed(align["cells"][0]["element"], "Align")
            check(event and event["value"] == 1, "pressing Left runs it with value 1")
            event = pressed(palette["cells"][2]["element"], "Palette")
            check(event and event["value"] == 3, "pressing the bottom-left cell of a 2 by 2 grid gives value 3" + ("" if event and event["value"] == 3 else f" (got {event}, {root().read('AXHelp')})"))
            check(event.get("compiled") is args.compiled, "4D runs in the requested " + report["mode"] + " mode")
            event = pressed(controls["Mode"]["element"], "Mode")
            check(event and event["value"] == 2, "pressing the picture button advances its state")
            # Pressing the popup offers its labeled cells in a native menu.
            ax.wait_for(lambda: root().read("AXHelp") not in ("Action queued", "Waiting for the application to complete the action"), "Bridge idle", timeout=10)
            front()
            assert color["element"].press() == 0
            menu = ax.wait_for(lambda: (lambda f: f if f and f.read("AXRole") == "AXMenu" else None)(ax.application(process.pid).read("AXFocusedUIElement")),
                               "The choices menu", timeout=10)
            items = menu.read("AXChildren") or []
            check([i.read("AXTitle") for i in items] == ["Blue", "Indigo", "Violet"], "its menu lists every cell's label in 4D's cell order")
            check([bool(i.read("AXMenuItemMarkChar")) for i in items] == [True, False, False], "the chosen cell is marked")
            check([i.read("AXSelected") is True for i in items] == [True, False, False], "the menu opens with the chosen cell highlighted, like a popup button")
            since = len(events())
            if ax.application(process.pid).read("AXFrontmost") is not True:
                raise RuntimeError("The fixture lost the foreground; refusing to choose")
            assert items[2].press() == 0
            limit = time.time() + 10
            while time.time() < limit and not any(e["object"] == "Color" and e["event"] == ON_CLICKED for e in events()[since:]):
                time.sleep(0.2)
            found = [e for e in events()[since:] if e["object"] == "Color" and e["event"] == ON_CLICKED]
            check(len(found) == 1 and found[0]["value"] == 3, "choosing Violet runs the control's own On Clicked once, with value 3")
            check(ax.wait_for(lambda: published()["Color"]["value"] == "Violet", "Chosen value", timeout=10), "the popup then shows the chosen cell")
            focused = ax.application(process.pid).read("AXFocusedUIElement")
            check(not focused or focused.read("AXRole") != "AXMenu", "4D's palette closes after the choice")
        report["passed"] = True
    finally:
        if heard:
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "picture-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} picture control checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
