#!/usr/bin/env python3
"""VoiceOver keeps and announces focus when a host mode change makes the focused field editable.

The owned AppKit fixture publishes a focused read-only note beside forty sibling fields. One
refresh then makes every field editable, as a 4D form does when it enters Modify. VoiceOver must
announce the note as editable text instead of falling back to the containing group.

--run starts an owned VoiceOver session; it refuses an existing one. Speech is read with
VoiceOver's AppleScript `last phrase`, so "Allow VoiceOver to be controlled with AppleScript"
must be enabled. Without --run the fixture is only compiled.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent
BINARY = ROOT / "build/FocusReplacementFixture"


def osa(script, timeout=20):
    result = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError("VoiceOver AppleScript failed: " + result.stderr.strip())
    return result.stdout.strip()


def voiceover_running():
    return subprocess.run(["pgrep", "-x", "VoiceOver"], capture_output=True).returncode == 0


def heard_until(predicate, timeout):
    """Sample VoiceOver's last phrase; return every distinct phrase and whether one satisfied the predicate."""
    phrases, limit = [], time.monotonic() + timeout
    while time.monotonic() < limit:
        phrase = osa('tell application "VoiceOver" to get content of last phrase')
        if not phrases or phrases[-1] != phrase:
            phrases.append(phrase)
        if predicate(phrase):
            return phrases, True
        time.sleep(0.1)
    return phrases, False


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--trials", type=int, default=5)
    parser.add_argument("--start-editable", action="store_true", help="Diagnostic: read the note when it is editable from the start")
    parser.add_argument("--report", type=Path, default=ROOT / "build/focus-replacement-speech.json")
    args = parser.parse_args()
    (ROOT / "build").mkdir(exist_ok=True)
    subprocess.run(["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "src"),
                    str(ROOT / "tests/FocusReplacementFixture.mm"), str(ROOT / "src/Session.mm"), str(ROOT / "src/Grid.mm"),
                    str(ROOT / "src/Bridge.mm"), str(ROOT / "src/GridNative.mm"), str(ROOT / "src/NativeLayout.mm"),
                    str(ROOT / "src/DrawnText.mm"), str(ROOT / "src/InternalForms.mm"), str(ROOT / "src/MessageDialogs.mm"), str(ROOT / "src/ProgressWindows.mm"), str(ROOT / "src/QueryEditor.mm"),
                    "-framework", "Cocoa", "-framework", "CoreText", "-framework", "QuartzCore", "-o", str(BINARY)], check=True)
    print("Built focus replacement fixture")
    if not args.run:
        return
    if voiceover_running():
        raise SystemExit("A VoiceOver session is already running; this test only uses its own session")
    report = {"passed": False, "trials": []}
    with tempfile.TemporaryDirectory(prefix="axb-focus-replacement-") as directory:
        directory = Path(directory)
        fixture = subprocess.Popen([str(BINARY), str(directory)] + (["--editable"] if args.start_editable else []), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sequence = 0

        def state():
            try:
                return json.loads((directory / "state.json").read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                return None

        def command(operation):
            nonlocal sequence
            assert fixture.poll() is None, "Owned fixture exited"
            sequence += 1
            (directory / "command.tmp").write_text(json.dumps({"id": sequence, "operation": operation}))
            (directory / "command.tmp").replace(directory / "command.json")
            limit = time.monotonic() + 15
            while time.monotonic() < limit and not (state() and state()["command"] >= sequence):
                time.sleep(0.05)
            assert state()["command"] >= sequence, "Fixture command timed out"

        started = False
        try:
            limit = time.monotonic() + 15
            while time.monotonic() < limit and not state():
                time.sleep(0.1)
            assert state() and state()["pid"] == fixture.pid, "Fixture did not start"
            subprocess.run(["open", "/System/Library/CoreServices/VoiceOver.app"], check=True)
            started = True
            limit = time.monotonic() + 30
            while time.monotonic() < limit:
                try:
                    osa('tell application "VoiceOver" to get content of last phrase')
                    break
                except (RuntimeError, subprocess.TimeoutExpired):
                    time.sleep(0.5)
            subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {fixture.pid}) to true'],
                           capture_output=True)
            phrases, ready = heard_until(lambda p: "Latest note" in p, 30)
            assert ready, "VoiceOver did not reach the read-only note: " + repr(phrases[-3:])
            report["initial"] = phrases
            if args.start_editable:
                time.sleep(4)
                report["initial"] = heard_until(lambda p: False, 3)[0]
                print("initial editable reading:", report["initial"], flush=True)
                args.trials = 0
            for trial in range(1, args.trials + 1):
                command("editable")
                phrases, announced = heard_until(lambda p: "Latest note" in p and "edit text" in p, 15)
                report["trials"].append({"trial": trial, "announced": announced, "heard": phrases})
                print(f"trial {trial}: {'announced' if announced else 'NOT announced'}: {phrases[-3:]}", flush=True)
                command("readonly")
                heard_until(lambda p: "Latest note" in p and "edit text" not in p, 10)
                time.sleep(1)
            report["passed"] = all(t["announced"] for t in report["trials"])
        finally:
            if started and voiceover_running():
                try:
                    osa('tell application "VoiceOver" to quit')
                except (RuntimeError, subprocess.TimeoutExpired):
                    pass
            if fixture.poll() is None:
                try:
                    command("quit")
                except AssertionError:
                    pass
                fixture.wait(10)
            args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    announced = sum(t["announced"] for t in report["trials"])
    print(f"{'PASS' if report['passed'] else 'FAIL'}: VoiceOver announced the editable note in {announced} of {len(report['trials'])} trials")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
