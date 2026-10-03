#!/usr/bin/env python3
"""Read and operate the owned classic-list fixture through Appium Mac2/XCTest."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def port_free(port):
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", port))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--appium", required=True, type=Path, help="Installed Appium executable")
    parser.add_argument("--appium-home", required=True, type=Path, help="Appium home with the Mac2 driver installed")
    args = parser.parse_args()
    mode = "compiled" if args.compiled else "interpreted"
    stem = "appium-list-" + mode
    run_id = uuid.uuid4().hex
    report_paths = [ROOT / ("build/" + stem + suffix + ".json") for suffix in ("", "-" + run_id)]
    report = {"passed": False, "compiled": args.compiled, "checks": [], "requests": [], "runId": run_id,
              "startedAt": datetime.now(timezone.utc).isoformat(), "driver_sha256": sha(Path(__file__)),
              "failure": "Preflight did not complete",
              "scope": "Synthetic named scalar list parent through Appium Mac2/XCTest. No AXPress, save/reopen, Symphony, QA-Driver, SQUASH runner or remote-client claim."}
    ROOT.joinpath("build").mkdir(exist_ok=True)
    for path in report_paths:
        path.write_text(json.dumps(report, indent=2) + "\n")
    if not args.run:
        parser.error("Use --run in an unlocked desktop session")
    ax.require_test_input()
    for name in ("4D", "4D Server", "VoiceOver"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0, "Close existing desktop fixtures"
    fixture = ROOT / "build/list-subform-fixture"
    project, resources = fixture / "Project/Selection.4DProject", fixture / "Resources"
    prepared = json.loads((ROOT / "build/list-subform-compile-report.json").read_text())
    assert prepared["passed"]
    expected_config = {"noArea": False, "autoModify": False, "configured": False, "diagnosticsTest": False,
                       "textKey": False, "tableParent": False, "noPrimaryKey": False, "horizontal": False,
                       "selectionMode": "multiple", "header": 0, "rowHeight": 24}
    assert all(prepared.get(key) == value for key, value in expected_config.items()), "Prepare the default list fixture"
    source_paths = {str(path.relative_to(fixture)) for path in (fixture / "Project/Sources").rglob("*") if path.is_file()}
    assert source_paths == set(prepared["sources_sha256"]), "Prepared source file set changed"
    for name, digest in prepared["sources_sha256"].items():
        if name.endswith("catalog.4DCatalog"):
            semantic = hashlib.sha256(ET.canonicalize((fixture / name).read_text(), strip_text=True).encode()).hexdigest()
            assert semantic == prepared["catalog_semantic_sha256"], "Catalog definitions changed"
        else:
            assert sha(fixture / name) == digest, "Prepared source changed: " + name
    for relative, key in (("Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge", "native_sha256"),
                          ("Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ", "component_sha256"),
                          ("Resources/AXB.FormMetadata.json", "metadata_sha256")):
        report[key] = sha(fixture / relative)
        assert report[key] == prepared[key], "Prepared package/metadata changed: " + relative
    subprocess.run(["codesign", "--verify", "--strict", str(fixture / "Plugins/AccessibilityBridge.bundle")], check=True, capture_output=True)
    report["kitVersion"] = (ROOT / "VERSION").read_text().strip()
    report["compile_sha256"] = sha(ROOT / "build/list-subform-compile-report.json")
    report["mac2Version"] = json.loads((args.appium_home / "node_modules/appium-mac2-driver/package.json").read_text())["version"]
    report["fourDVersion"] = plistlib.loads(Path("/Applications/4D/4D.app/Contents/Info.plist").read_bytes()).get("CFBundleVersion")
    report["hostArchitecture"] = os.uname().machine
    for port in (4725, 10125):
        port_free(port)
    for name in ("runtime-status.json", "errors.json", "close.json", "closed.json"):
        (resources / name).unlink(missing_ok=True)
    last = {}

    def state():
        nonlocal last
        assert not (resources / "errors.json").exists(), "4D fixture error"
        try:
            last = json.loads((resources / "runtime-status.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        return last

    def check(value, label):
        report["checks"].append({"name": label, "passed": bool(value)})
        print(("PASS: " if value else "FAIL: ") + label, flush=True)
        assert value, label

    endpoint = "http://127.0.0.1:4725"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(method, path, body=None, timeout=180, record=True):
        raw = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(endpoint + path, data=raw, method=method, headers={"Content-Type": "application/json"})
        started = time.monotonic()
        try:
            with opener.open(req, timeout=timeout) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            raise AssertionError(error.read().decode()) from error
        finally:
            if record:
                report["requests"].append({"method": method, "path": path, "seconds": round(time.monotonic() - started, 3)})
        assert not (isinstance(result.get("value"), dict) and result["value"].get("error")), result
        return result

    logs, session, appium, process = [], None, None, None
    try:
        log = ROOT / ("build/appium-" + mode + "-fixture.log")
        handle = log.open("w")
        logs.append(handle)
        process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project),
                                    "--data", str(fixture / "synthetic.4dd"), "--opening-mode", mode,
                                    "--webadmin-auto-start", "false"], stdout=handle, stderr=handle)
        ready, _ = wait_for_start(process, project, lambda: state() if state().get("listForm") == "Rows" else None, ROOT / "build")
        check(ready["compiled"] is args.compiled, "The owned fixture runs in the requested 4D execution mode")
        app, window = activate_fixture(process, project, "AX bridge classic list subform")
        def guard():
            ax.require_test_input()
            assert process.poll() is None, "Owned 4D exited"
            pids = subprocess.run(["pgrep", "-x", "4D"], capture_output=True, text=True)
            assert pids.stdout.split() == [str(process.pid)], "A second 4D process appeared"
            focused = app.read("AXFocusedWindow")
            assert app.read("AXFrontmost") is True and focused and focused.same_as(window), "Owned fixture lost foreground focus"

        before = state()
        dependencies = before.get("dependencies", {})
        component = dependencies.get("componentInfo", {})
        check(dependencies.get("ok") is True and component.get("compiled") is True and component.get("version") == report["kitVersion"]
              and component.get("hostCompiled") is args.compiled
              and (dependencies.get("nativeStatus") or "").startswith("Accessibility Bridge " + report["kitVersion"] + ";"),
              "The loaded plugin and compiled component match the fixture version and mode")
        report["dependencies"] = dependencies
        report["before"] = {key: before.get(key) for key in ("before", "after", "events", "inspections")}
        handle = (ROOT / ("build/appium-" + mode + "-server.log")).open("w")
        logs.append(handle)
        appium = subprocess.Popen([str(args.appium.resolve()), "--address", "127.0.0.1", "--port", "4725", "--log-no-colors"],
                                  env=dict(os.environ, APPIUM_HOME=str(args.appium_home.resolve())), stdout=handle, stderr=handle,
                                  start_new_session=True)

        def server_ready():
            assert appium.poll() is None, "Appium exited"
            try:
                return request("GET", "/status", timeout=2, record=False)["value"]["ready"]
            except (OSError, AssertionError):
                return False

        ax.wait_for(server_ready, "Appium server did not start", timeout=30)
        assert appium.poll() is None, "Owned Appium exited"
        owners = subprocess.run(["lsof", "-t", "-nP", "-iTCP:4725", "-sTCP:LISTEN"], capture_output=True, text=True)
        assert owners.stdout.split() == [str(appium.pid)], "The loopback Appium server belongs to another process"
        report["appiumVersion"] = request("GET", "/status")["value"]["build"]["version"]
        caps = {"platformName": "mac", "appium:automationName": "mac2", "appium:bundleId": "com.4D.4D",
                "appium:appPath": "/Applications/4D/4D.app", "appium:noReset": True, "appium:skipAppKill": True,
                "appium:systemPort": 10125, "appium:showServerLogs": True, "appium:serverStartupTimeout": 120000}
        response = request("POST", "/session", {"capabilities": {"alwaysMatch": caps, "firstMatch": [{}]}})
        session = response["value"]["sessionId"]
        base = "/session/" + session
        guard()
        xml = request("GET", base + "/source")["value"]
        (ROOT / ("build/appium-" + mode + "-source.xml")).write_text(xml)
        tree = ET.fromstring(xml)
        matches = [node for node in tree.iter() if node.tag == "XCUIElementTypeWindow" and node.get("title") == "AX bridge classic list subform"]
        check(len(matches) == 1, "XCTest exports one owned fixture window")
        report["source_sha256"] = hashlib.sha256(xml.encode()).hexdigest()
        report["element_count"] = sum(1 for _ in tree.iter())
        for name, role in (("Items", "XCUIElementTypeTable"), ("Inspect", "XCUIElementTypeButton"), ("Note", "XCUIElementTypeTextField")):
            nodes = [node for node in matches[0].iter() if node.get("identifier") == "axb/Grid/" + name]
            check(len(nodes) == 1 and nodes[0].tag == role, "XCTest exports one " + name + " with its stable identifier and role")
        window_elements = request("POST", base + "/elements", {"using": "class name", "value": "XCUIElementTypeWindow"})["value"]
        owned = []
        for candidate in window_elements:
            identifier = candidate["element-6066-11e4-a52e-4f735466cecf"]
            if request("GET", base + "/element/" + identifier + "/attribute/title")["value"] == "AX bridge classic list subform":
                owned.append(identifier)
        check(len(owned) == 1, "Appium scopes identifier queries to the owned fixture window")
        elements = {}
        for name in ("Items", "Inspect", "Note"):
            found = request("POST", base + "/element/" + owned[0] + "/elements", {"using": "accessibility id", "value": "axb/Grid/" + name})["value"]
            check(len(found) == 1, "The owned window has one Appium match for " + name)
            identifier = found[0]["element-6066-11e4-a52e-4f735466cecf"]
            elements[name] = identifier
            observed = request("GET", base + "/element/" + identifier + "/attribute/identifier")["value"]
            check(observed == "axb/Grid/" + name, "Appium finds " + name + " by accessibility identifier")
        after = state()
        check(after.get("tick", 0) > before.get("tick", 0)
              and all(after.get(key) == before.get(key) for key in ("inspections", "events", "before", "after")),
              "Fresh fixture state confirms XCTest discovery preserves original handlers and record buffer")
        # Mac2's XCUIElement click and the bridge's AXPress have separate gates.
        # The fixture state proves actual behavior separately from HTTP success.
        guard()
        request("POST", base + "/element/" + elements["Inspect"] + "/click", {})
        inspected = ax.wait_for(lambda: state() if state().get("inspections") == after.get("inspections", 0) + 1 and state().get("privateRead", {}).get("done") else None,
                                "XCTest click did not complete the original inspection handler", timeout=20)
        quiet_tick = inspected["tick"]
        quiet_until = time.monotonic() + 2
        while time.monotonic() < quiet_until:
            guard()
            assert state().get("inspections") == after.get("inspections", 0) + 1, "Original handler ran again"
            time.sleep(0.1)
        inspected = state()
        check(inspected["tick"] > quiet_tick, "The fixture continues publishing during the handler quiet period")
        check(inspected["before"] == inspected["after"] == after["before"], "Appium activation preserves loaded record, selection and modified buffer")
        saved = inspected["privateRead"]
        check(inspected["inspections"] == after.get("inspections", 0) + 1 and saved.get("error") is None and saved["count"] == 600
              and saved["first"] == "Record 0001" and saved["second"] == "Record 0002" and saved["last"] == "Record 0600",
              "Appium activation runs the original handler once and reads saved fixture data")
        guard()
        check(app.read("AXFocusedWindow").same_as(window), "XCTest leaves focus in the owned fixture window")
        report["final"] = {key: inspected.get(key) for key in ("before", "after", "events", "inspections", "privateRead")}
        report["passed"] = True
        report.pop("failure", None)
    except BaseException as error:
        report["failure"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        if session:
            try:
                request("DELETE", "/session/" + session, timeout=30)
            except Exception as error:
                report["session_cleanup_error"] = str(error)
                report["passed"] = False
        if appium:
            try:
                try:
                    os.killpg(appium.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                def group_stopped():
                    appium.poll()
                    try:
                        os.killpg(appium.pid, 0)
                        return False
                    except ProcessLookupError:
                        return True

                deadline = time.monotonic() + 15
                while not group_stopped() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if not group_stopped():
                    report["passed"] = False
                    report["appium_cleanup_error"] = "Owned Appium process group did not stop after SIGTERM"
                    try:
                        os.killpg(appium.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    deadline = time.monotonic() + 5
                    while not group_stopped() and time.monotonic() < deadline:
                        time.sleep(0.1)
                    assert group_stopped(), "Owned Appium process group survived SIGKILL"
                appium.wait(timeout=5)
                for port in (4725, 10125):
                    deadline = time.monotonic() + 5
                    while True:
                        try:
                            port_free(port)
                            break
                        except OSError:
                            if time.monotonic() >= deadline:
                                raise AssertionError("Listener remains on owned test port " + str(port))
                            time.sleep(0.1)
            except Exception as error:
                report["appium_cleanup_error"] = str(error)
                report["passed"] = False
        if process and process.poll() is None:
            try:
                (resources / "close.json").write_text("{}")
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    report["passed"] = False
                    report["fixture_cleanup_error"] = "Owned fixture did not close through its original handler"
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
            except Exception as error:
                report["fixture_cleanup_error"] = str(error)
                report["passed"] = False
        report["exitCode"] = process.returncode if process else None
        if report["exitCode"] != 0:
            report["passed"] = False
            report["failure"] = report.get("failure", "Fixture exit code " + str(report["exitCode"]))
        if not report["passed"] and "failure" not in report:
            report["failure"] = "Acceptance cleanup failed"
        for log in logs:
            log.close()
        payload = json.dumps(report, indent=2) + "\n"
        for path in report_paths:
            path.write_text(payload)
    assert report["passed"]


if __name__ == "__main__":
    main()
