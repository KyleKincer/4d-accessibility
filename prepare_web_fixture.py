#!/usr/bin/env python3
"""Compile a local HTML form beside ordinary 4D controls, without DOM injection."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from build_component import BUILD, ROOT, literal, project_at, run_utility, sha, verify_package

FIXTURE = BUILD / "web-fixture"
TITLE = "AX native web fixture"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--kit", required=True, type=Path)
    parser.add_argument("--baseline", action="store_true", help="No plugin, component, helpers or area")
    parser.add_argument("--engine", choices=["system", "embedded"], default="system")
    args = parser.parse_args()
    for name in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            parser.error("Close 4D and 4D Server before preparing this disposable fixture")
    server, kit = args.server.expanduser().resolve(), args.kit.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    package = kit / "Components/AccessibilityBridge.4dbase"
    verify_package(package)
    BUILD.mkdir(exist_ok=True)
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("web-fixture-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "Web")
    sources, resources = project.parent / "Sources", FIXTURE / "Resources"
    methods = sources / "Methods"
    for path in (ROOT / "tests/4d").glob("AXBW_*.4dm"):
        shutil.copy2(path, methods / path.name)
    (methods / "Compiler_AXBW.4dm").write_text("C_LONGINT(AXBW_Area)\n")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text('''ON ERR CALL("AXBW_Error")
var $window : Integer
var $data : Object
$data:=New object("name"; "Native field"; "clicks"; 0; "events"; New collection; "runId"; File("/RESOURCES/run-id.txt").getText())
$window:=Open form window("Root"; Plain form window)
SET WINDOW RECT(40; 100; 720; 720; $window)
DIALOG("Root"; $data)
File("/RESOURCES/closed.json").setText(JSON Stringify(New object("runId"; $data.runId; "clicks"; $data.clicks; "name"; $data.name)))
CLOSE WINDOW($window)
QUIT 4D
''')
    objects = {
        "Caption": {"type": "text", "text": "Native field", "left": 20, "top": 20, "width": 100, "height": 24},
        "Name": {"type": "input", "dataSource": "Form.name", "left": 130, "top": 20, "width": 220, "height": 24, "enterable": True},
        "Count": {"type": "button", "text": "Count", "left": 380, "top": 20, "width": 100, "height": 28, "method": "ObjectMethods/Count.4dm", "events": ["onClick"]},
        "Web": {"type": "webArea", "dataSource": "AXBW_Area", "left": 20, "top": 70, "width": 620, "height": 460, "webEngine": args.engine,
                "method": "ObjectMethods/Web.4dm", "events": ["onLoad", "onBeginURLLoading", "onEndURLLoading", "onURLLoadingError", "onGettingFocus", "onLosingFocus"]},
        "Close": {"type": "button", "text": "Close fixture", "action": "cancel", "left": 500, "top": 560, "width": 140, "height": 28},
    }
    form = {"windowTitle": TITLE, "width": 680, "height": 620, "method": "method.4dm", "events": ["onLoad", "onTimer"], "pages": [None, {"objects": objects}]}
    form_path = sources / "Forms/Root"
    (form_path / "ObjectMethods").mkdir(parents=True)
    (form_path / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    (form_path / "method.4dm").write_text("AXBW_Form\n")
    (form_path / "ObjectMethods/Count.4dm").write_text("AXBW_Click\n")
    (form_path / "ObjectMethods/Web.4dm").write_text("AXBW_Web\n")
    (resources / "index.html").write_text((ROOT / "tests/web/index.html").read_text())
    (resources / "web-url.txt").write_text((resources / "index.html").as_uri())
    (resources / "run-id.txt").write_text(uuid.uuid4().hex)
    if args.baseline:
        path = methods / "AXBW_Form.4dm"
        text = path.read_text()
        for line in ('  $state.areas:=AXB_Area("diagnostics"; ""; "")\n', '  $state.diagnostics:=AXB_Form("diagnostics"; New object)\n', '  $state.info:=AXB_Host("info"; New object)\n'):
            assert line in text
            text = text.replace(line, "")
        path.write_text(text)
    else:
        shutil.copytree(package, FIXTURE / "Components/AccessibilityBridge.4dbase")
        shutil.copytree(kit / "Plugins/AccessibilityBridge.bundle", FIXTURE / "Plugins/AccessibilityBridge.bundle")
        subprocess.run(["python3", str(kit / "install_host_methods.py"), "--project-dir", str(project.parent), "--form", "Root"], check=True)
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="web-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        body = '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
        if not args.baseline:
            body += '$options.plugins:=Folder(' + literal(FIXTURE / "Plugins") + ')\n'
            body += '$options.components:=New collection(File(' + literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ") + '))\n'
        body += '$result:=Compile project(File(' + literal(project) + '); $options)'
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver, body, 90)
    changed = [name for name, digest in hashes.items() if sha(FIXTURE / name) != digest]
    report = {"passed": result.get("success") is True and not result.get("errors") and not changed, "compiler": result,
              "sources_sha256": hashes, "baseline": args.baseline, "engine": args.engine, "changedDuringCompile": changed,
              "html_sha256": sha(resources / "index.html"), "kitVersion": (kit / "VERSION").read_text().strip(),
              "native_sha256": None if args.baseline else sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "component_sha256": None if args.baseline else sha(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}
    payload = json.dumps(report, indent=2) + "\n"
    (BUILD / "web-compile-report.json").write_text(payload)
    (BUILD / ("web-compile-report-" + uuid.uuid4().hex + ".json")).write_text(payload)
    print("PASS" if report["passed"] else json.dumps(report, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
