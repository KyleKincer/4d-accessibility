#!/usr/bin/env python3
"""A 4D splitter through accessibility: position, adjustment and VoiceOver.

Prepares the splitter fixture with --server. The splitter must be published as a vertical
splitter with its position, adjustable by one step in each direction or to a written position,
with 4D's own splitter handling resizing the attached pane and keeping its limits. --baseline
records the same window without any plugin, component or helpers; a later --run then requires
an unchanged form before the first adjustment.
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
FIXTURE = BUILD / "splitter-fixture"
PIXELS = BUILD / "splitter-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "AX bridge splitter"
TITLE_BAR = 28


# Notes has the initial focus, and its insertion point blinks at the start of its text.
CARET = (18, 20 + TITLE_BAR - 4, 24, 20 + TITLE_BAR + 24)


def content_changed_pixels(first, second):
    """Changed pixels below the window's title bar, which AppKit draws, outside the blinking caret."""
    from test_native_messages import rgba
    (size, a), (other, b) = rgba(first), rgba(second)
    if size != other:
        return size[0] * size[1]
    width = size[0]
    left, top, right, bottom = CARET
    return sum(1 for index in range(TITLE_BAR * width * 4, len(a), 4) if a[index:index + 4] != b[index:index + 4]
               and not (left <= (index // 4) % width < right and top <= (index // 4) // width < bottom))


def set_number(ax, element, name, number):
    """Write a numeric attribute, as VoiceOver does for a splitter's position."""
    create = ax.signature(ax.CF, "CFNumberCreate", c.c_void_p, c.c_void_p, c.c_int, c.c_void_p)
    value = c.c_double(number)
    cf_number = create(None, 13, c.byref(value))
    key = ax.make_string(None, name.encode(), 0x08000100)
    try:
        return ax.set_attribute(element.pointer, key, cf_number)
    finally:
        ax.release(cf_number)
        ax.release(key)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free window for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Move the splitter with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_splitter_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
    if not (args.run or args.baseline):
        return
    ax.require_test_input()
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/Splitter.4DProject"), "--dataless", "--opening-mode",
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
        print("Recorded the plugin-free splitter window")
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

    def element(role):
        return next((child for child in root().read("AXChildren") or [] if child.read("AXRole") == role), None)

    def pane_width():
        # 4D can shrink the pane to nothing, and an empty object is not published.
        pane = element("AXTextField")
        return pane.read("AXSize")[0] if pane else 0

    def idle():
        ax.wait_for(lambda: root().read("AXHelp") not in ("Action queued", "Waiting for the application to complete the action"), "Bridge idle", timeout=10)

    def position_after(action):
        """Run an action, wait for its receipt, and return the splitter position and pane width."""
        idle()
        if ax.application(process.pid).read("AXFrontmost") is not True:
            raise RuntimeError("The fixture lost the foreground; refusing to act")
        assert action() == 0
        idle()
        time.sleep(0.5)
        return element("AXSplitter").read("AXValue"), pane_width(), root().read("AXHelp")

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
        splitter = ax.wait_for(lambda: element("AXSplitter"), "The splitter is published", timeout=20)
        check(splitter.read("AXOrientation") == "AXVerticalOrientation" and splitter.read("AXDescription") == "Pane divider",
              "a tall splitter is a vertical splitter labeled by its help tip")
        check(splitter.read("AXValue") == 226 and splitter.read("AXMinValue") == 0 and splitter.read("AXMaxValue") == 520,
              "its value is its position within the window's width")
        check({"AXIncrement", "AXDecrement"} <= set(splitter.actions()) and splitter.is_settable("AXValue"), "it can be stepped or moved to a position")
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
            check(phrase_until(lambda ph: "AX bridge splitter" in ph, 0, 40), "VoiceOver reaches the form")
            front(); mark = heard.mark(); vo.key("right", vo.VO)
            check(phrase_until(lambda ph: "vertical splitter" in ph and "Pane divider" in ph, mark), "VoiceOver reads the splitter by its label")
            front(); mark = heard.mark(); vo.key("down", vo.VO + ("shift",))
            check(phrase_until(lambda ph: "To change the splitter position" in ph, mark), "interacting offers VoiceOver's splitter adjustment")
            # VoiceOver's hint names VO-Right and VO-Left for moving the splitter.
            front(); vo.key("right", vo.VO); idle()
            moved = element("AXSplitter").read("AXValue")
            check(moved > 226 and pane_width() == 200 + (moved - 226), "VO-Right moves the splitter and resizes the pane with it")
            front(); vo.key("left", vo.VO); idle()
            check(element("AXSplitter").read("AXValue") < moved, "VO-Left moves it back")
            run = [ph for _, ph in heard.since(0)]
            report["speech"] = run[next((i for i, ph in enumerate(run) if "AX bridge splitter" in ph), len(run)):]
        else:
            value, width, receipt = position_after(lambda: element("AXSplitter").perform("AXIncrement"))
            check(value == 236 and width == 210 and receipt == "Splitter moved", "an increment moves the splitter one step and widens the pane by the same amount")
            value, width, receipt = position_after(lambda: element("AXSplitter").perform("AXDecrement"))
            check(value == 226 and width == 200, "a decrement moves it back")
            value, width, receipt = position_after(lambda: set_number(ax, element("AXSplitter"), "AXValue", 300))
            check(value == 300 and width == 274, "writing a position moves the splitter there through 4D's splitter handling")
            value, width, receipt = position_after(lambda: set_number(ax, element("AXSplitter"), "AXValue", 300))
            check(value == 300 and receipt == "Splitter already at that position", "writing the current position changes nothing")
            value, width, receipt = position_after(lambda: set_number(ax, element("AXSplitter"), "AXValue", -500))
            # The pane starts at 20 and keeps a 6-point gap; 4D lets it shrink to nothing.
            check(value == 26 and width == 0, "a position past its limit stops where 4D's own limit holds it")
            report["limit"] = value
        report["passed"] = True
    finally:
        if heard:
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "splitter-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} splitter checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
