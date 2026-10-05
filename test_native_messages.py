#!/usr/bin/env python3
"""Standard 4D ALERT, CONFIRM and Request windows through accessibility, with the plugin installed.

A disposable copy of tests/native-messages gains the built plugin and a startup method that
opens five standard windows in turn. Each window is read and operated only through
accessibility (or VoiceOver with --voiceover); 4D's own result is recorded after each one.
--run needs an unlocked desktop and Accessibility permission. --voiceover starts its own
VoiceOver session, refuses an existing one, and reads speech with VoiceOver's AppleScript
`last phrase`, so "Allow VoiceOver to be controlled with AppleScript" must be enabled.
--baseline records each window from the plugin-free project, advancing with Return only as
setup; a later --run compares its windows, before any action, with that baseline.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
BUILD = ROOT / "build"
FIXTURE = BUILD / "native-messages-fixture"
PIXELS = BUILD / "native-messages-pixels"
PHASES = ("confirm-cancel", "confirm-accept", "confirm-immediate", "alert", "request-accept", "request-reject", "request-empty")
BUNDLE = BUILD / "AccessibilityBridge.bundle"
DESKTOP = Path("/Applications/4D/4D.app/Contents/MacOS/4D")

STARTUP = '''// Standard windows in turn; each phase is recorded before its window opens.
var $answer : Text
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "confirm-cancel"; "compiled"; Is compiled mode)))
CONFIRM("Discard the draft order?"; "Discard"; "Keep")
File("/RESOURCES/results.json").setText(JSON Stringify(New object("confirmCancel"; OK)))
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "confirm-accept")))
CONFIRM("Send the invoice now?"; "Send"; "Later")
File("/RESOURCES/results.json").setText(JSON Stringify(New object("confirmCancel"; JSON Parse(File("/RESOURCES/results.json").getText()).confirmCancel; "confirmAccept"; OK)))
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "confirm-immediate")))
CONFIRM("Archive the report?"; "Archive"; "Cancel")
File("/RESOURCES/immediate.json").setText(JSON Stringify(New object("ok"; OK)))
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "alert")))
ALERT("The export finished."; "Close")
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "request-accept")))
$answer:=Request("Name for the saved search:"; "Open orders"; "Save"; "Cancel")
File("/RESOURCES/request.json").setText(JSON Stringify(New object("answer"; $answer; "ok"; OK)))
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "request-reject")))
$answer:=Request("Reason for the change:"; "None"; "Apply"; "Skip")
File("/RESOURCES/reject.json").setText(JSON Stringify(New object("answer"; $answer; "ok"; OK)))
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "request-empty")))
$answer:=Request("Optional note:"; ""; "Add"; "Skip")
File("/RESOURCES/empty.json").setText(JSON Stringify(New object("answer"; $answer; "ok"; OK)))
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "complete")))
QUIT 4D
'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare(plugin=True):
    if FIXTURE.exists():
        shutil.rmtree(FIXTURE)
    shutil.copytree(ROOT / "tests/native-messages", FIXTURE)
    (FIXTURE / "Resources").mkdir(exist_ok=True)
    if plugin:
        (FIXTURE / "Plugins").mkdir(exist_ok=True)
        shutil.copytree(BUNDLE, FIXTURE / "Plugins/AccessibilityBridge.bundle")
    (FIXTURE / "Project/Sources/DatabaseMethods/onStartup.4dm").write_text(STARTUP)
    for name in ("phase.json", "results.json", "request.json", "reject.json", "empty.json", "immediate.json"):
        (FIXTURE / "Resources" / name).unlink(missing_ok=True)


def read(name):
    try:
        return json.loads((FIXTURE / "Resources" / name).read_text(encoding="utf-8-sig"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--baseline", action="store_true", help="Record the plugin-free windows for pixel comparison")
    parser.add_argument("--compiled", action="store_true", help="Compile the fixture with --server and run it compiled")
    parser.add_argument("--server", type=Path, help="4D Server.app used only as the compiler for --compiled")
    args = parser.parse_args()
    if args.compiled and not args.server:
        raise SystemExit("--compiled needs --server /path/to/4D Server.app")
    if args.baseline:
        return baseline(args)
    if not BUNDLE.is_dir():
        raise SystemExit("Build the plugin first: python3 build.py")
    prepare()
    if args.compiled:
        compile_fixture(args.server)
    print("Prepared " + str(FIXTURE))
    if not args.run:
        return
    import mac_ax as ax
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    ax.require_test_input()
    report = {"passed": False, "mode": "compiled" if args.compiled else "interpreted", "architecture": "x86_64" if args.intel else "arm64", "voiceover": args.voiceover,
              "pluginSHA256": sha(BUNDLE / "Contents/MacOS/AccessibilityBridge"), "checks": [], "results": {}}
    checks = report["checks"]

    def check(condition, description):
        assert condition, description
        checks.append(description)
        print("PASS: " + description, flush=True)

    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/NativeMessages.4DProject"), "--dataless", "--opening-mode", report["mode"],
               "--webadmin-auto-start", "false"]
    if args.intel:
        command = ["/usr/bin/arch", "-x86_64"] + command
    vo = heard = None
    if args.voiceover:
        import voiceover_session as vo
        heard = vo.Listener()
        vo.start()
        heard.start()
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Only speech during the fixture's own run is recorded; other applications are not.
    spoken = [heard.mark() if heard else 0, None]

    def front():
        subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                       capture_output=True)

    def wait_phase(phase, timeout=90):
        limit = time.time() + timeout
        while time.time() < limit:
            if read("phase.json").get("phase") == phase:
                return
            assert process.poll() is None, "4D exited before " + phase
            time.sleep(0.2)
        raise AssertionError("4D did not reach " + phase)

    reference = PIXELS / ("baseline-" + report["architecture"])
    captured = PIXELS / report["architecture"]
    shutil.rmtree(captured, ignore_errors=True)
    captured.mkdir(parents=True)
    report["pixels"] = {}

    def compare(phase):
        """Compare the untouched window with the plugin-free baseline, before any action."""
        if args.voiceover or not (reference / (phase + ".png")).exists():
            return
        time.sleep(1.5)
        ax.capture_window(process.pid, captured / (phase + ".png"), include_shadow=False)
        changed = changed_pixels(reference / (phase + ".png"), captured / (phase + ".png"))
        report["pixels"][phase] = changed
        check(changed == 0, phase + " window is pixel-identical to the plugin-free window")

    def elements(expected):
        """Wait for the published message window and return its elements by object name."""
        app = ax.application(process.pid)
        limit = time.time() + 30
        found = {}
        while time.time() < limit:
            front()
            found = {}
            for window in app.read("AXWindows") or []:
                for child in window.read("AXChildren") or []:
                    identifier = child.read("AXIdentifier") or ""
                    if identifier.startswith("axb/message/"):
                        found[identifier.split("/")[-1]] = child
            if set(found) == set(expected):
                return found
            time.sleep(0.3)
        raise AssertionError("Published message elements " + repr(sorted(found)) + " differ from " + repr(sorted(expected)))

    def phrase_until(predicate, since, timeout=30):
        limit = time.time() + timeout
        while time.time() < limit:
            for at, phrase in heard.since(since):
                if predicate(phrase):
                    return phrase
            time.sleep(0.1)
        raise AssertionError("VoiceOver did not say the expected phrase; heard " + repr([p for _, p in heard.since(since)][-5:]))

    try:
        # CONFIRM, cancelled.
        wait_phase("confirm-cancel")
        check(read("phase.json").get("compiled") is args.compiled, "4D runs in the requested " + report["mode"] + " mode")
        nodes = elements(["main", "cancel", "ok"])
        compare("confirm-cancel")
        check(nodes["main"].read("AXRole") == "AXStaticText" and nodes["main"].read("AXValue") == "Discard the draft order?", "CONFIRM message is readable static text")
        check(nodes["ok"].read("AXRole") == "AXButton" and nodes["ok"].read("AXDescription") == "Discard" and
              nodes["cancel"].read("AXDescription") == "Keep", "CONFIRM buttons carry their titles")
        if args.voiceover:
            check("Discard the draft order?" in phrase_until(lambda p: "Discard the draft order?" in p, 0), "VoiceOver reads the CONFIRM message when it opens")
            since = heard.mark(); vo.key("left", vo.VO)
            check(phrase_until(lambda p: p.startswith("Keep button"), since), "VoiceOver moves to the cancel button")
            vo.key("space", vo.VO)
        else:
            check(nodes["cancel"].press() == 0, "the cancel button is pressed through accessibility")
        wait_phase("confirm-accept")
        check(read("results.json").get("confirmCancel") == 0, "CONFIRM returns OK = 0 for its cancel button")
        # CONFIRM, accepted.
        nodes = elements(["main", "cancel", "ok"])
        compare("confirm-accept")
        check(nodes["main"].read("AXValue") == "Send the invoice now?", "a second CONFIRM publishes its own message")
        if args.voiceover:
            check("Send button" in phrase_until(lambda p: "Send button" in p, 0), "VoiceOver lands on the default button")
            vo.key("space", vo.VO)
        else:
            check(nodes["ok"].press() == 0, "the default button is pressed through accessibility")
        wait_phase("confirm-immediate")
        check(read("results.json").get("confirmAccept") == 1, "CONFIRM returns OK = 1 for its default button")
        # A press the moment the window is published, as a fast automation client makes it.
        nodes = elements(["main", "cancel", "ok"])
        if args.voiceover:
            phrase_until(lambda p: "Archive button" in p, 0)
            vo.key("space", vo.VO)
        else:
            check(nodes["ok"].press() == 0, "a press is accepted as soon as the window is published")
        wait_phase("alert", 10)
        check(read("immediate.json").get("ok") == 1, "a press made as soon as the window appears takes effect without a retry")
        # ALERT.
        nodes = elements(["main", "ok"])
        compare("alert")
        check(nodes["main"].read("AXValue") == "The export finished." and nodes["ok"].read("AXDescription") == "Close", "ALERT message and button are readable")
        if args.voiceover:
            check("The export finished." in phrase_until(lambda p: "The export finished." in p, 0), "VoiceOver reads the ALERT message")
            phrase_until(lambda p: "Close button" in p, 0)
            vo.key("space", vo.VO)
        else:
            check(nodes["ok"].press() == 0, "the ALERT button is pressed through accessibility")
        wait_phase("request-accept")
        checks.append("ALERT closes through its published button")
        # Request, answered and accepted.
        nodes = elements(["main", "box", "cancel", "ok"])
        compare("request-accept")
        check(nodes["box"].read("AXRole") == "AXTextField" and nodes["box"].read("AXValue") == "Open orders", "Request field exposes its default answer")
        focused = ax.application(process.pid).read("AXFocusedUIElement")
        check(isinstance(focused, ax.Element) and focused.read("AXIdentifier") == "axb/message/box" and nodes["box"].read("AXFocused") is True,
              "the Request field is the application's focused element")
        check(nodes["box"].read("AXSelectedTextRange") is not None, "the Request field reports its selection")
        if args.voiceover:
            check("Open orders" in phrase_until(lambda p: "Open orders" in p, 0), "VoiceOver reads the Request field")
            typing = heard.mark()
            vo.type_text("Late shipments")
            limit = time.time() + 15
            while time.time() < limit and nodes["box"].read("AXValue") != "Late shipments":
                time.sleep(0.2)
            check(nodes["box"].read("AXValue") == "Late shipments", "typed text reaches the published field value")
            time.sleep(2)
            echo = [p for _, p in heard.since(typing)]
            report["typingEcho"] = echo
            check(any(p.replace(" ", "") and set(p.replace(" ", "")) <= set("Lateshipments") for p in echo), "VoiceOver echoes the typed characters")
            since = heard.mark(); vo.key("right", vo.VO); vo.key("right", vo.VO)
            check(phrase_until(lambda p: p.startswith("Save button"), since), "VoiceOver reaches the Request default button")
            vo.key("space", vo.VO)
        else:
            check(nodes["box"].is_settable("AXValue") and nodes["box"].set_text("Late shipments") == 0, "the Request answer is written through accessibility")
            limit = time.time() + 15
            while time.time() < limit and nodes["box"].read("AXValue") != "Late shipments":
                time.sleep(0.2)
            check(nodes["box"].read("AXValue") == "Late shipments", "the written answer is the field's value")
            check(nodes["ok"].press() == 0, "the Request default button is pressed through accessibility")
        wait_phase("request-reject")
        check(read("request.json") == {"answer": "Late shipments", "ok": 1}, "Request returns the entered answer with OK = 1")
        # Request, rejected.
        nodes = elements(["main", "box", "cancel", "ok"])
        compare("request-reject")
        check(nodes["main"].read("AXValue") == "Reason for the change:" and nodes["cancel"].read("AXDescription") == "Skip", "a second Request publishes its own text")
        if args.voiceover:
            since = heard.mark(); vo.key("right", vo.VO)
            check(phrase_until(lambda p: p.startswith("Skip button"), since), "VoiceOver reaches the Request cancel button")
            vo.key("space", vo.VO)
        else:
            check(nodes["cancel"].press() == 0, "the Request cancel button is pressed through accessibility")
        wait_phase("request-empty")
        check(read("reject.json").get("ok") == 0, "Request returns OK = 0 for its cancel button")
        # Request without a default answer; the field stays published while empty.
        nodes = elements(["main", "box", "cancel", "ok"])
        compare("request-empty")
        check(nodes["box"].read("AXValue") == "" and nodes["box"].read("AXFocused") is True, "an empty Request field is published and focused")

        def value_becomes(expected):
            limit = time.time() + 15
            while time.time() < limit and nodes["box"].read("AXValue") != expected:
                time.sleep(0.2)
            return nodes["box"].read("AXValue") == expected
        if args.voiceover:
            check(phrase_until(lambda p: "Optional note:" in p, 0), "VoiceOver reads the empty Request")
            typed = heard.mark()
            vo.type_text("Hi")
            check(value_becomes("Hi"), "typed text reaches the empty field")
            # Let VoiceOver finish the echo and its hint, so the deletion is a new phrase.
            quiet, count, limit = time.time(), heard.mark(), time.time() + 15
            while time.time() < limit and time.time() - quiet < 2:
                if heard.mark() != count:
                    quiet, count = time.time(), heard.mark()
                time.sleep(0.1)
            deleting = heard.mark()
            vo.key("delete")
            check(value_becomes("H"), "Delete removes the last character")
            check(phrase_until(lambda p: p.split()[:1] == ["i"] or "deleted" in p, deleting, 10), "VoiceOver announces the deleted character")
            since = heard.mark(); vo.key("right", vo.VO); vo.key("right", vo.VO)
            check(phrase_until(lambda p: p.startswith("Add button"), since), "VoiceOver reaches the Add button")
            spoken[1] = heard.mark()
            vo.key("space", vo.VO)
            expected = {"answer": "H", "ok": 1}
        else:
            check(nodes["box"].set_text("Note") == 0 and value_becomes("Note"), "an answer is written into the empty field")
            check(nodes["box"].set_text("") == 0 and value_becomes("") and elements(["main", "box", "cancel", "ok"]),
                  "clearing the answer keeps the field published")
            check(nodes["box"].set_text("Final") == 0 and value_becomes("Final"), "a new answer replaces the cleared one")
            check(nodes["ok"].press() == 0, "the empty Request's default button is pressed through accessibility")
            expected = {"answer": "Final", "ok": 1}
        wait_phase("complete")
        check(read("empty.json") == expected, "Request returns the answer typed into the initially empty field")
        process.wait(30)
        report["results"] = {"confirm": read("results.json"), "request": read("request.json"), "reject": read("reject.json"), "empty": read("empty.json")}
        report["passed"] = True
    finally:
        if heard:
            heard.stop()
            run = [p for _, p in heard.since(spoken[0])][:None if spoken[1] is None else spoken[1] - spoken[0]]
            first = next((i for i, p in enumerate(run) if "Discard the draft order?" in p), len(run))
            report["speech"] = run[first:]
        if vo:
            vo.stop()
        if process.poll() is None:
            process.terminate()
            process.wait(20)
        name = "native-messages-" + report["architecture"] + ("-compiled" if args.compiled else "") + ("-voiceover" if args.voiceover else "") + ".json"
        (BUILD / name).write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(checks)} standard-message checks ({report['architecture']}, {report['mode']}{', VoiceOver' if args.voiceover else ''})")


def rgba(path):
    """Decode a capture to premultiplied RGBA bytes with ImageIO; no third-party imaging package."""
    import ctypes as c
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    imageio = c.CDLL("/System/Library/Frameworks/ImageIO.framework/ImageIO")
    foundation = c.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")

    class Rect(c.Structure):
        _fields_ = [("x", c.c_double), ("y", c.c_double), ("width", c.c_double), ("height", c.c_double)]

    def bind(library, name, result, *arguments):
        function = getattr(library, name)
        function.restype, function.argtypes = result, arguments
        return function

    url = bind(foundation, "CFURLCreateFromFileSystemRepresentation", c.c_void_p, c.c_void_p, c.c_char_p, c.c_long, c.c_bool)
    release = bind(foundation, "CFRelease", None, c.c_void_p)
    source_create = bind(imageio, "CGImageSourceCreateWithURL", c.c_void_p, c.c_void_p, c.c_void_p)
    image_create = bind(imageio, "CGImageSourceCreateImageAtIndex", c.c_void_p, c.c_void_p, c.c_size_t, c.c_void_p)
    width_of = bind(graphics, "CGImageGetWidth", c.c_size_t, c.c_void_p)
    height_of = bind(graphics, "CGImageGetHeight", c.c_size_t, c.c_void_p)
    space_create = bind(graphics, "CGColorSpaceCreateDeviceRGB", c.c_void_p)
    context_create = bind(graphics, "CGBitmapContextCreate", c.c_void_p, c.c_void_p, c.c_size_t, c.c_size_t, c.c_size_t, c.c_size_t, c.c_void_p, c.c_uint32)
    draw = bind(graphics, "CGContextDrawImage", None, c.c_void_p, Rect, c.c_void_p)
    encoded = str(path).encode()
    location = url(None, encoded, len(encoded), False)
    source = source_create(location, None)
    image = image_create(source, 0, None) if source else None
    try:
        if not image:
            raise RuntimeError("Cannot decode " + str(path))
        width, height = width_of(image), height_of(image)
        buffer = (c.c_ubyte * (width * height * 4))()
        space = space_create()
        context = context_create(buffer, width, height, 8, width * 4, space, 1)
        draw(context, Rect(0, 0, width, height), image)
        release(context)
        release(space)
        return (width, height), bytes(buffer)
    finally:
        for value in (image, source, location):
            if value:
                release(value)


def changed_pixels(first, second):
    (size, a), (other, b) = rgba(first), rgba(second)
    if size != other:
        return size[0] * size[1]
    return sum(1 for index in range(0, len(a), 4) if a[index:index + 4] != b[index:index + 4])


def compile_fixture(server_app):
    """Compile the prepared fixture for both desktop architectures with 4D Server's Compile project."""
    import plistlib
    from build_component import literal, project_at, run_utility
    server_app = server_app.expanduser().resolve()
    info = plistlib.loads((server_app / "Contents/Info.plist").read_bytes())
    driver = BUILD / ("native-messages-compile-" + uuid.uuid4().hex)
    project_at(driver, "Driver")
    try:
        result = run_utility(server_app / "Contents/MacOS" / info["CFBundleExecutable"], driver,
                             '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
                             + f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
                             + f'$result:=Compile project(File({literal(FIXTURE / "Project/NativeMessages.4DProject")}); $options)', 120)
    finally:
        shutil.rmtree(driver, ignore_errors=True)
    if result.get("success") is not True or result.get("errors"):
        raise SystemExit("Fixture compilation failed: " + json.dumps(result))


