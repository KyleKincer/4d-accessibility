#!/usr/bin/env python3
"""Check that forms without a bridge area are published when 4D runs a project from its archive.

A built application, and 4D opening a .4DZ, run the compiled project from an archive and report
the folder holding it. A 4D remote client runs its server's project from an archive in its cache
folder and reports only the project's name. In each case the plugin reads the forms' definitions
from that archive.

First, 4D opens the fixture's archive directly; its project form must be published. Then the
fixture is a compiled project with a project form and a table form, neither with a lifecycle
area, served by 4D Server on this Mac. 4D Server gives its clients the plugin and component from
its own Plugins and Components folders, and the compiled project as an archive in the client's
cache folder. A 4D client connects to 127.0.0.1 through a .4DLink file, opens the project form,
then the table form. Each must be published from its definition in that archive, with its
controls labelled by their captions, and Save must close the project form through 4D.

The client's cache folder for the fixture is removed afterwards.
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
import zipfile

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax

NAME = "AXBRemoteClient"
FIXTURE = BUILD / "remote-client-fixture"
CLIENT = "/Applications/4D/4D.app/Contents/MacOS/4D"
PORT = 19813
PROJECT_TITLE, TABLE_TITLE = "AXB remote project form", "AXB remote table form"


def prepare(server):
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("remote-client-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, NAME)
    sources = project.parent / "Sources"
    table_id, key_id = uuid.uuid4().hex.upper(), uuid.uuid4().hex.upper()
    (sources / "catalog.4DCatalog").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n'
        f'<base name="{NAME}" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en"><schema name="DEFAULT_SCHEMA"/>'
        f'<table name="Customers" uuid="{table_id}" id="1"><field name="id" uuid="{key_id}" type="4" id="1" unique="true" never_null="true"/>'
        f'<primary_key field_name="id" field_uuid="{key_id}"/></table></base>\n')
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Plugins").mkdir()
    shutil.copytree(BUILD / "AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''var $window : Integer
$window:=Open form window("Hello"; Plain form window)
DIALOG("Hello"; New object("name"; ""))
CLOSE WINDOW($window)
$window:=Open form window([Customers]; "Detail"; Plain form window)
DIALOG([Customers]; "Detail"; New object("city"; ""))
CLOSE WINDOW($window)
''')

    def form(title, objects):
        return json.dumps({"windowTitle": title, "width": 320, "height": 110, "pages": [None, {"objects": objects}]}, indent=2) + "\n"

    (sources / "Forms/Hello").mkdir(parents=True)
    (sources / "Forms/Hello/form.4DForm").write_text(form(PROJECT_TITLE, {
        "labelName": {"type": "text", "text": "Name", "left": 20, "top": 20, "width": 60, "height": 17},
        "inputName": {"type": "input", "dataSource": "Form.name", "left": 90, "top": 18, "width": 150, "height": 20},
        "btnSave": {"type": "button", "text": "Save", "action": "accept", "left": 90, "top": 60, "width": 80, "height": 24}}))
    (sources / "TableForms/1/Detail").mkdir(parents=True)
    (sources / "TableForms/1/Detail/form.4DForm").write_text(form(TABLE_TITLE, {
        "labelCity": {"type": "text", "text": "City", "left": 20, "top": 20, "width": 60, "height": 17},
        "inputCity": {"type": "input", "dataSource": "Form.city", "left": 90, "top": 18, "width": 150, "height": 20},
        "btnDone": {"type": "button", "text": "Done", "action": "accept", "left": 90, "top": 60, "width": 80, "height": 24}}))
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="remote-client-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    if not (result.get("success") is True and not result.get("errors")):
        print(json.dumps(result, indent=2))
        raise SystemExit("FAIL: remote client fixture compilation")
    return project


def archived_project():
    """The compiled project zipped as a .4DZ, beside the plugin and component."""
    folder = FIXTURE / "archived"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir()
    shutil.copytree(FIXTURE / "Components", folder / "Components")
    shutil.copytree(FIXTURE / "Plugins", folder / "Plugins")
    with zipfile.ZipFile(folder / f"{NAME}.4DZ", "w", zipfile.ZIP_DEFLATED) as zipped:
        # 4D's own archives list each folder before its contents.
        for path in [FIXTURE / "Project", *sorted((FIXTURE / "Project").rglob("*"))]:
            zipped.write(path, path.relative_to(FIXTURE).as_posix() + ("/" if path.is_dir() else ""))
    return folder / f"{NAME}.4DZ"


def caches():
    return list((Path.home() / "Library/Caches/4D").glob(f"{NAME}_127_0_0_1_{PORT}_*"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path, help="4D Server.app, used to compile and to serve")
    args = parser.parse_args()
    for process in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", process], capture_output=True).returncode == 0:
            parser.error(f"Close {process} before running the fixture")
    if not ax.trusted():
        parser.error("Accessibility permission is required")
    verify_package(PACKAGE)
    server_app = args.server.expanduser().resolve()
    project = prepare(server_app)
    for folder in caches():
        shutil.rmtree(folder)
    checks = []
    report = {"passed": False, "checks": checks, "nativeSha256": sha(BUILD / "AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "componentSha256": sha(PACKAGE / "AccessibilityBridge.4DZ")}

    def check(condition, message):
        checks.append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    server = client = local = None
    try:
        local = subprocess.Popen([CLIENT, "--project", str(archived_project()), "--opening-mode", "compiled", "--dataless", "--webadmin-auto-start", "false"],
                                 stdout=(BUILD / "archived-project.log").open("w"), stderr=subprocess.STDOUT)
        app = ax.application(local.pid)
        try:
            target = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == PROJECT_TITLE), None),
                                 "4D did not open the archived project's form", timeout=60)
        except AssertionError:
            print("windows", [w.read("AXTitle") for w in app.read("AXWindows") or []], "exit", local.poll())
            raise
        field = ax.wait_for(lambda: target.find("/inputName"), "The archived project's form was not published", timeout=30)
        check(field.read("AXRole") == "AXTextField" and field.read("AXDescription") == "Name",
              "a project opened from its archive publishes its form, labelled by its caption")
        local.terminate()
        local.wait(timeout=30)
        info = plistlib.loads((server_app / "Contents/Info.plist").read_bytes())
        server = subprocess.Popen([str(server_app / "Contents/MacOS" / info["CFBundleExecutable"]), "--project", str(project), "--create-data",
                                   "--opening-mode", "compiled", "--webadmin-auto-start", "false"],
                                  stdout=(BUILD / "remote-server.log").open("w"), stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 90
        while f":{PORT}" not in subprocess.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", str(server.pid)], capture_output=True, text=True).stdout:
            assert server.poll() is None, f"4D Server exited: {server.returncode}"
            assert time.monotonic() < deadline, "4D Server did not listen"
            time.sleep(1)
        link = FIXTURE / "client.4DLink"
        link.write_text(f'<?xml version="1.0" encoding="UTF-8"?><database_shortcut is_remote="true" server_database_name="{NAME}" server_path="127.0.0.1:{PORT}"/>\n')
        client = subprocess.Popen([CLIENT, str(link)], stdout=(BUILD / "remote-client.log").open("w"), stderr=subprocess.STDOUT)
        app = ax.application(client.pid)

        def window(title):
            return next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == title), None)

        def published(title, names):
            def found():
                target = window(title)
                if not target:
                    return None
                elements = {name: target.find("/" + name) for name in names}
                return elements if all(elements.values()) else None
            try:
                return ax.wait_for(found, f"{title} was not published", timeout=30)
            except AssertionError:
                print("windows", [w.read("AXTitle") for w in app.read("AXWindows") or []])
                raise

        elements = ax.wait_for(lambda: window(PROJECT_TITLE), "The client did not open the project form", timeout=120) and \
            published(PROJECT_TITLE, ("labelName", "inputName", "btnSave"))
        check(elements["inputName"].read("AXRole") == "AXTextField" and elements["inputName"].read("AXDescription") == "Name",
              "the client publishes the project form's field, labelled by its caption")
        check(elements["btnSave"].read("AXRole") == "AXButton" and elements["btnSave"].read("AXDescription") == "Save",
              "the client publishes the project form's button by its title")
        # macOS does not activate an application launched from a background process, and the
        # bridge presses only in 4D's key window. Activate only this fixture's client.
        ax.require_test_input()
        if app.read("AXFrontmost") is not True and app.set_boolean("AXFrontmost", True) != 0:
            subprocess.run(["/usr/bin/osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {client.pid}) to true'],
                           capture_output=True, timeout=10)
        ax.wait_for(lambda: app.read("AXFrontmost") is True, "The client did not activate", timeout=15)
        time.sleep(1)
        check(elements["btnSave"].press() == 0, "Save accepts a press")
        elements = published(TABLE_TITLE, ("labelCity", "inputCity", "btnDone"))
        check(window(PROJECT_TITLE) is None, "the press ran 4D's accept action on the client")
        check(elements["inputCity"].read("AXDescription") == "City" and elements["btnDone"].read("AXDescription") == "Done",
              "the client publishes the table form from the cached archive")
        report["clientCache"] = [folder.name for folder in caches()]
        check(any((folder / f"{NAME}.4DZ").exists() for folder in caches()), "the client ran the project from an archive in its cache folder")
        report["passed"] = True
    finally:
        for process in (local, client, server):
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
        if not report["passed"]:
            import zipfile
            for folder in caches():
                for archive in folder.glob("*.4DZ"):
                    print("archive", archive.name, [n for n in zipfile.ZipFile(archive).namelist() if "Forms" in n])
        for folder in caches():
            shutil.rmtree(folder, ignore_errors=True)
        (BUILD / "archived-project.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} archived project checks")


if __name__ == "__main__":
    main()
