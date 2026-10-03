#!/usr/bin/env python3
"""Exercise native HTML accessibility beside the area-owned 4D provider."""
import argparse
import ctypes as c
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit
import uuid

from build_component import sha
from prepare_web_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def descendants(start):
    if not isinstance(start, ax.Element):
        return
    pending, seen = [(start, 0)], []
    while pending:
        element, depth = pending.pop(0)
        if any(element.same_as(other) for other in seen):
            continue
        if depth > 24 or len(seen) >= 2000:
            raise AssertionError("Native web fixture AX traversal exceeded its bound")
        seen.append(element)
        yield element
        pending.extend((child, depth + 1) for child in element.read("AXChildren") or [] if isinstance(child, ax.Element))


def describe(element):
    return {key: element.read(key) for key in ("AXRole", "AXTitle", "AXDescription", "AXIdentifier", "AXValue", "AXPosition", "AXSize")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--read-only", action="store_true")
    parser.add_argument("--pixels", action="store_true", help="Capture identical ordinary-button focus without editing")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error("--run and Accessibility permission are required")
    ax.require_test_input()
    for name in ("4D", "4D Server", "VoiceOver"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0, "An existing application owns the desktop"
    project, resources = FIXTURE / "Project/Web.4DProject", FIXTURE / "Resources"
    prepared = json.loads((BUILD / "web-compile-report.json").read_text())
    assert prepared["passed"]
    for name, digest in prepared["sources_sha256"].items():
        assert sha(FIXTURE / name) == digest, "Prepared source changed: " + name
    assert sha(resources / "index.html") == prepared["html_sha256"]
    for name in ("state.json", "error.json", "close.json", "closed.json"):
        (resources / name).unlink(missing_ok=True)
    run_id = (resources / "run-id.txt").read_text()
    requests, request_lock = [], threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            parsed = urlsplit(self.path)
            with request_lock:
                requests.append({"path": parsed.path, "query": parse_qs(parsed.query)})
            if parsed.path == "/":
                body = (resources / "index.html").read_bytes()
            elif parsed.path in ("/submit", "/next"):
                title = "Submission received" if parsed.path == "/submit" else "Next page"
                body = ('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>' + title + '</title></head><body><h1>' + title + '</h1><a href="/">Back to fixture</a></body></html>').encode()
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = "http://127.0.0.1:" + str(server.server_port) + "/"
    (resources / "web-url.txt").write_text(url)
    mode = "compiled" if args.compiled else "interpreted"
    variant = "baseline" if prepared["baseline"] else "bridge"
    case = "voiceover" if args.voiceover else ("pixels" if args.pixels else ("read" if args.read_only else "actions"))
    report = {"passed": False, "compiled": args.compiled, "engine": prepared["engine"], "baseline": prepared["baseline"],
              "scope": "Local semantic HTML and ordinary 4D controls; native browser owns HTML semantics and input",
              "runId": run_id, "kitVersion": prepared["kitVersion"], "native_sha256": prepared["native_sha256"],
              "component_sha256": prepared["component_sha256"], "compile_sha256": sha(BUILD / "web-compile-report.json"),
              "driver_sha256": sha(Path(__file__)), "checks": []}
    last = {}

    def state():
        nonlocal last
        assert not (resources / "error.json").exists(), "4D fixture error"
        try:
            last = json.loads((resources / "state.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            pass
        assert not last.get("webError"), last.get("webError")
        return last if last.get("runId") == run_id else {}

    def check(value, name):
        report["checks"].append({"name": name, "passed": bool(value)})
        print(("PASS: " if value else "FAIL: ") + name, flush=True)
        assert value, name

    process, window, vo = None, None, None
    try:
        with (BUILD / ("web-" + prepared["engine"] + "-" + variant + "-" + mode + ".log")).open("w") as log:
            process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", mode, "--webadmin-auto-start", "false"], stdout=log, stderr=log)
            ready, _ = wait_for_start(process, project, lambda: state() if state().get("webReady") else None, BUILD)
            check(ready["compiled"] is args.compiled, "Actual 4D execution mode matches the requested mode")
            app, window = activate_fixture(process, project, TITLE)
            if args.voiceover:
                from voiceover import VoiceOver
                vo = VoiceOver(process, project, TITLE, BUILD / "web-voiceover", BUILD / "read-fixture-screen")
                report["voiceover"] = vo.steps
                vo.start()

            def guard():
                ax.require_test_input()
                assert process.poll() is None
                command = subprocess.check_output(["ps", "-p", str(process.pid), "-o", "command="], text=True)
                assert "--project " + str(project.resolve()) in command
                assert app.read("AXFrontmost") is True and app.read("AXFocusedWindow").same_as(window)

            def native_click(element):
                guard()
                x, y = element.read("AXPosition")
                width, height = element.read("AXSize")
                wx, wy = window.read("AXPosition")
                ww, wh = window.read("AXSize")
                assert width > 0 and height > 0 and wx <= x and wy <= y and x + width <= wx + ww and y + height <= wy + wh
                hit = ax.system().at_position(x + width / 2, y + height / 2)
                get_pid = ax.signature(ax.AX, "AXUIElementGetPid", c.c_int, c.c_void_p, c.POINTER(c.c_int))
                pid = c.c_int()
                assert get_pid(hit.pointer, c.byref(pid)) == 0
                report.setdefault("mouseTargetOwners", []).append({"fixturePid": process.pid, "targetPid": pid.value, "role": hit.read("AXRole")})
                assert pid.value == process.pid, "Another application covers the native input target"
                class Point(c.Structure):
                    _fields_ = [("x", c.c_double), ("y", c.c_double)]
                graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
                create = ax.signature(graphics, "CGEventCreateMouseEvent", c.c_void_p, c.c_void_p, c.c_uint32, Point, c.c_uint32)
                post = ax.signature(graphics, "CGEventPost", None, c.c_uint32, c.c_void_p)
                flags = ax.signature(graphics, "CGEventSetFlags", None, c.c_void_p, c.c_uint64)
                clicks = ax.signature(graphics, "CGEventSetIntegerValueField", None, c.c_void_p, c.c_uint32, c.c_longlong)
                timestamp = ax.signature(graphics, "CGEventSetTimestamp", None, c.c_void_p, c.c_uint64)
                for kind in (5, 1, 2):
                    guard()
                    event = create(None, kind, Point(x + width / 2, y + height / 2), 0)
                    flags(event, 0)
                    clicks(event, 1, 1)
                    timestamp(event, time.monotonic_ns())
                    post(1, event)
                    ax.release(event)
                    time.sleep(0.1)

            def native_key(element, code, modifiers=0):
                guard()
                assert element.read("AXFocused") is True
                focused = app.read("AXFocusedUIElement")
                assert isinstance(focused, ax.Element) and (focused.same_as(element) or focused.same_as(window))
                graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
                create = ax.signature(graphics, "CGEventCreateKeyboardEvent", c.c_void_p, c.c_void_p, c.c_uint16, c.c_bool)
                flags = ax.signature(graphics, "CGEventSetFlags", None, c.c_void_p, c.c_uint64)
                post = ax.signature(graphics, "CGEventPostToPid", None, c.c_int, c.c_void_p)
                for down in (True, False):
                    event = create(None, code, down)
                    flags(event, modifiers)
                    post(process.pid, event)
                    ax.release(event)
                    time.sleep(0.1)

            def web():
                return next((e for e in descendants(window) if e.read("AXRole") == "AXWebArea"), None)

            native_web = ax.wait_for(web, "No native AXWebArea published", timeout=20)
            report["initialAX"] = [describe(e) for e in descendants(window)]
            check(sum(e.read("AXRole") == "AXWebArea" for e in descendants(window)) == 1, "The actual window contains one native web accessibility tree")
            check(not any((e.read("AXIdentifier") or "").startswith("axb/Root/Web") for e in descendants(window)), "The bridge does not publish duplicate HTML controls")
            bridge_root = window.find("/Root")
            check((bridge_root is None) is prepared["baseline"], "Only the integrated fixture has a virtual 4D root")
            if not prepared["baseline"]:
                registered = ax.wait_for(lambda: state() if state().get("diagnostics", {}).get("ready") else None, "The bridge did not publish a ready snapshot")
                areas = registered["areas"]
                check(areas.get("ok") is True and len(areas["areas"]) == 1 and areas["areas"][0]["state"] == "active" and areas["areas"][0]["registered"] is True and areas["areas"][0]["failure"] is None, "The lifecycle area has one active registration")
                check(registered["diagnostics"]["ok"] is True and registered["diagnostics"]["issues"] == [{"path": [], "object": "Web", "reason": "providerPending"}], "Discovery leaves only the browser-owned web area pending")
                info = registered["info"]
                check(info.get("ok") is True and info.get("hostAPI") == 1 and info["componentInfo"]["compiled"] is True and info["componentInfo"]["version"] == prepared["kitVersion"] and info["componentInfo"]["capturedStop"] == 1 and info["nativeStatus"].startswith("Accessibility Bridge " + prepared["kitVersion"] + ";") and all("; " + capability + " 1;" in info["nativeStatus"] for capability in ("areaLifecycle", "stableIdentifiers", "buttonInput")), "The loaded native plugin and compiled component match the kit and lifecycle contract")
                virtual = [e for e in descendants(bridge_root) if not e.same_as(bridge_root) and (e.read("AXIdentifier") or "").startswith("axb/")]
                check(not any(e.read("AXRole") == "AXWebArea" or (e.read("AXPosition") == native_web.read("AXPosition") and e.read("AXSize") == native_web.read("AXSize")) for e in virtual), "No virtual 4D descendant duplicates the native web role or frame")
            ax.capture_window(process.pid, BUILD / ("web-" + prepared["engine"] + "-" + variant + "-" + mode + "-initial.png"), include_shadow=False)

            def find(role, title):
                return next((e for e in descendants(web()) if e.read("AXRole") == role and e.read("AXTitle") == title), None)

            def require(role, title):
                return ax.wait_for(lambda: find(role, title), "Native HTML control missing: " + title)

            name, email = require("AXTextField", "Name"), require("AXTextField", "Email")
            enabled, reset = require("AXCheckBox", "Enabled"), require("AXButton", "Reset fixture")
            submit, more = require("AXButton", "Submit fixture"), require("AXDisclosureTriangle", "More information")
            check(name.read("AXValue") == "Before" and email.read("AXValue") == "before@example.test" and enabled.read("AXValue") == 1, "Native HTML labels, roles and initial values are exposed")
            if args.pixels:
                from PIL import Image, ImageChops
                wx, wy = window.read("AXPosition")
                class CountButton:
                    def read(self, key):
                        return {"AXPosition": (wx + 380, wy + 28 + 20), "AXSize": (100, 28)}[key]
                native_click(CountButton())
                ax.wait_for(lambda: state()["clicks"] == 1 and state()["focus"] == "Count", "Native ordinary button did not establish pixel-test focus")
                target = BUILD / ("web-" + prepared["engine"] + "-" + variant + "-" + mode + "-pixels.png")
                previous = None
                for _ in range(10):
                    ax.capture_window(process.pid, target, include_shadow=False)
                    current = Image.open(target).convert("RGB")
                    if previous is not None and ImageChops.difference(previous, current).getbbox() is None:
                        break
                    previous = current
                    time.sleep(0.15)
                else:
                    raise AssertionError("Native browser/window rendering did not settle")
                check(state()["name"] == "Native field", "Pixel capture preserves the original 4D value")
                report["pixels"] = {"sha256": sha(target), "size": list(current.size)}
            elif not args.read_only:
                native_click(name)
                ax.wait_for(lambda: app.read("AXFocusedUIElement").same_as(name), "Native web editor did not receive actual application focus")
                check(name.set_text("After") == 0, "HTML text accepts its native AX value replacement")
                ax.wait_for(lambda: name.read("AXValue") == "After", "Native HTML value replacement was not observed")
                check(enabled.press() == 0, "HTML checkbox accepts its native AX press")
                ax.wait_for(lambda: enabled.read("AXValue") == 0, "Native HTML checkbox did not toggle")
                native_click(more)
                ax.wait_for(lambda: more.read("AXValue") is True and any(e.read("AXValue") == "Expanded content." for e in descendants(web())), "Native details activation did not reveal content")
                check(True, "Native pointer disclosure exposes the expanded content")
                native_key(more, 49)
                ax.wait_for(lambda: more.read("AXValue") is False and not any(e.read("AXValue") == "Expanded content." for e in descendants(web())), "Native details collapse did not remove content")
                check(True, "Native keyboard disclosure removes collapsed content")
                check(reset.press() == 0, "HTML reset accepts its native AX press")
                ax.wait_for(lambda: name.read("AXValue") == "Before" and enabled.read("AXValue") == 1, "Native HTML reset did not restore values")
                check(True, "Browser-owned reset restores the original HTML values")
                native_click(email)
                ax.wait_for(lambda: app.read("AXFocusedUIElement").same_as(email), "Invalid email editor did not receive actual native focus")
                check(email.set_text("invalid-address") == 0 and submit.press() == 0, "Invalid HTML email is submitted through native accessibility")
                ax.wait_for(lambda: app.read("AXFocusedUIElement").same_as(email), "Browser validation did not focus the invalid email")
                check(not any(item["path"] == "/submit" for item in requests), "Native browser validation prevents the invalid submission")
                native_key(email, 48, 1 << 17)
                ax.wait_for(lambda: app.read("AXFocusedUIElement").same_as(name), "Name editor did not receive actual native focus")
                check(name.set_text("After") == 0, "Focused HTML name accepts the submission value")
                ax.wait_for(lambda: name.read("AXValue") == "After", "Name replacement did not finish")
                native_key(name, 48)
                ax.wait_for(lambda: app.read("AXFocusedUIElement").same_as(email), "Native Tab did not focus the email editor")
                check(email.set_text("after@example.test") == 0, "Focused HTML email accepts the submission value")
                ax.wait_for(lambda: email.read("AXValue") == "after@example.test", "Email replacement did not finish")
                check(submit.press() == 0, "Valid HTML submission accepts its native AX press")
                ax.wait_for(lambda: any(item["path"] == "/submit" for item in requests), "No native browser submission reached the local endpoint")
                received = next(item for item in requests if item["path"] == "/submit")
                check(received["query"] == {"name": ["After"], "email": ["after@example.test"], "enabled": ["on"]}, "The local endpoint receives the browser's actual submitted values")
                check(require("AXLink", "Back to fixture").press() == 0, "Native browser link returns to the form")
                name = require("AXTextField", "Name")
                ax.wait_for(lambda: name.read("AXValue") == "Before", "Returned HTML form did not load its initial values")
                ax.wait_for(lambda: sum(event["code"] == 49 for event in state()["events"] if event["kind"] == "web") == 3, "Original web handlers did not receive all completed navigations")
                report["browserEvents"] = [event for event in state()["events"] if event["kind"] == "web"]
                check(sum(event["code"] == 1 for event in report["browserEvents"]) == 1, "Original web load and navigation handlers complete without a reported error")
                if not prepared["baseline"]:
                    field = window.find("/Name")
                    count = window.find("/Count")
                    check(field.set_text("Host edit") == 0, "Ordinary 4D text accepts an AX edit after web navigation")
                    ax.wait_for(lambda: field.read("AXValue") == "Host edit" and bridge_root.read("AXHelp") == "Text entered in the editor; normal validation runs when editing ends", "Ordinary native editor replacement did not finish")
                    check(count.press() == 0, "Ordinary 4D button accepts AX activation after web navigation")
                    ax.wait_for(lambda: state()["clicks"] == 1 and state()["name"] == "Host edit", "Original 4D handler or editor commit did not complete")
                    check([event for event in state()["events"] if event["kind"] == "button"] == [{"kind": "button", "code": 4, "object": "Count"}], "The original 4D button handler runs exactly once")
                    native_click(name)
                    ax.wait_for(lambda: app.read("AXFocusedUIElement").same_as(name), "Focus did not return to native HTML")
                    check(state()["clicks"] == 1 and state()["name"] == "Host edit", "Native web focus preserves 4D data and handler count")
            if args.voiceover:
                caption = vo.key("home", command=True)
                captions = [caption]
                inside_ordinary = False
                checkbox_done = disclosure_done = False
                for _ in range(32):
                    captions.append(vo.key("right"))
                    if "Close fixture" in captions[-1] and inside_ordinary:
                        captions.append(vo.key("up", shift=True))
                        inside_ordinary = False
                        continue
                    if any(captions[-1].lower().rstrip().endswith(kind) for kind in ("group", "scroll area", "html content", "web content")):
                        inside_ordinary = "AX native web fixture" in captions[-1]
                        captions.append(vo.key("down", shift=True))
                    if "Enabled" in captions[-1] and "checkbox" in captions[-1] and not checkbox_done:
                        enabled = require("AXCheckBox", "Enabled")
                        captions.append(vo.key("space"))
                        ax.wait_for(lambda: enabled.read("AXValue") == 0, "VoiceOver did not uncheck the native HTML checkbox")
                        check(True, "VoiceOver activates the native HTML checkbox")
                        captions.append(vo.key("space"))
                        ax.wait_for(lambda: enabled.read("AXValue") == 1, "VoiceOver did not restore the native HTML checkbox")
                        checkbox_done = True
                    if "More information" in captions[-1] and "summary" in captions[-1] and not disclosure_done:
                        more = require("AXDisclosureTriangle", "More information")
                        captions.append(vo.key("space"))
                        ax.wait_for(lambda: more.read("AXValue") is True, "VoiceOver did not expand the native HTML disclosure")
                        check(True, "VoiceOver expands the native HTML disclosure")
                        captions.append(vo.key("right"))
                        check("Expanded content" in captions[-1], "VoiceOver reads the newly disclosed HTML content")
                        captions.append(vo.key("left"))
                        captions.append(vo.key("space"))
                        ax.wait_for(lambda: more.read("AXValue") is False, "VoiceOver did not collapse the native HTML disclosure")
                        disclosure_done = True
                    if "Next page" in captions[-1]:
                        break
                def spoken(*parts):
                    return any(all(part.lower() in caption.lower() for part in parts) for caption in captions)
                check(all(spoken(*parts) for parts in (("Native web fixture", "heading level 1"), ("Name", "edit text"), ("Email", "email field"), ("Enabled", "checkbox"), ("Submit fixture", "button"))), "VoiceOver reads the HTML heading, editors, checkbox and submit button with their roles")
                check(spoken("Native field", "edit text") and spoken("Count", "button") and spoken("Close fixture", "button"), "VoiceOver also reaches the ordinary 4D editor and buttons in the same window")
                report["readingOrder"] = "Ordinary 4D group, including Close below the web area, precedes the sibling native web content; visual interleaving is not supported"
                check(checkbox_done and disclosure_done, "VoiceOver restores the original HTML checkbox and disclosure states")
                vo.stop()
            report["finalState"] = state()
            report["passed"] = True
    except BaseException as error:
        report["failure"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        if vo is not None:
            vo.stop()
        if window is not None and process.poll() is None:
            report["finalAX"] = [describe(e) for e in descendants(window)]
            ax.capture_window(process.pid, BUILD / ("web-" + prepared["engine"] + "-" + variant + "-" + mode + "-final.png"), include_shadow=False)
        if process is not None and process.poll() is None:
            (resources / "close.json").write_text("{}")
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)
                report["passed"] = False
        report["exitCode"] = process.returncode if process else None
        if report["exitCode"] != 0:
            report["passed"] = False
        if (resources / "closed.json").exists():
            report["closed"] = json.loads((resources / "closed.json").read_text(encoding="utf-8-sig"))
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        report["requests"] = requests
        payload = json.dumps(report, indent=2) + "\n"
        stem = "web-" + prepared["engine"] + "-" + variant + "-" + case + "-" + mode
        (BUILD / (stem + ".json")).write_text(payload)
        (BUILD / (stem + "-" + uuid.uuid4().hex + ".json")).write_text(payload)
    assert report["passed"]


if __name__ == "__main__":
    main()