def baseline(args):
    """Capture each standard window from the project without the plugin installed."""
    import mac_ax as ax
    import voiceover_session as keys
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise SystemExit("Close 4D first")
    ax.require_test_input()
    prepare(plugin=False)
    architecture = "x86_64" if args.intel else "arm64"
    target = PIXELS / ("baseline-" + architecture)
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir(parents=True)
    command = [str(DESKTOP), "--project", str(FIXTURE / "Project/NativeMessages.4DProject"), "--dataless", "--opening-mode", "interpreted",
               "--webadmin-auto-start", "false"]
    if args.intel:
        command = ["/usr/bin/arch", "-x86_64"] + command
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        def front():
            subprocess.run(["osascript", "-e", f'tell application "System Events" to set frontmost of (first process whose unix id is {process.pid}) to true'],
                           capture_output=True)
            ax.wait_for(lambda: ax.application(process.pid).read("AXFrontmost") is True, "4D did not come to the front", timeout=15)

        for index, phase in enumerate(PHASES):
            limit = time.time() + 90
            while read("phase.json").get("phase") != phase:
                assert time.time() < limit and process.poll() is None, "4D did not reach " + phase
                time.sleep(0.2)
            front()
            time.sleep(3)
            front()  # Captured only as the active window, as the plugin run sees it.
            ax.capture_window(process.pid, target / (phase + ".png"), include_shadow=False)
            following = PHASES[index + 1] if index + 1 < len(PHASES) else "complete"
            for _ in range(3):
                if process.poll() is not None:
                    break
                front()
                keys.key("return")  # Setup only: the plugin-free window has no accessible controls.
                limit = time.time() + 10
                while time.time() < limit and read("phase.json").get("phase") != following and process.poll() is None:
                    time.sleep(0.2)
                if read("phase.json").get("phase") == following:
                    break
            assert read("phase.json").get("phase") == following, "Return did not advance past " + phase
        process.wait(60)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(20)
    print("Recorded " + str(len(PHASES)) + " plugin-free windows in " + str(target))


if __name__ == "__main__":
    main()
