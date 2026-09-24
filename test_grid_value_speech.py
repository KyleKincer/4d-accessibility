#!/usr/bin/env python3
"""Verify delayed grid values with a stationary, owned VoiceOver cursor."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from voiceover import VoiceOver
import doctor

CASES = ("single", "forward", "back", "leave", "inspection", "reload", "checkbox", "popup")
SOURCES = (
    "src/Session.mm", "src/Session.h", "src/Grid.mm", "src/Grid.h",
    "src/Bridge.mm", "src/Bridge.h", "src/BridgePrivate.h", "src/GridNative.mm", "src/Limits.h",
    "tests/NativeGridFixture.mm", "tests/mac_ax.py", "tests/voiceover.py",
    "tests/ReadScreen.swift", "test_grid_value_speech.py",
)
TITLE = "AXB complete logical grid fixture"


def run_case(case, binary, ocr, output):
    report = {"case": case, "passed": False, "checks": [], "voiceover": [], "observations": []}

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print(f"PASS ({case}): {description}", flush=True)

    def spoken_column(caption, column):
        if column == 0 and case == "checkbox":
            return "Approved" in caption and "checked" in caption.lower() and "unchecked" not in caption.lower() and "checkbox" in caption.replace(" ", "").lower()
        if column == 0 and case == "popup":
            return "Decision" in caption and "Allowed" in caption and "pop" in caption.lower()
        # Vision occasionally reads the final zero as a lowercase o. The AX
        # value is checked exactly; retain strict row/column speech identity.
        return bool(re.search(rf"row-00000\s*/\s*column-{column}\s*/\s*value-[0oO]\b", caption))

    with tempfile.TemporaryDirectory(prefix="axb-grid-speech-") as directory:
        directory = Path(directory)
        with (output / f"{case}-host.log").open("w") as log:
            mode = "--deferred-" + case if case in ("checkbox", "popup") else "--deferred-values"
            process = subprocess.Popen([str(binary), str(directory), mode], stdout=log, stderr=log)
        sequence, vo = 0, None

        def state():
            try:
                value = json.loads((directory / "state.json").read_text())
                assert value["pid"] == process.pid, "Fixture PID changed"
                return value
            except (FileNotFoundError, json.JSONDecodeError):
                return None

        def command(operation):
            nonlocal sequence
            assert process.poll() is None, "Owned fixture exited"
            sequence += 1
            temporary = directory / "command.tmp"
            temporary.write_text(json.dumps({"id": sequence, "operation": operation}))
            temporary.replace(directory / "command.json")
            if operation != "quit":
                ax.wait_for(lambda: state() and state()["command"] == sequence, "Fixture command timed out", timeout=15)

        def observe(column, leave=False):
            command("releasePages")
            expected = f"row-00000 / column-{column} / value-0"
            if case == "popup" and column == 0:
                expected = "Allowed"
            cell = table.cell(column, 0)
            ax.wait_for(lambda: cell.read("AXValue") == expected, "Asynchronous value did not arrive", timeout=20)
            check(True, "external AX reads the provider's actual value")
            if case in ("checkbox", "popup"):
                content = cell.read("AXChildren")[0]
                role, value = ("AXCheckBox", 1) if case == "checkbox" else ("AXPopUpButton", "Allowed")
                check(content.read("AXRole") == role and content.read("AXValue") == value, "loaded content exposes its actual control role and state")
                check(content.read("AXEnabled") is False and "AXPress" not in content.actions(), "read-only control does not acquire a mutation action")
            observation = {"column": column, "leftGrid": leave, "captions": []}
            report["observations"].append(observation)
            loaded_at = time.monotonic()
            # Continue observing after the first correct caption: a later
            # notification must not speak another cell or move the cursor.
            for _ in range(8):
                caption = vo.read_caption()
                observation["captions"].append({"afterLoadedSeconds": round(time.monotonic() - loaded_at, 3), "caption": caption})
                time.sleep(1)
            captions = [item["caption"] for item in observation["captions"]]
            check(not any("not responding" in text.lower() for text in captions), "provider remains responsive during delayed speech")
            if leave:
                check(not any("row-" in text for text in captions), "pending grid values do not interrupt reading outside the grid")
                check("minimize" in vo.key("right").lower(), "VoiceOver remains at the window close button")
            else:
                check(any(spoken_column(text, column) for text in captions), "VoiceOver speaks the arriving value without cursor movement")
                check(not any("row-" in text and not spoken_column(text, column) for text in captions), "VoiceOver does not speak a different cell's value")
                check(spoken_column(vo.key("right"), column + 1), "next navigation starts from the same cell")

        try:
            ax.wait_for(state, "Native fixture did not open", timeout=20)
            app = ax.application(process.pid)
            windows = app.read("AXWindows") or []
            check(len(windows) == 1 and windows[0].read("AXTitle") == TITLE and app.read("AXFrontmost"), "exact owned native window is frontmost")
            pending, table = [windows[0]], None
            while pending:
                item = pending.pop()
                if item.read("AXRole") == "AXTable":
                    table = item
                    break
                pending.extend(item.read("AXChildren") or [])
            check(table is not None and table.count("AXRows") == 60 and table.count("AXColumns") == 24, "complete synthetic logical table is discoverable")
            cell = table.cell(0, 0)
            check(cell.read("AXValue") == "Loading" and state()["pages"] == 0 and state()["deferredPages"], "fixture withholds values while exposing the real grid")
            vo = VoiceOver(process, None, TITLE, output / f"{case}-captions", ocr)
            report["voiceover"] = vo.steps
            vo.start()
            report["initialCaption"] = vo.key("home", command=True)
            # A newly opened caption panel can exist before it paints. Observe
            # the original command's result without repeating navigation.
            def at_window_start():
                report["initialCaption"] = vo.read_caption()
                return "close button" in report["initialCaption"].lower().replace(",", "")
            at_start = "close button" in report["initialCaption"].lower().replace(",", "")
            check(at_start or bool(ax.wait_for(at_window_start, "VoiceOver did not reach the owned window", timeout=10)), "VoiceOver begins at the owned window")
            for _ in range(8):
                caption = vo.key("right")
                if "Complete grid fixture" in caption and "group" in caption.lower():
                    break
            check("Complete grid fixture" in caption and "group" in caption.lower(), "VoiceOver reaches the bridge group")
            caption = vo.key("down", shift=True)
            for _ in range(3):
                if "table" in caption.lower():
                    break
                caption = vo.key("right")
            check("table" in caption.lower(), "VoiceOver reaches the logical table")
            caption = vo.key("down", shift=True)
            if "loading" not in caption.lower():
                caption = vo.key("right")
            check("loading" in caption.lower() and cell.read("AXValue") == "Loading", "VoiceOver actually reads the cold first cell")
            column = 0
            if case in ("forward", "back", "leave"):
                check("loading" in vo.key("right").lower(), "VoiceOver visits a second cold cell")
                column = 1
            if case == "back":
                check("loading" in vo.key("left").lower(), "VoiceOver returns to the first cold cell")
                column = 0
            if case == "inspection":
                check(table.cell(2, 0).read("AXValue") == "Loading", "an unrelated AX client inspects another cold cell")
            if case == "leave":
                check("close button" in vo.key("home", command=True).lower().replace(",", ""), "VoiceOver leaves both cold cells for native window controls")
            observe(column, leave=case == "leave")
            if case == "reload":
                identity = cell.read("AXIdentifier")
                command("reloadPages")
                ax.wait_for(lambda: cell.read("AXValue") == "Loading", "Retained cell did not become cold", timeout=15)
                check(table.cell(0, 0).read("AXIdentifier") == identity, "cache invalidation preserves cell identity")
                # The preceding observation moved right exactly once.
                check("loading" in vo.key("left").lower(), "VoiceOver revisits the retained cell while its identical value reloads")
                observe(0)
            check(table.read("AXSelectedRows") == [], "reading does not select a row")
        except Exception as error:
            report["error"] = str(error)
        finally:
            try:
                if vo is not None:
                    vo.stop()
            except Exception as error:
                report["cleanupError"] = str(error)
            finally:
                if process.poll() is None:
                    command("quit")
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.terminate()
                        process.wait(timeout=5)
                report["exitCode"] = process.returncode
                report["passed"] = not any(key in report for key in ("error", "cleanupError")) and process.returncode == 0
                (output / f"{case}.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"RESULT ({case}): {report['passed']}", flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Run the owned VoiceOver session on an unlocked desktop")
    parser.add_argument("--case", choices=CASES, action="append", help="Run selected cases; default is all eight")
    parser.add_argument("--output", type=Path, default=ROOT / "build/grid-value-speech")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    binary, ocr = output / "NativeGridFixture", output / "read-fixture-screen"
    subprocess.run([
        "xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-g", "-I", str(ROOT / "src"),
        *[str(ROOT / name) for name in ("src/Session.mm", "src/Grid.mm", "src/Bridge.mm", "src/GridNative.mm", "tests/NativeGridFixture.mm")],
        "-framework", "Cocoa", "-o", str(binary),
    ], check=True)
    if not args.run:
        print("Built the deferred-value fixture; use --run to verify actual VoiceOver speech.")
        return
    if not ax.trusted() or not doctor.desktop_session()["unlocked"] or not doctor.desktop_access().get("screenCaptureAllowed"):
        parser.error("An unlocked desktop and existing Accessibility/Screen Recording permissions are required")
    if VoiceOver.pids("VoiceOver") or VoiceOver.pids("VoiceOver Quickstart"):
        parser.error("An existing VoiceOver session belongs to the user")
    subprocess.run(["xcrun", "swiftc", str(ROOT / "tests/ReadScreen.swift"), "-o", str(ocr)], check=True)
    report = {
        "scope": "Synthetic native host using production grid/session/provider sources and actual VoiceOver captions; no 4D host",
        "platform": platform.platform(), "passed": False, "cases": [],
        "sources_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES},
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    }
    for case in args.case or CASES:
        result = run_case(case, binary, ocr, output)
        report["cases"].append(result)
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        if not result["passed"]:
            raise SystemExit(result.get("error") or result.get("cleanupError") or "Owned fixture exited abnormally")
    report["passed"] = True
    report["count"] = sum(len(case["checks"]) for case in report["cases"])
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {report['count']} checks across {len(report['cases'])} VoiceOver cases")


if __name__ == "__main__":
    main()
