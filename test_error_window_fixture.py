#!/usr/bin/env python3
"""4D's error window through accessibility, with the plugin installed.

When a method fails and no error handler takes the error, 4D shows its own error window: the
message, the error's description, the failing line, Details and the buttons that end it. The
fixture is a project whose startup method runs two methods that fail, each in its own process,
with no error handler. The first error is read, its Details opened, and Abort pressed: the
method must stop at the failing line. The second is ended with Continue: the method must go on
after it. Each window is read and operated only through accessibility, or VoiceOver with
--voiceover. In a compiled application, Edit and Trace must be published unavailable.
"""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

from build_component import BUILD, literal, project_at, run_utility, sha

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
import voiceover_session as keys

FIXTURE = BUILD / "error-window-fixture"
BUNDLE = BUILD / "AccessibilityBridge.bundle"
APPLICATION = "/Applications/4D/4D.app/Contents/MacOS/4D"
TITLE = "Syntax Error"


def prepare(server, compiled):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("error-window-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "ErrorWindow")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUNDLE, FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''// Each failing method runs in its own process, so that Abort ends only that process.
var $phase : Text
var $process : Integer
For each ($phase; New collection("abort"; "continue"))
 File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; $phase; "compiled"; Is compiled mode)))
 $process:=New process("ErrorPhase"; 0; "Phase "+$phase; $phase)
 While (Process state($process)>=0)
  DELAY PROCESS(Current process; 10)
 End while
End for each
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "complete")))
QUIT 4D
''')
    (methods / "ErrorPhase.4dm").write_text('''#DECLARE($phase : Text)
