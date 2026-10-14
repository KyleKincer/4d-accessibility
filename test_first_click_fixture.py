#!/usr/bin/env python3
"""Check that the bridge never changes where a click on a 4D window goes.

The fixture opens two compiled forms with lifecycle areas: Probe, with a button, then Other,
which becomes the key window. The test clicks Probe's button once with the mouse, while Probe
is not the key window, and records whether the button's method ran and which window is key
afterwards, then clicks it again, now in the key window. It does so without the plugin, with the
plugin dormant and with it active, and requires the same outcome each time: the plugin's views
never take a click, including the first click on an inactive window.

Only the windows' titles and frames are read, so the dormant variant stays dormant.
"""

import argparse
import ctypes as c
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

from build_component import BUILD, PACKAGE, literal, project_at, run_utility, verify_package
from install_host_methods import main as install

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start

FIXTURE = BUILD / "first-click-fixture"
APPLICATION = "/Applications/4D/4D.app/Contents/MacOS/4D"
PROBE, OTHER = "AXB first click", "AXB other window"
FORM_HEIGHT = 64
BUTTON = (20, 20, 100, 24)


def prepare(server):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("first-click-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "FirstClick")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text(f'''ON ERR CALL("ClickError")
var $probe; $other : Integer
var $data : Object
$data:=New object("pressed"; 0)
$probe:=Open form window("Probe"; Plain form window; 200; 200)
DIALOG("Probe"; $data; *)
$other:=Open form window("Other"; Plain form window; 700; 200)
DIALOG("Other"; New object)
QUIT 4D
''')
    (methods / "ClickError.4dm").write_text('File("/RESOURCES/error.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (methods / "ClickProbe.4dm").write_text('Form.pressed:=Form.pressed+1\nFile("/RESOURCES/pressed.json").setText(JSON Stringify(New object("pressed"; Form.pressed)))\n')
    (methods / "ClickOther.4dm").write_text('If (Form event code=On Load)\n File("/RESOURCES/ready.json").setText("{}")\nEnd if\n')
    left, top, width, height = BUTTON
    probe = {"Alpha": {"type": "button", "text": "Alpha", "left": left, "top": top, "width": width, "height": height,
                       "method": "ClickProbe", "events": ["onClick"]}}
    other = {"Close": {"type": "button", "text": "Close", "action": "cancel", "left": 20, "top": 20, "width": 100, "height": 24}}
    for name, title, objects, method in (("Probe", PROBE, probe, None), ("Other", OTHER, other, "ClickOther")):
        form = sources / "Forms" / name
        form.mkdir(parents=True)
        definition = {"windowTitle": title, "width": 360, "height": FORM_HEIGHT, "pages": [None, {"objects": objects}]}
        if method:
            definition.update({"method": method, "events": ["onLoad"]})
        (form / "form.4DForm").write_text(json.dumps(definition, indent=2) + "\n")
    install(["--project-dir", str(project.parent), "--all-forms"])
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="first-click-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    if not (result.get("success") is True and not result.get("errors")):
        print(json.dumps(result, indent=2))
        raise SystemExit("FAIL: first-click fixture compilation")
    return project


class Point(c.Structure):
    _fields_ = [("x", c.c_double), ("y", c.c_double)]


def click(x, y):
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    create = ax.signature(graphics, "CGEventCreateMouseEvent", c.c_void_p, c.c_void_p, c.c_uint32, Point, c.c_uint32)
    post = ax.signature(graphics, "CGEventPost", None, c.c_uint32, c.c_void_p)
    set_integer = ax.signature(graphics, "CGEventSetIntegerValueField", None, c.c_void_p, c.c_uint32, c.c_longlong)
    for kind in (5, 1, 2):  # moved, left down, left up
        event = create(None, kind, Point(x, y), 0)
        set_integer(event, 1, 1)  # click count
        post(1, event)  # kCGSessionEventTap
        ax.release(event)
        time.sleep(0.08)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before running the fixture")
    if not ax.trusted():
        parser.error("Accessibility permission is required")
    verify_package(PACKAGE)
    project = prepare(args.server.expanduser().resolve())
    resources = FIXTURE / "Resources"
    plugin, parked = FIXTURE / "Plugins/AccessibilityBridge.bundle", FIXTURE / "AccessibilityBridge.bundle"
    outcomes, checks = {}, []
    report = {"passed": False, "outcomes": outcomes, "checks": checks}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    try:
        for variant in ("none", "dormant", "active"):
            if variant == "none":
                plugin.rename(parked)
            elif parked.exists():
                parked.rename(plugin)
            resources.mkdir(exist_ok=True)
            for name in ("ready.json", "pressed.json", "error.json"):
                (resources / name).unlink(missing_ok=True)
            environment = dict(os.environ)
            environment.pop("AXB_ACTIVATION", None)
            if variant == "active":
                environment["AXB_ACTIVATION"] = "on"
            log = (BUILD / f"first-click-{variant}.log").open("w")
            process = subprocess.Popen([APPLICATION, "--project", str(project), "--dataless", "--opening-mode", "compiled",
                                        "--webadmin-auto-start", "false"], stdout=log, stderr=log, env=environment)
            try:
                wait_for_start(process, project, lambda: (resources / "ready.json").exists(), BUILD, timeout=60, awake=False)
                app = ax.application(process.pid)

                def windows():
                    return {w.read("AXTitle"): w for w in app.read("AXWindows") or []}

                ax.wait_for(lambda: {PROBE, OTHER} <= set(windows()), f"{variant}: both windows did not open", timeout=10)
                time.sleep(1)
                focused = app.read("AXFocusedWindow")
                check(focused is not None and focused.read("AXTitle") == OTHER, f"{variant}: the other window is key before the click")
                probe = windows()[PROBE]
                (x, y), (width, height) = probe.read("AXPosition"), probe.read("AXSize")
                left, top, button_width, button_height = BUTTON
                target = (x + left + button_width / 2, y + height - FORM_HEIGHT + top + button_height / 2)
                ax.require_test_input()
                if app.read("AXFrontmost") is not True:
                    raise AssertionError(f"{variant}: 4D is not frontmost; no click was sent")
                click(*target)
                time.sleep(1.5)
                def pressed():
                    return json.loads((resources / "pressed.json").read_text(encoding="utf-8-sig"))["pressed"] if (resources / "pressed.json").exists() else 0
                first = pressed()
                focused = app.read("AXFocusedWindow")
                key = focused.read("AXTitle") if focused else None
                ax.require_test_input()
                if app.read("AXFrontmost") is not True:
                    raise AssertionError(f"{variant}: 4D is not frontmost; no second click was sent")
                click(*target)
                time.sleep(1.5)
                outcomes[variant] = {"pressedByFirstClick": first, "keyWindowAfterFirstClick": key, "pressedAfterSecondClick": pressed()}
                check(outcomes[variant]["pressedAfterSecondClick"] == first + 1, f"{variant}: a click on the key window presses the button")
                check(not (resources / "error.json").exists(), f"{variant}: the fixture raised no error")
                print(f"{variant}: {outcomes[variant]}", flush=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=30)
        if parked.exists():
            parked.rename(plugin)
        check(outcomes["dormant"] == outcomes["none"], "a dormant plugin leaves a first click on an inactive window as without it")
        check(outcomes["active"] == outcomes["none"], "an active plugin leaves a first click on an inactive window as without it")
        report["passed"] = True
    finally:
        if parked.exists():
            parked.rename(plugin)
        (BUILD / "first-click.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} first-click checks")


if __name__ == "__main__":
    main()
