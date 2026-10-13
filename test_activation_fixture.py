#!/usr/bin/env python3
"""Check that a 4D process serves accessibility only once an assistive technology needs it.

The fixture is a compiled form with a lifecycle area, as the installer adds it. In each mode
the test launches 4D and reads the form's state, which its timer records with AXB Active and
AXB Status:

- auto: the form starts dormant. Reading only the window's title and frame, as a window
  manager does, leaves it dormant. Reading the window's contents wakes it: its controls are
  published and a button pressed through accessibility runs the form's method;
- off: reading the window's contents leaves it dormant and publishes nothing;
- on: the form is active before any client reads it;
- with --voiceover, starting VoiceOver wakes a dormant process, and a process launched while
  VoiceOver runs starts active.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package
from install_host_methods import main as install

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start

FIXTURE = BUILD / "activation-fixture"
APPLICATION = "/Applications/4D/4D.app/Contents/MacOS/4D"


def prepare(server):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("activation-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Activation")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    import shutil
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''var $data : Object
var $window : Integer
ON ERR CALL("ActivationError")
$data:=New object("pressed"; ""; "name"; "")
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; $data)
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "ActivationError.4dm").write_text('File("/RESOURCES/error.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (methods / "ActivationClick.4dm").write_text("Form.pressed:=OBJECT Get name(Object current)\n")
    (methods / "ActivationForm.4dm").write_text('''Case of
 : (Form event code=On Load)
  SET TIMER(15)
 : (Form event code=On Timer)
  File("/RESOURCES/status.json").setText(JSON Stringify(New object("active"; AXB Active; "status"; AXB Status; "pressed"; Form.pressed; "compiled"; Is compiled mode)))
End case
''')
    objects = {
        "Alpha": {"type": "button", "text": "Alpha", "left": 20, "top": 20, "width": 100, "height": 24, "method": "ActivationClick", "events": ["onClick"]},
        "Beta": {"type": "button", "text": "Beta", "left": 130, "top": 20, "width": 100, "height": 24, "method": "ActivationClick", "events": ["onClick"]},
        "Close": {"type": "button", "text": "Close", "action": "cancel", "left": 240, "top": 20, "width": 100, "height": 24},
    }
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(json.dumps({"windowTitle": "AXB activation", "width": 360, "height": 64, "method": "ActivationForm",
                                                  "events": ["onLoad", "onTimer"], "pages": [None, {"objects": objects}]}, indent=2) + "\n")
    install(["--project-dir", str(project.parent), "--all-forms"])
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="activation-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    if not (result.get("success") is True and not result.get("errors")):
        print(json.dumps(result, indent=2))
        raise SystemExit("FAIL: activation fixture compilation")
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--voiceover", action="store_true", help="Also check that VoiceOver starts the process active")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the fixture")
    if not ax.trusted():
        parser.error("Accessibility permission is required")
    verify_package(PACKAGE)
    project = prepare(args.server.expanduser().resolve())
    status_file = FIXTURE / "Resources/status.json"
    checks = []
    report = {"passed": False, "checks": checks, "intel": args.intel, "voiceover": args.voiceover,
              "nativeSha256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "componentSha256": sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def launch(mode):
        (FIXTURE / "Resources").mkdir(exist_ok=True)
        status_file.unlink(missing_ok=True)
        (FIXTURE / "Resources/error.json").unlink(missing_ok=True)
        environment = dict(os.environ)
        environment.pop("AXB_ACTIVATION", None)
        if mode != "auto":
            environment["AXB_ACTIVATION"] = mode
        command = [APPLICATION, "--project", str(project), "--dataless", "--opening-mode", "compiled", "--webadmin-auto-start", "false"]
        if args.intel:
            command = ["arch", "-x86_64", *command]
        log = (BUILD / f"activation-{mode}.log").open("w")
        process = subprocess.Popen(command, stdout=log, stderr=log, env=environment)
        wait_for_start(process, project, lambda: status_file.exists(), BUILD, timeout=60)
        return process

    def status(process):
        assert process.poll() is None, "4D exited"
        deadline = time.monotonic() + 2
        while True:
            try:
                return json.loads(status_file.read_text(encoding="utf-8-sig"))
            except (OSError, ValueError):
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.05)

    def window(process):
        windows = [w for w in ax.application(process.pid).read("AXWindows") or [] if w.read("AXTitle") == "AXB activation"]
        assert len(windows) == 1, "The fixture window is not unique"
        return windows[0]

    def settle(process, seconds=2.0):
        time.sleep(seconds)
        return status(process)

    def stop(process):
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)

    vo = None
    try:
        process = launch("auto")
        try:
            state = settle(process)
            check(state["compiled"] is True, "auto: the fixture runs compiled")
            target = window(process)
            for name in ("AXTitle", "AXPosition", "AXSize", "AXMain", "AXMinimized"):
                target.read(name)
            state = settle(process)
            check(state["active"] == 0 and state["status"].endswith("auto; dormant"),
                  "auto: reading the window's title and frame leaves the process dormant")
            started = time.monotonic()
            alpha = ax.wait_for(lambda: window(process).find("/Alpha"), "auto: the form was not published after its contents were read", timeout=10)
            report["autoWakeSeconds"] = round(time.monotonic() - started, 2)
            # The form records its state every quarter second.
            state = ax.wait_for(lambda: (lambda value: value if value["active"] == 1 else None)(status(process)),
                                "auto: the process did not report activation", timeout=3)
            check(state["active"] == 1 and state["status"].endswith("auto; active; accessibility client"),
                  "auto: reading the window's contents wakes the process")
            check(alpha.read("AXRole") == "AXButton" and alpha.read("AXDescription") == "Alpha", "auto: the woken form publishes its buttons")
            check(alpha.press() == 0, "auto: Alpha accepts a press")
            ax.wait_for(lambda: status(process)["pressed"] == "Alpha", "auto: the press did not reach the form's method", timeout=10)
            check(True, "auto: a press runs the form's own method")
        finally:
            stop(process)

        process = launch("off")
        try:
            settle(process)
            published = None
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline and not published:
                published = window(process).find("/Alpha")
                time.sleep(0.25)
            state = status(process)
            check(state["active"] == 0 and state["status"].endswith("off; dormant") and published is None,
                  "off: reading the window's contents leaves the process dormant and publishes nothing")
        finally:
            stop(process)

        process = launch("on")
        try:
            state = status(process)
            check(state["active"] == 1 and state["status"].endswith("on; active; configured"), "on: the process is active before any client reads it")
            alpha = ax.wait_for(lambda: window(process).find("/Alpha"), "on: the form was not published", timeout=10)
            check(alpha.read("AXDescription") == "Alpha", "on: the form is published")
        finally:
            stop(process)

        if args.voiceover:
            import voiceover_session
            vo = voiceover_session
            process = launch("auto")
            try:
                state = settle(process)
                check(state["active"] == 0, "VoiceOver: the process is dormant before VoiceOver starts")
                vo.start()
                ax.wait_for(lambda: status(process)["active"] == 1, "VoiceOver: starting VoiceOver did not wake the process", timeout=15)
                # VoiceOver's launch or its first read of the window, whichever 4D sees first.
                reason = status(process)["status"].rsplit("; ", 1)[-1]
                report["voiceOverWakeReason"] = reason
                check(reason in ("VoiceOver", "accessibility client"), "VoiceOver: starting VoiceOver wakes a running process")
                alpha = ax.wait_for(lambda: window(process).find("/Alpha"), "VoiceOver: the form was not published", timeout=10)
                check(alpha.read("AXDescription") == "Alpha", "VoiceOver: the woken form is published")
            finally:
                stop(process)
            process = launch("auto")
            try:
                state = status(process)
                check(state["active"] == 1 and state["status"].endswith("auto; active; VoiceOver"),
                      "VoiceOver: the process starts active while VoiceOver is on")
            finally:
                stop(process)
        report["passed"] = True
    finally:
        if vo:
            vo.stop()
        name = "activation" + ("-intel" if args.intel else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} activation checks")


if __name__ == "__main__":
    main()
