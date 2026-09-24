#!/usr/bin/env python3
"""Validate metadata mappings before readiness, after bad keys, and on callback errors."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

from build_component import literal, project_at, run_utility, sha
from prepare_grid_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
import doctor
from fixture_desktop import wait_for_start


def prepare(server):
    subprocess.run([sys.executable, str(ROOT / "prepare_grid_fixture.py"), "--collection", "--row-states", "--server", str(server)], check=True)
    fixture = BUILD / "grid-metadata-lifecycle"
    if fixture.exists():
        fixture.rename(BUILD / ("metadata-lifecycle-previous-" + uuid.uuid4().hex))
    shutil.copytree(FIXTURE, fixture)
    methods = fixture / "Project/Sources/Methods"
    path = methods / "AXBG_Form.4dm"
    source = path.read_text().replace('  Form.linesReady:=True', '  Form.linesReady:=False\n  Form.bridgeMetaCalls:=0\n  Form.commandSequence:=0\n  Form.savedSecondKey:=Form.rows[1].id')
    source = source.replace('  $result:=AXB_Form("start"; $options)', '  Form.savedOptions:=$options\n  $result:=AXB_Form("start"; $options)', 1)
    source = source.replace(' : (Form event code=On Timer)\n', ' : (Form event code=On Timer)\n  AXBG_MetaLifecycle\n')
    path.write_text(source)
    path = methods / "AXBG_MetaBridge.4dm"
    source = path.read_text().replace('var $same : Boolean', 'var $same : Boolean\nForm.bridgeMetaCalls:=Form.bridgeMetaCalls+1\nIf (Form.throwMeta=True)\n $meta:=JSON Parse("{")\nEnd if')
    path.write_text(source)
    path = methods / "AXBG_State.4dm"
    source = path.read_text().replace('$state.diagnostics:=', '$state.commandSequence:=Form.commandSequence\n$state.bridgeMetaCalls:=Form.bridgeMetaCalls\n$state.axbFailure:=Form.axbFailure\n$state.active:=Form.axbForm.active\n$state.diagnostics:=')
    path.write_text(source)
    (methods / "AXBG_MetaLifecycle.4dm").write_text('''var $command; $reply : Object
If (Not(File("/RESOURCES/meta-command.json").exists))
 return
End if
$command:=JSON Parse(File("/RESOURCES/meta-command.json").getText())
File("/RESOURCES/meta-command.json").delete()
Case of
 : ($command.operation="ready-changed")
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; "AXBG_MetaOther")
  Form.linesReady:=True
 : ($command.operation="invalid-key-start")
  $reply:=AXB_Form("stop"; New object)
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; "AXBG_Meta")
  Form.rows[1].id:=Form.rows[0].id
  $reply:=AXB_Form("start"; Form.savedOptions)
 : ($command.operation="repair-key-changed")
  Form.rows[1].id:=Form.savedSecondKey
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; "AXBG_MetaOther")
 : ($command.operation="empty-start")
  $reply:=AXB_Form("stop"; New object)
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; "")
  $reply:=AXB_Form("start"; Form.savedOptions)
 : ($command.operation="recover")
  $reply:=AXB_Form("stop"; New object)
  LISTBOX SET PROPERTY(*; "Items"; lk meta expression; "AXBG_Meta")
  $reply:=AXB_Form("start"; Form.savedOptions)
 : ($command.operation="throw")
  Form.throwMeta:=True
 : ($command.operation="close")
  CANCEL
End case
Form.commandSequence:=$command.sequence
''')
    project = fixture / "Project/LogicalGridFixture.4DProject"
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="metadata-lifecycle-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(fixture / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    compiled = {"passed": result.get("success") is True and not result.get("errors"), "compiler": result,
        "sources_sha256": {str(p.relative_to(fixture)): sha(p) for p in (fixture / "Project/Sources").rglob("*") if p.is_file()},
        "native_sha256": sha(fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
        "component_sha256": sha(fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"), "test_sha256": sha(Path(__file__))}
    (BUILD / "grid-metadata-lifecycle-compile.json").write_text(json.dumps(compiled, indent=2) + "\n")
    assert compiled["passed"], result
    return fixture, project, compiled


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if args.run:
        assert ax.trusted() and doctor.desktop_session()["unlocked"]
    fixture, project, compiled = prepare(args.server.expanduser().resolve())
    if not args.run:
        print("Compiled metadata lifecycle fixture; --run validates it on the desktop.")
        return
    report = {"passed": False, "checks": [], "states": [], "native_sha256": compiled["native_sha256"], "test_sha256": compiled["test_sha256"]}
    status = fixture / "Resources/runtime-status.json"
    status.unlink(missing_ok=True)
    native_error = fixture / "Resources/native-error.json"
    native_error.unlink(missing_ok=True)
    last = {}

    def state():
        nonlocal last
        assert not native_error.exists(), "Unexpected uncaught native error"
        try:
            last = json.loads(status.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        return last

    def check(condition, message):
        report["checks"].append({"passed": bool(condition), "name": message})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)
        assert condition, message

    with (BUILD / "grid-metadata-lifecycle-desktop.log").open("w") as log:
        process = subprocess.Popen(["/usr/bin/arch", "-arm64", "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", "interpreted", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
    sequence = 0
    try:
        ready, report["noticeAcknowledged"] = wait_for_start(process, project, state, BUILD)
        check(ready.get("start", {}).get("ok") is True and ready["compiled"] is False, "metadata lifecycle starts in interpreted desktop")
        app = ax.application(process.pid)
        window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == TITLE), None), "Owned metadata window missing")

        def tables():
            pending, found = [window], []
            while pending:
                element = pending.pop()
                if element.read("AXRole") == "AXTable":
                    found.append(element)
                else:
                    pending.extend(element.read("AXChildren") or [])
            return found

        def label_contains(text):
            return any(text in (t.read("AXDescription") or t.read("AXTitle") or "") for t in tables())

        def command(operation):
            nonlocal sequence
            assert process.poll() is None and app.read("AXFrontmost") is True
            sequence += 1
            (fixture / "Resources/meta-command.json").write_text(json.dumps({"operation": operation, "sequence": sequence}))
            if operation != "close":
                ax.wait_for(lambda: state().get("commandSequence") == sequence, "Metadata command not received")
                report["states"].append({"operation": operation, "state": state()})

        ax.wait_for(lambda: label_contains("loading"), "Initial loading state not published")
        check(state()["bridgeMetaCalls"] == 0, "not-ready grid does not evaluate its metadata callback")
        command("ready-changed")
        ax.wait_for(lambda: label_contains("row metadata expression changed"), "Changed expression escaped initial readiness guard")
        check(state()["bridgeMetaCalls"] == 0, "expression is captured before readiness and old mapping never runs")
        command("invalid-key-start")
        ax.wait_for(lambda: state()["bridgeMetaCalls"] > 0 and label_contains("row keys"), "Invalid keys did not suspend the grid")
        command("repair-key-changed")
        ax.wait_for(lambda: label_contains("row metadata expression changed"), "Changed expression escaped failed-binding guard")
        check(True, "repairing invalid keys cannot authorize a changed metadata expression")
        command("empty-start")
        ax.wait_for(lambda: label_contains("no Meta Info Expression"), "Empty native expression silently accepted a Formula")
        check(True, "configured Formula with empty native expression reports a named configuration failure")
        command("recover")
        table = ax.wait_for(lambda: next((t for t in tables() if t.count("AXRows") == 599), None), "Matching public restart did not recover")
        retained = table.cell(0, 0)
        check(retained is not None, "matching public restart restores grid cells")
        command("throw")
        ax.wait_for(lambda: state().get("axbFailure") and state().get("failure"), "Callback failure did not reach the owning error handler")
        ax.wait_for(lambda: not tables(), "Failed window's grid remained accessible")
        check(state().get("active") is not True and state()["diagnostics"].get("error") == "unregisteredWindow", "callback error stops the owning bridge and preserves its diagnostic")
        check(retained.read("AXSize") in (None, (0.0, 0.0)), "callback error retires the retained cell")
        report["finalState"] = state()
        command("close")
        process.wait(timeout=15)
        check(process.returncode == 0, "ordinary form timer and close survive bridge cleanup")
        report["passed"] = True
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        report["lastState"] = last
        if native_error.exists():
            report["unexpectedNativeError"] = native_error.read_text(encoding="utf-8-sig")
        (BUILD / "grid-metadata-lifecycle-report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