var $order : Object
File("/RESOURCES/"+$phase+".txt").setText("started")
$order.lines.first:=1
File("/RESOURCES/"+$phase+".txt").setText("continued")
''')
    (methods / "Compiler_ErrorWindow.4dm").write_text("C_TEXT(ErrorPhase; $1)\n")
    if compiled:
        info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
        with tempfile.TemporaryDirectory(prefix="error-window-compile-", dir=BUILD) as temporary:
            driver = Path(temporary)
            project_at(driver, "Driver")
            result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
                '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
                f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
                f'$result:=Compile project(File({literal(project)}); $options)', 120)
        if not (result.get("success") is True and not result.get("errors")):
            print(json.dumps(result, indent=2))
            raise SystemExit("FAIL: error-window fixture compilation")
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--compiled", action="store_true", help="Open the project compiled instead of interpreted")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--voiceover", action="store_true", help="Read and operate the windows with VoiceOver")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the fixture")
    if not ax.trusted():
        parser.error("Accessibility permission is required")
    ax.require_test_input()
    project = prepare(args.server.expanduser().resolve(), args.compiled)
    resources = FIXTURE / "Resources"
    checks = []
    report = {"passed": False, "checks": checks, "compiled": args.compiled, "intel": args.intel, "voiceover": args.voiceover,
              "nativeSha256": sha(BUNDLE / "Contents/MacOS/AccessibilityBridge"), "windows": {}}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def read(name):
        try:
            return (resources / name).read_text(encoding="utf-8-sig")
        except OSError:
            return None

    heard = None
    if args.voiceover:
        heard = keys.Listener()
        keys.start()
        heard.start()
        # The error opens as soon as 4D starts: let VoiceOver finish starting first, or it can miss
        # the window's arrival.
        ax.wait_for(lambda: any("VoiceOver is on" in p for _, p in heard.since(0)), "VoiceOver did not start speaking", timeout=20)
        time.sleep(3)
    process = subprocess.Popen((["/usr/bin/arch", "-x86_64"] if args.intel else []) + [APPLICATION, "--project", str(project), "--dataless",
                                "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false"],
                               stdout=(BUILD / "error-window.log").open("w"), stderr=subprocess.STDOUT)
    keys.set_guard(keys.guard_frontmost(process.pid, ax))
    app = ax.application(process.pid)

    def front():
        subprocess.run(["/usr/bin/osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True, timeout=10)

    def window():
        return next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None)

    def elements():
        found = {}
        current = window()
        for child in (current.read("AXChildren") or []) if current else []:
            identifier = child.read("AXIdentifier") or ""
            if identifier.startswith("axb/error/"):
                found[identifier[len("axb/error/"):]] = child
        return found

    def published(keys_wanted):
        def ready():
            front()
            found = elements()
            return found if all(found.get(key) is not None and (found[key].read("AXValue") or found[key].read("AXDescription")) for key in keys_wanted) else None
        return ax.wait_for(ready, "The error window was not published", timeout=60)

    def phrase_until(predicate, since, timeout=20):
        limit = time.time() + timeout
        while time.time() < limit:
            for _, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    def describe(found):
        return {key: {"role": element.read("AXRole"), "label": element.read("AXDescription"), "value": element.read("AXValue"),
                      "enabled": element.read("AXEnabled")} for key, element in found.items()}

    try:
        spoken = heard.mark() if heard else 0
        # Abort: the method stops at the failing line.
        found = published(["message", "description", "line", "bAbort"])
        report["windows"]["abort"] = describe(found)
        check(found["message"].read("AXRole") == "AXStaticText" and 'method "ErrorPhase" at line number 4' in found["message"].read("AXValue"),
              "the error's message is readable text, with the method and line")
        check(found["description"].read("AXValue") in ("Undefined Object.", "Object or Collection Expected."), "the error's description is published")
        check(found["line"].read("AXValue") == "$order.lines.first:=1", "the failing line is published")
        check([found[key].read("AXDescription") for key in ("bEdit", "bTrace", "bContinue", "bAbort")] == ["Edit", "Trace", "Continue", "Abort"],
              "the buttons carry their titles, in reading order")
        check([found[key].read("AXEnabled") for key in ("bEdit", "bTrace")] == ([False, False] if args.compiled else [True, True]) and
              found["bContinue"].read("AXEnabled") is True and found["bAbort"].read("AXEnabled") is True,
              "Edit and Trace are unavailable in a compiled application, and available otherwise")
        ax.wait_for(lambda: (app.read("AXFocusedUIElement").read("AXIdentifier") if app.read("AXFocusedUIElement") else None) == "axb/error/bAbort",
                    "Focus did not start on Abort", timeout=10)
        check(True, "keyboard focus starts on Abort, 4D's default button")
        details = found["details"]
        check(details.read("AXRole") == "AXDisclosureTriangle" and details.read("AXDescription") == "Details" and details.read("AXValue") is False,
              "Details is a closed disclosure")
        if args.voiceover:
            check(phrase_until(lambda p: 'Error when executing the method "ErrorPhase"' in p, spoken), "VoiceOver speaks the error window when it opens")
        check(details.press() == 0, "Details opens through accessibility")
        opened = ax.wait_for(lambda: (lambda f: f if f.get("errors") is not None and f.get("bCopy") is not None else None)(elements()),
                             "Details did not open", timeout=10)
        report["windows"]["details"] = describe(opened)
        check(opened["details"].read("AXValue") is True, "Details reports itself open")
        check(opened["errors"].read("AXValue").startswith("-107"), "the error list is published with its code")
        check(opened["process"].read("AXValue").startswith("Process "), "the failing process is published")
        check(opened["bCopy"].read("AXDescription") == "Copy" and opened["bSave"].read("AXDescription").startswith("Save"), "Details' buttons are published")
        if args.voiceover:
            front()
            ax.wait_for(lambda: app.read("AXFocusedUIElement") and app.read("AXFocusedUIElement").read("AXIdentifier") == "axb/error/bAbort",
                        "Focus left Abort", timeout=10)
            keys.key("space", keys.VO)
            check(True, "VoiceOver presses Abort")
        else:
            check(opened["bAbort"].press() == 0, "Abort is pressed through accessibility")
        ax.wait_for(lambda: read("abort.txt") == "started" and json.loads(read("phase.json") or "{}").get("phase") == "continue",
                    "Abort did not end the failing method", timeout=20)
        check(True, "Abort stops the method at the failing line")

        # Continue: the method goes on after the failing line.
        found = ax.wait_for(lambda: (lambda f: f if f.get("bContinue") is not None and read("continue.txt") == "started" else None)(published(["message", "bContinue"])),
                            "The second error window was not published", timeout=60)
        report["windows"]["continue"] = describe(found)
        # 4D draws Continue as Ignore while it believes Option is held, and can miss the release of
        # VoiceOver's keys as the first window closes; the bridge then gives it the keyboard's state.
        limit = time.time() + 5
        while time.time() < limit and elements()["bContinue"].read("AXDescription") != "Continue":
            time.sleep(0.2)
        title = elements()["bContinue"].read("AXDescription")
        report["continueTitle"] = title
        check(title == "Continue" or (args.voiceover and title == "Ignore"), "Continue is published with the title 4D draws")
        found = elements()
        if args.voiceover:
            front()
            since = heard.mark()
            keys.key("left", keys.VO)
            check(phrase_until(lambda p: p.startswith(title), since), "VoiceOver moves to Continue")
            keys.key("space", keys.VO)
        else:
            check(found["bContinue"].press() == 0, "Continue is pressed through accessibility")
        ax.wait_for(lambda: read("continue.txt") == "continued", "Continue did not resume the method", timeout=20)
        check(True, "Continue resumes the method after the failing line")
        ax.wait_for(lambda: process.poll() is not None, "4D did not quit", timeout=30)
        check(True, "both errors ended and the application quit normally")
        report["passed"] = True
    finally:
        if heard:
            heard.stop()
            report["speech"] = [p for _, p in heard.since(0)][-40:]
            keys.stop()
        if process.poll() is None:
            process.terminate()
            process.wait(20)
        name = "error-window" + ("-intel" if args.intel else "") + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} error-window checks" + (" (compiled)" if args.compiled else "") + (" (VoiceOver)" if args.voiceover else ""))


if __name__ == "__main__":
    main()
