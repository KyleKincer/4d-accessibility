#!/usr/bin/env python3
"""4D's Progress component windows through accessibility and VoiceOver.

Prepares the progress fixture with --server. Each progress must be published as an
indicator labelled with its title and valued by its progress, with its message and its
Stop button; an indeterminate progress has no value. Advancing the progress must update
the published value, and pressing Stop must reach the component, as Progress Stopped
reports. --baseline records the windows without any plugin, component or helpers; a later
--run then requires them unchanged.
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
FIXTURE = BUILD / "progress-fixture"
PIXELS = BUILD / "progress-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")


def changed_outside(first, second, excluded):
    """Changed pixels outside the excluded window rectangles (left, top, right, bottom)."""
    from test_native_messages import rgba
    (size, a), (other, b) = rgba(first), rgba(second)
    if size != other:
        return size[0] * size[1]
    width = size[0]
    return sum(1 for index in range(0, len(a), 4) if a[index:index + 4] != b[index:index + 4] and
               not any(left <= (index // 4) % width < right and top <= (index // 4) // width < bottom for left, top, right, bottom in excluded))


def park_pointer(pid, window, ax):
    """Move the pointer just below the window when it is over it, so no control is drawn hovered.
    A plain move, posted only while the fixture is frontmost."""
    import ctypes as c

    class Point(c.Structure):
        _fields_ = [("x", c.c_double), ("y", c.c_double)]
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    graphics.CGEventCreate.restype = c.c_void_p
    graphics.CGEventCreate.argtypes = (c.c_void_p,)
    graphics.CGEventGetLocation.restype = Point
    graphics.CGEventGetLocation.argtypes = (c.c_void_p,)
    graphics.CGEventCreateMouseEvent.restype = c.c_void_p
    graphics.CGEventCreateMouseEvent.argtypes = (c.c_void_p, c.c_uint32, Point, c.c_uint32)
    graphics.CGEventPost.argtypes = (c.c_uint32, c.c_void_p)
    current = graphics.CGEventCreate(None)
    pointer = graphics.CGEventGetLocation(current)
    ax.release(current)
    (x, y), (width, height) = window.read("AXPosition"), window.read("AXSize")
    if not (x - 20 <= pointer.x <= x + width + 20 and y - 20 <= pointer.y <= y + height + 20):
        return
    if ax.application(pid).read("AXFrontmost") is not True:
        raise RuntimeError("The fixture lost the foreground; refusing to post input")
    move = graphics.CGEventCreateMouseEvent(None, 5, Point(x + width / 2, y + height + 60), 0)
    graphics.CGEventPost(0, move)
    ax.release(move)
    time.sleep(0.8)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free windows for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Read and stop the progress with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_progress_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
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
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/Progress.4DProject"), "--dataless", "--opening-mode",
               "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if vo:
        # Keys reach whatever is frontmost; never post one into another application.
        vo.set_guard(vo.guard_frontmost(process.pid, ax))

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)

    def windows():
        return [w for w in ax.application(process.pid).read("AXWindows") or [] if w.read("AXRole") == "AXWindow"]

    def published():
        """Every published progress element, by identifier, across the component's windows."""
        found = {}
        for window in windows():
            for child in window.read("AXChildren") or []:
                identifier = child.read("AXIdentifier") or ""
                if identifier.startswith("axb/progress/"):
                    found[identifier] = child
        return found

    def stop():
        (FIXTURE / "Resources/stop.txt").write_text("1")
        try:
            process.wait(20)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(10)

    def capture(name):
        """Each progress window, top to bottom."""
        front()
        ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
        for window in windows():
            park_pointer(process.pid, window, ax)
        time.sleep(1.5)
        PIXELS.mkdir(parents=True, exist_ok=True)
        ordered = sorted(windows(), key=lambda w: w.read("AXPosition")[1])
        paths = []
        for index, window in enumerate(ordered):
            path = PIXELS / f"{name}-{architecture}-{index + 1}.png"
            ax.capture_window(process.pid, path, include_shadow=False, title=window.read("AXTitle") or "")
            paths.append(path)
        return paths

    if args.baseline:
        try:
            ax.wait_for(lambda: len(windows()) >= 1, "Progress window", timeout=60)
            time.sleep(3)
            capture("baseline")
        finally:
            stop()
        print("Recorded the plugin-free progress windows")
        return

    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": architecture, "voiceover": args.voiceover,
              "checks": [], "pluginSHA256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")}

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS: " + description, flush=True)

    def events():
        path = FIXTURE / "Resources/events.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()] if path.exists() else []

    def phrase_until(predicate, since, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    try:
        ax.wait_for(lambda: {"axb/progress/1/progress", "axb/progress/1/stop"} <= set(published()) and
                    published()["axb/progress/1/progress"].read("AXDescription") == "Importing orders", "The progress is published", timeout=60)
        if not args.voiceover:
            references = sorted(PIXELS.glob(f"baseline-{architecture}-*.png"))
            if references:
                paths = capture("bridge")
                # An indeterminate bar animates; compare everything else in its window.
                (window,) = windows()
                (wx, wy), moving = window.read("AXPosition"), []
                for element in published().values():
                    if element.read("AXRole") == "AXProgressIndicator" and element.read("AXValue") is None:
                        (x, y), (w, h) = element.read("AXPosition"), element.read("AXSize")
                        moving.append((int(x - wx), int(y - wy), int(x - wx + w + 1), int(y - wy + h + 1)))
                report["animatedExcluded"] = moving
                changed = [changed_outside(a, b, moving) for a, b in zip(references, paths)] if len(paths) == len(references) else [-1]
                report["changedPixels"] = changed
                check(changed and all(count == 0 for count in changed), "the progress window is pixel-identical to the plugin-free window, apart from the indeterminate bar's animation")
        elements = published()
        importing = elements["axb/progress/1/progress"]
        check(importing.read("AXRole") == "AXProgressIndicator" and importing.read("AXValue") == 30 and
              importing.read("AXMinValue") == 0 and importing.read("AXMaxValue") == 100,
              "the determinate progress is an indicator labelled with its title, at its progress in percent")
        message = elements.get("axb/progress/1/message")
        check(message is not None and message.read("AXRole") == "AXStaticText" and message.read("AXValue") == "Order 3 of 10", "its message is published as text")
        button = elements["axb/progress/1/stop"]
        check(button.read("AXRole") == "AXButton" and button.read("AXDescription") == "Stop" and "AXPress" in button.actions(), "its Stop button is a pressable button")
        waiting = next((element for identifier, element in elements.items() if identifier.endswith("/progress") and element.read("AXDescription") == "Waiting for server"), None)
        check(waiting is not None and waiting.read("AXValue") is None, "the indeterminate progress is published without a value")
        (FIXTURE / "Resources/advance.txt").write_text("1")
        ax.wait_for(lambda: published()["axb/progress/1/progress"].read("AXValue") == 75, "The advanced progress", timeout=20)
        check(published()["axb/progress/1/message"].read("AXValue") == "Order 8 of 10", "advancing the progress updates its value and message")
        if args.voiceover:
            # A script-launched 4D starts in the background; bring it forward, then read the window from its top.
            front()
            ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)
            time.sleep(1)
            front(); mark = heard.mark(); vo.key("home", vo.VO)
            run = [phrase_until(lambda ph: ph.strip() != "", mark)]
            # VoiceOver reads by position: the indicator, the Stop button on its line, then the message.
            for _ in range(8):
                if any("Stop" in ph for ph in run) and any("Order 8 of 10" in ph for ph in run):
                    break
                front(); mark = heard.mark(); vo.key("right", vo.VO)
                run.append(phrase_until(lambda ph: ph.strip() != "", mark))
            for _ in range(4):
                if "Stop" in run[-1]:
                    break
                front(); mark = heard.mark(); vo.key("left", vo.VO)
                run.append(phrase_until(lambda ph: ph.strip() != "", mark))
            report["navigation"] = run
            check(any("Importing orders" in ph and "75" in ph for ph in run), "VoiceOver reads the indicator by its title and progress")
            check(any("Order 8 of 10" in ph for ph in run), "VoiceOver reads the message")
            check("Stop" in run[-1] and "button" in run[-1], "VoiceOver reaches the Stop button")
            front(); vo.key("space", vo.VO)
            spoken = [ph for _, ph in heard.since(0)]
            report["speech"] = spoken
        else:
            check(published()["axb/progress/1/stop"].perform("AXPress") == 0, "pressing Stop is accepted")
        ax.wait_for(lambda: any(e.get("event") == "stopped" for e in events()), "Progress Stopped", timeout=20)
        stopped = next(e for e in events() if e.get("event") == "stopped")
        check(stopped["runId"] == run_id and stopped["compiled"] == args.compiled and stopped["advanced"] is True,
              "the Stop press reaches the component, as Progress Stopped reports for this run")
        process.wait(20)
        check(process.returncode == 0, "4D quits normally after the stopped progress")
        report["passed"] = True
    finally:
        if heard:
            heard.stop()
        if vo:
            vo.stop()
        if process.poll() is None:
            stop()
        name = "progress-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} progress checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
