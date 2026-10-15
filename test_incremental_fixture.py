#!/usr/bin/env python3
"""Check that a form described again only where its drawing changed stays complete and correct.

The fixture is a compiled form with a lifecycle area. Its own code, run from a timer, changes it
the ways an application does: a field's value, a button's title, its position and its visibility,
and a caption that labels a field. After each change the test reads the form through
accessibility, and requires the change within a few seconds, well before the bridge's 30-second
backstop. It also requires that some descriptions reused the unchanged controls, that the form
was described whole when a control appeared, that a new caption relabelled its field without a
whole description, and that only the changed nodes were sent to the plugin. Last, it changes a help tip that
names a checkbox, which 4D does not draw: the backstop finds it by checking the form's objects a
few at a time, without describing the form whole.
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

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package
from install_host_methods import main as install

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start

FIXTURE = BUILD / "incremental-fixture"
APPLICATION = "/Applications/4D/4D.app/Contents/MacOS/4D"
TITLE = "AXB incremental"
COMMANDS = {
    "value": 'Form.name:="Changed by code"',
    "title": 'OBJECT SET TITLE(*; "btnTarget"; "Renamed")',
    "move": 'OBJECT MOVE(*; "btnTarget"; 40; 0)',
    "hide": 'OBJECT SET VISIBLE(*; "btnTarget"; False)',
    "show": 'OBJECT SET VISIBLE(*; "btnTarget"; True)',
    "caption": 'OBJECT SET TITLE(*; "labelName"; "Full name")',
    "tip": 'OBJECT SET HELP TIP(*; "chkUpdates"; "Send news")',
}


def prepare(server):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("incremental-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Incremental")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("IncrementalError")
var $window : Integer
$window:=Open form window("Probe"; Plain form window)
DIALOG("Probe"; New object("name"; "Ada"))
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "IncrementalError.4dm").write_text('File("/RESOURCES/error.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    cases = "".join(f'  : ($command="{name}")\n   {code}\n' for name, code in COMMANDS.items())
    (methods / "IncrementalForm.4dm").write_text(f'''var $file : 4D.File
var $command : Text
Case of
 : (Form event code=On Load)
  SET TIMER(15)
 : (Form event code=On Timer)
  $file:=File("/RESOURCES/command.txt")
  If ($file.exists)
   $command:=$file.getText()
   $file.delete()
   Case of
{cases}   End case
  End if
  File("/RESOURCES/state.json").setText(JSON Stringify(New object("diagnostics"; AXB_Form("diagnostics"; New object))))
End case
''')
    objects = {
        "labelName": {"type": "text", "text": "Name", "left": 20, "top": 22, "width": 80, "height": 17},
        "inputName": {"type": "input", "dataSource": "Form.name", "left": 110, "top": 20, "width": 200, "height": 20},
        "btnTarget": {"type": "button", "text": "Target", "left": 20, "top": 60, "width": 100, "height": 24},
        "btnOther": {"type": "button", "text": "Other", "left": 200, "top": 60, "width": 100, "height": 24},
        "chkUpdates": {"type": "checkbox", "text": "", "tooltip": "Send updates", "dataSource": "Form.updates", "left": 330, "top": 62,
                       "width": 20, "height": 20},
    }
    for index in range(40):
        objects[f"Item{index:02}"] = {"type": "button", "text": f"Item {index}", "left": 20 + (index % 8) * 50, "top": 100 + (index // 8) * 26,
                                      "width": 46, "height": 22}
    form = sources / "Forms/Probe"
    form.mkdir(parents=True)
    (form / "form.4DForm").write_text(json.dumps({"windowTitle": TITLE, "width": 440, "height": 240, "method": "IncrementalForm",
                                                  "events": ["onLoad", "onTimer"], "pages": [None, {"objects": objects}]}, indent=2) + "\n")
    install(["--project-dir", str(project.parent), "--all-forms"])
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="incremental-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    if not (result.get("success") is True and not result.get("errors")):
        print(json.dumps(result, indent=2))
        raise SystemExit("FAIL: incremental fixture compilation")
    return project


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
    checks = []
    report = {"passed": False, "checks": checks, "nativeSha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "componentSha256": sha(PACKAGE / "AccessibilityBridge.4DZ"), "latencySeconds": {}}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    def state():
        try:
            return json.loads((resources / "state.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}

    process = subprocess.Popen([APPLICATION, "--project", str(project), "--dataless", "--opening-mode", "compiled", "--webadmin-auto-start", "false"],
                               stdout=(BUILD / "incremental.log").open("w"), stderr=subprocess.STDOUT)
    try:
        wait_for_start(process, project, lambda: (resources / "state.json").exists(), BUILD, timeout=60)
        app = ax.application(process.pid)

        def window():
            return next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None)

        def element(name):
            target = window()
            return target.find("/" + name) if target else None

        ax.wait_for(lambda: element("inputName"), "The form was not published", timeout=20)
        check(element("inputName").read("AXDescription") == "Name" and element("btnTarget").read("AXDescription") == "Target",
              "the form is published with its labels")
        position = element("btnTarget").read("AXPosition")

        def change(command, condition, message, timeout=8):
            (resources / "command.txt").write_text(command)
            started = time.monotonic()
            ax.wait_for(condition, f"{command}: {message}", timeout=timeout)
            report["latencySeconds"][command] = round(time.monotonic() - started, 2)
            check(True, message)

        change("value", lambda: element("inputName").read("AXValue") == "Changed by code", "a field's value set by code is published")
        def diagnostics_where(condition, message):
            return ax.wait_for(lambda: (lambda d: d if d and condition(d) else None)(state().get("diagnostics")), message, timeout=5)

        def settled():
            # Let the descriptions of a change finish before counting them.
            time.sleep(1.5)
            return state()["diagnostics"]

        change("title", lambda: element("btnTarget") and element("btnTarget").read("AXDescription") == "Renamed", "a button's new title is published")
        report["sentNodes"] = {"title": diagnostics_where(lambda d: d.get("sentNodes") == 1, "The title change sent more than its node")["sentNodes"]}
        check(True, "only the renamed button's node was sent to the plugin")
        change("move", lambda: element("btnTarget") and element("btnTarget").read("AXPosition")[0] == position[0] + 40, "a moved button is published at its new place")
        change("hide", lambda: element("btnTarget") is None, "a hidden button leaves the form")
        whole = settled()["wholeDescriptions"]
        change("show", lambda: element("btnTarget") is not None, "a shown button returns")
        diagnostics_where(lambda d: d.get("wholeDescriptions", 0) > whole, "A control that appeared did not describe the form whole")
        check(True, "a control that appears describes the form whole")
        whole = settled()["wholeDescriptions"]
        change("caption", lambda: element("inputName").read("AXDescription") == "Full name", "a new caption relabels its field")
        report["sentNodes"]["caption"] = diagnostics_where(lambda d: d.get("sentNodes") == 2, "The caption change sent more than its and its field's nodes")["sentNodes"]
        check(settled()["wholeDescriptions"] == whole, "a new caption is described with only the controls it labels, sending only their nodes")
        check(element("btnOther").read("AXDescription") == "Other" and element("Item39").read("AXDescription") == "Item 39",
              "unchanged controls stay published")
        diagnostics = ax.wait_for(lambda: state().get("diagnostics"), "No diagnostics", timeout=5)
        report["diagnostics"] = {k: diagnostics.get(k) for k in ("wholeDescriptions", "partialDescriptions", "verifiedObjects", "revision", "nodeCount")}
        check(diagnostics.get("partialDescriptions", 0) > 0, "descriptions reused the unchanged controls")
        whole = settled()["wholeDescriptions"]
        report["beforeBackstop"] = whole
        change("tip", lambda: element("chkUpdates") and element("chkUpdates").read("AXDescription") == "Send news",
               "a change 4D does not draw is published by the backstop", timeout=50)
        diagnostics = ax.wait_for(lambda: (lambda d: d if d.get("verifiedObjects", 0) >= 46 else None)(state().get("diagnostics") or {}),
                                  "The backstop did not check every object", timeout=10)
        report["backstop"] = {k: diagnostics.get(k) for k in ("wholeDescriptions", "partialDescriptions", "verifiedObjects")}
        check(diagnostics["wholeDescriptions"] == whole, "the backstop checked the objects a few at a time, without a whole description")
        report["passed"] = True
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        (BUILD / "incremental.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} incremental description checks")


if __name__ == "__main__":
    main()
