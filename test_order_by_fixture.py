#!/usr/bin/env python3
"""4D's Order By editor through accessibility and VoiceOver.

Prepares the order by fixture with --server. The editor must publish its available fields,
the fields the selection is ordered by with each one's direction, the buttons that move
them, and Sort and Cancel. A field is added by pressing it, its direction is reversed by
pressing its Descending checkbox, and an ordered field is removed by pressing it, then Remove
field; Sort then returns the selection in the order they describe. --baseline records the
editor without any plugin, component or helpers; a later --run then requires it unchanged.
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
FIXTURE = BUILD / "order-by-fixture"
PIXELS = BUILD / "order-by-pixels"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
TITLE = "Order by"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--server", type=Path, required=True, help="4D Server.app used only as the compiler")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free editor for pixel comparison")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Sort with an owned VoiceOver session")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    import mac_ax as ax
    from test_native_messages import changed_pixels
    architecture = "x86_64" if args.intel else "arm64"
    subprocess.run([sys.executable, str(ROOT / "prepare_order_by_fixture.py"), "--server", str(args.server)] + (["--no-bridge"] if args.baseline else []), check=True)
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
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/OrderBy.4DProject"), "--data", str(FIXTURE / "Data/Orders.4DD"), "--create-data",
               "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"]
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
            if identifier.startswith("axb/order/"):
                found[identifier[len("axb/order/"):]] = child
        return found

    def element(key):
        return published().get(key)

    def press(key):
        assert element(key).perform("AXPress") == 0, key

    def ordered():
        """The ordered fields, top to bottom, each with whether it sorts descending."""
        found = published()
        return [(key[len("order/"):], found[key + "/descending"].read("AXValue") if key + "/descending" in found else None)
                for key in found if key.startswith("order/") and not key.endswith("/descending")]

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
            ax.wait_for(window, "Order By editor", timeout=60)
            front()
            time.sleep(3)
            PIXELS.mkdir(parents=True, exist_ok=True)
            ax.capture_window(process.pid, PIXELS / f"baseline-{architecture}.png", include_shadow=False, title=TITLE)
        finally:
            stop()
        print("Recorded the plugin-free Order By editor")
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

    def vo_to(predicate, limit=24):
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

    try:
        ax.wait_for(lambda: window() and element("bOK"), "The Order By editor is published", timeout=60)
        front()
        time.sleep(1)
        if not args.voiceover:
            reference = PIXELS / f"baseline-{architecture}.png"
            if reference.exists():
                time.sleep(1.5)
                ax.capture_window(process.pid, PIXELS / f"bridge-{architecture}.png", include_shadow=False, title=TITLE)
                changed = changed_pixels(reference, PIXELS / f"bridge-{architecture}.png", caret=True)
                report["changedPixels"] = changed
                check(changed == 0, "the Order By editor is pixel-identical to the plugin-free editor")
        roles = {key: (value.read("AXRole"), value.read("AXDescription") or value.read("AXTitle") or value.read("AXValue")) for key, value in published().items()}
        report["published"] = roles
        check({"field/id", "field/Customer", "field/Amount", "field/Paid", "field/Due"} <= set(roles) and roles["field/Customer"][0] == "AXButton" and not ordered(),
              "the available fields are buttons, and nothing is ordered yet")
        check(roles.get("bOne") == ("AXButton", "Add field") and roles.get("bRemoveOne") == ("AXButton", "Remove field") and
              roles.get("bRemoveAll") == ("AXButton", "Remove all fields"), "the arrow buttons are labelled")
        check(roles.get("bOK") == ("AXButton", "Sort") and roles.get("bCancel") == ("AXButton", "Cancel") and roles.get("fields.title", ("", ""))[1] == "Available Fields",
              "Sort, Cancel and the lists' captions are published by their titles")
        if args.voiceover:
            check(phrase_until(lambda ph: TITLE in ph, 0, 40), "VoiceOver reaches the Order By editor")
            check(vo_to(lambda ph: ph.startswith("Customer") and "button" in ph), "VoiceOver reads the available fields")
            front(); vo.key("space", vo.VO)
            ax.wait_for(lambda: ordered() == [("[Orders]Customer", False)], "Customer ordered", timeout=10)
            check(True, "VO-Space on a field orders by it, ascending")
            check(vo_to(lambda ph: "Descending" in ph and "checkbox" in ph and "unchecked" in ph), "VoiceOver reads the ordered field's direction as a checkbox")
            front(); mark = heard.mark(); vo.key("space", vo.VO)
            ax.wait_for(lambda: ordered() == [("[Orders]Customer", True)], "Customer descending", timeout=10)
            check(True, "VO-Space on it reverses the direction")
            check(vo_to(lambda ph: "Sort" in ph and "button" in ph), "VoiceOver reaches Sort")
            front(); vo.key("space", vo.VO)
            ax.wait_for(result, "The sorted selection", timeout=20)
            outcome = result()
            check(outcome["runId"] == run_id and outcome["ok"] == 1 and outcome["customers"] == [f"Customer {i}" for i in (5, 4, 3, 2, 1)],
                  "VO-Space on Sort sorts the selection in the order described")
        else:
            press("field/Paid")
            ax.wait_for(lambda: ordered() == [("[Orders]Paid", False)], "Paid ordered", timeout=10)
            check(True, "pressing an available field orders by it, ascending, as its double click does")
            press("field/Customer")
            ax.wait_for(lambda: ordered() == [("[Orders]Paid", False), ("[Orders]Customer", False)], "Customer ordered", timeout=10)
            press("order/[Orders]Customer/descending")
            ax.wait_for(lambda: ordered() == [("[Orders]Paid", False), ("[Orders]Customer", True)], "Customer descending", timeout=10)
            check(True, "pressing an ordered field's Descending checkbox reverses its direction, and the checkbox reports it")
            press("field/Amount")
            ax.wait_for(lambda: len(ordered()) == 3, "Amount ordered", timeout=10)
            press("order/[Orders]Amount")
            time.sleep(1)
            press("bRemoveOne")
            ax.wait_for(lambda: ordered() == [("[Orders]Paid", False), ("[Orders]Customer", True)], "Amount removed", timeout=10)
            check(True, "an ordered field pressed, then Remove field, is no longer ordered")
            press("bOK")
            ax.wait_for(result, "The sorted selection", timeout=20)
            outcome = result()
            check(outcome["runId"] == run_id and outcome["compiled"] == args.compiled and outcome["ok"] == 1 and
                  outcome["customers"] == [f"Customer {i}" for i in (5, 3, 1, 4, 2)], "Sort sorts the selection in the order described")
        process.wait(20)
        report["passed"] = True
    finally:
        if heard:
            report["speech"] = [ph for _, ph in heard.since(0)]
            heard.stop()
        if vo:
            vo.stop()
        stop()
        name = "order-by-" + architecture + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(report['checks'])} Order By editor checks ({architecture}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


if __name__ == "__main__":
    main()
