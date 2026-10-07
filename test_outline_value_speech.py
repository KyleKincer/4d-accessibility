#!/usr/bin/env python3
"""Cold final-row VoiceOver speech with controlled outline page delivery.

Synthetic AppKit diagnostic using the production provider; no 4D acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
CASES = ("offscreen-delayed", "onscreen-delayed", "offscreen-immediate", "fast-update", "leave", "leave-after-load", "inspection")
COMPILE = ("src/Session.mm", "src/Grid.mm", "src/Bridge.mm", "src/GridNative.mm", "src/NativeLayout.mm", "src/DrawnText.mm", "src/MessageDialogs.mm", "src/ProgressWindows.mm", "tests/NativeOutlineFixture.mm")
SOURCES = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "src").glob("*") if p.is_file()) + [
    "tests/NativeOutlineFixture.mm", "tests/mac_ax.py", "tests/voiceover.py", "tests/ReadScreen.swift", "test_outline_value_speech.py"]
TITLE = "AXB native outline fixture"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--case", action="append", choices=CASES)
    parser.add_argument("--output", type=Path, default=ROOT / "build/outline-value-speech")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"passed": False, "scope": __doc__.strip(), "cases": []}
    path = output / "report.json"

    def save():
        path.write_text(json.dumps(report, indent=2) + "\n")

    save()
    report["sourceSHA256"] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}
    binary, ocr = output / "NativeOutlineFixture", output / "ReadScreen"
    subprocess.run(["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-g", "-I", str(ROOT / "src"),
                    *[str(ROOT / name) for name in COMPILE], "-framework", "Cocoa", "-framework", "CoreText", "-framework", "QuartzCore", "-o", str(binary)], check=True)
    report["binarySHA256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    save()
    if not args.run:
        print("Built cold outline speech fixture; use --run on an unlocked desktop.")
        return
    import mac_ax as ax
    from voiceover import VoiceOver
    ax.require_test_input()
    assert ax.trusted(), "Existing Accessibility permission is required"
    assert not VoiceOver.pids("VoiceOver") and not VoiceOver.pids("VoiceOver Quickstart"), "Existing VoiceOver session belongs to the user"
    subprocess.run(["xcrun", "swiftc", str(ROOT / "tests/ReadScreen.swift"), "-o", str(ocr)], check=True)

    for case in args.case or CASES:
        result = {"case": case, "passed": False, "checks": [], "voiceover": [], "observations": []}
        report["cases"].append(result)
        save()

        def check(condition, description):
            assert condition, description
            result["checks"].append(description)
            print(f"PASS ({case}): {description}", flush=True)

        with tempfile.TemporaryDirectory(prefix="axb-outline-speech-") as directory:
            directory = Path(directory)
            run_id, sequence, process, vo = uuid.uuid4().hex, 0, None, None
            result["runID"] = run_id

            def state():
                try:
                    value = json.loads((directory / "state.json").read_text())
                    assert value["pid"] == process.pid and value["runID"] == run_id
                    return value
                except (FileNotFoundError, json.JSONDecodeError):
                    return None

            def command(operation):
                nonlocal sequence
                assert process.poll() is None
                sequence += 1
                temporary = directory / "command.tmp"
                temporary.write_text(json.dumps({"runID": run_id, "id": sequence, "operation": operation}))
                temporary.replace(directory / "command.json")
                if operation != "quit":
                    ax.wait_for(lambda: state() and state()["command"] == sequence, "Fixture command timed out", timeout=10)

            with (output / f"{case}-host.log").open("w") as log:
                try:
                    mode = "--deferred-onscreen" if case == "onscreen-delayed" else "--fast-update" if case == "fast-update" else "" if case == "offscreen-immediate" else "--deferred-values"
                    process = subprocess.Popen([str(binary), str(directory), run_id, *([mode] if mode else [])], stdout=log, stderr=log)
                    result["pid"] = process.pid
                    ax.wait_for(state, "Outline fixture did not start", timeout=10)
                    app = ax.application(process.pid)
                    windows = app.read("AXWindows") or []
                    check(len(windows) == 1 and windows[0].read("AXTitle") == TITLE and app.read("AXFrontmost"), "exact owned outline window is frontmost")
                    pending, outline = [windows[0]], None
                    while pending:
                        item = pending.pop()
                        if item.read("AXRole") == "AXOutline":
                            outline = item
                            break
                        pending.extend(item.read("AXChildren") or [])
                    check(outline is not None and outline.count("AXRows") == 25, "production outline exposes the exact target row")
                    check(len(outline.read("AXVisibleRows")) == (25 if "onscreen" in case else 10), "target geometry matches the chosen viewport")
                    check(state()["targetPages"] == 0, "final value page starts cold")
                    target = outline.cell(1, 24)
                    target_id = target.read("AXIdentifier")
                    vo = VoiceOver(process, None, TITLE, output / f"{case}-captions", ocr)
                    result["voiceover"] = vo.steps
                    vo.start()
                    caption = vo.key("home")
                    for _ in range(4):
                        if "Grouped items" in caption:
                            break
                        caption = vo.key("right")
                    check("Grouped items" in caption, "VoiceOver reaches the owned outline")
                    vo.key("down", shift=True)
                    caption = vo.key("end")
                    result["coldCaption"] = caption
                    check("Loading" in caption and "25" in caption, "VoiceOver actually reads the cold final row")
                    result["beforeRelease"] = state()
                    if case == "inspection":
                        check(outline.cell(0, 23).read("AXValue") == "Loading", "an unrelated AX client inspects a different cold row")
                    if case == "leave":
                        check("close button" in vo.key("home", command=True).lower().replace(",", ""), "VoiceOver leaves the outline for its native close button")
                    if "immediate" not in case and case != "fast-update":
                        command("releasePages")
                    ax.wait_for(lambda: state()["targetPages"] > 0, "Final page did not arrive", timeout=10)
                    expected_value = "Updated final value" if case == "fast-update" else "Value root/19"
                    if case == "fast-update":
                        ax.wait_for(lambda: state()["finalValueUpdated"] and state()["targetPages"] >= 2, "Second fast value did not arrive", timeout=10)
                        check(True, "a second value arrives before the settled layout notification")
                    result["afterRelease"] = state()
                    if case == "leave-after-load":
                        check("close button" in vo.key("home", command=True).lower().replace(",", ""), "VoiceOver leaves immediately after page arrival")
                    check(all(result["beforeRelease"][name] == result["afterRelease"][name] for name in ("generation", "order", "revision", "rows")), "page release preserves topology and target identity")
                    check(target.read("AXValue") == expected_value and outline.cell(1, 24).read("AXIdentifier") == target_id, "the same retained target has its exact loaded value")
                    loaded_at = time.monotonic()
                    for n in range(8):
                        caption = vo.read_caption()
                        result["observations"].append({"afterLoadedSeconds": round(time.monotonic() - loaded_at, 3), "caption": caption})
                        shutil.copyfile(vo.output / f"step-{len(vo.steps):03}.png", vo.output / f"observation-{n:02}.png")
                        time.sleep(1)
                    captions = [item["caption"] for item in result["observations"]]
                    check(not any("not responding" in item.lower() for item in captions), "provider stays responsive during stationary observation")
                    if case in ("leave", "leave-after-load"):
                        check(not any("root/" in item or "Distant leaf" in item for item in captions), "arriving values do not interrupt reading outside the outline")
                        check("minimize" in vo.key("right").lower(), "next navigation retains the native window-control cursor")
                    else:
                        check(any(expected_value in item for item in captions), "VoiceOver speaks the loaded final value without cursor movement")
                        check(not any("root/18" in item or "Distant leaf" in item for item in captions), "VoiceOver does not speak an unrelated value")
                        check("Distant leaf" in vo.key("left"), "next navigation starts from the same final-row cell")
                        check(expected_value in vo.key("right"), "return navigation retains the exact loaded target")
                    vo.stop()
                    command("quit")
                    process.wait(timeout=10)
                    closed = json.loads((directory / "closed.json").read_text())
                    check(process.returncode == 0 and closed == {"runID": run_id, "pid": process.pid}, "owned fixture closes normally with matching evidence")
                    result["passed"] = True
                except BaseException as error:
                    result["error"] = repr(error)
                    print(f"FAIL ({case}): {error}", flush=True)
                finally:
                    if vo and vo.owned:
                        try:
                            vo.stop()
                        except BaseException as error:
                            result["cleanupError"] = repr(error)
                            result["passed"] = False
                    if process and process.poll() is None:
                        try:
                            command("quit")
                            process.wait(timeout=5)
                        except BaseException:
                            process.terminate()
                            try:
                                process.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                process.kill(); process.wait(timeout=5)
                        result["passed"] = False
                    result["exitCode"] = process.returncode if process else None
                    save()
    report["passed"] = all(item["passed"] for item in report["cases"]) and report["sourceSHA256"] == {
        name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}
    report["count"] = sum(len(item["checks"]) for item in report["cases"])
    save()
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
