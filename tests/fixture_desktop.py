"""Known startup notices for disposable, explicitly owned 4D test processes."""
import ctypes as c
from pathlib import Path
import subprocess
import time

import mac_ax as ax


def press_key(process, project, title, expected_focus, key_code, modifiers=0):
    """Send a test key only to the still-focused editor of the owned fixture."""
    assert process.poll() is None, "Owned fixture has exited"
    command = subprocess.check_output(["ps", "-p", str(process.pid), "-o", "command="], text=True)
    assert f"--project {Path(project).resolve()}" in command and "/4D.app/Contents/MacOS/4D" in command, "Owned fixture identity changed"
    app = ax.application(process.pid)
    assert app.read("AXFrontmost") is True, "Owned fixture lost foreground"
    assert any(window.read("AXTitle") == title for window in app.read("AXWindows") or []), "Owned fixture window missing"
    focused = app.read("AXFocusedUIElement")
    assert isinstance(focused, ax.Element) and focused.read("AXIdentifier") == expected_focus, "Owned editor lost focus"
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    create = ax.signature(graphics, "CGEventCreateKeyboardEvent", c.c_void_p, c.c_void_p, c.c_uint16, c.c_bool)
    flags = ax.signature(graphics, "CGEventSetFlags", None, c.c_void_p, c.c_uint64)
    post = ax.signature(graphics, "CGEventPostToPid", None, c.c_int, c.c_void_p)
    for down in (True, False):
        event = create(None, key_code, down)
        flags(event, modifiers)
        post(process.pid, event)
        ax.release(event)
        time.sleep(0.1)


def activate_fixture(process, project, title):
    """Activate an already-open owned fixture after its real window exists."""
    project = Path(project).resolve()
    command = subprocess.check_output(["ps", "-p", str(process.pid), "-o", "command="], text=True)
    assert f"--project {project}" in command and "/4D.app/Contents/MacOS/4D" in command
    assert subprocess.check_output(["pgrep", "-x", "4D"], text=True).split() == [str(process.pid)]
    app = ax.application(process.pid)
    window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == title), None), "Owned fixture window is missing")
    if app.read("AXFrontmost") is not True:
        # Licensed startup has no notice to activate the app. LaunchServices
        # activates this existing instance after window creation has finished.
        subprocess.run(["/usr/bin/open", "-a", "/Applications/4D/4D.app"], check=True, timeout=10)
    ax.wait_for(lambda: app.read("AXFrontmost") is True, "Owned fixture did not activate")
    ax.wait_for(lambda: app.read("AXFocusedWindow") and app.read("AXFocusedWindow").read("AXTitle") == title, "Owned fixture window did not receive keyboard focus")
    return app, window


def wait_for_start(process, project, ready, build, timeout=40, area_list_demo=False, area_list_title="AreaList Pro 11.4.2"):
    """Acknowledge only the vendor's application-mode notice, if it appears."""
    project = Path(project).resolve()
    deadline = time.monotonic() + timeout
    acknowledged = False
    demo_acknowledged = False
    executable = build / "read-fixture-screen"
    source = Path(__file__).with_name("ReadScreen.swift")
    if not executable.exists() or executable.stat().st_mtime < source.stat().st_mtime:
        subprocess.run(["/usr/bin/xcrun", "swiftc", str(source), "-o", str(executable)], check=True, timeout=30)
    expected = "No license has been found. The application will be started in application mode."
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Owned 4D process exited before form startup: {process.returncode}")
        value = ready()
        if value:
            return value, acknowledged
        if not acknowledged:
            image = build / "fixture-startup.png"
            try:
                ax.capture_window(process.pid, image)
            except RuntimeError:
                time.sleep(0.25)
                continue
            text = subprocess.check_output([str(executable), str(image)], text=True, timeout=10)
            if expected in " ".join(text.split()):
                command = subprocess.check_output(["ps", "-p", str(process.pid), "-o", "command="], text=True)
                assert f"--project {project}" in command and "/4D.app/Contents/MacOS/4D" in command, "Owned project identity changed"
                app = ax.application(process.pid)
                if app.read("AXFrontmost") is not True:
                    assert app.set_boolean("AXFrontmost", True) == 0, "Cannot activate owned fixture"
                    ax.wait_for(lambda: app.read("AXFrontmost") is True, "Owned fixture did not activate")
                    continue  # Recheck the visible notice after activation.
                assert ax.application(process.pid).read("AXFrontmost") is True, "Owned license notice is not frontmost"
                graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
                create = ax.signature(graphics, "CGEventCreateKeyboardEvent", c.c_void_p, c.c_void_p, c.c_uint16, c.c_bool)
                post = ax.signature(graphics, "CGEventPostToPid", None, c.c_int, c.c_void_p)
                flags = ax.signature(graphics, "CGEventSetFlags", None, c.c_void_p, c.c_uint64)
                for down in (True, False):
                    event = create(None, 36, down)
                    flags(event, 0)
                    post(process.pid, event)
                    ax.release(event)
                    time.sleep(0.1)
                acknowledged = True
                print("Acknowledged the owned fixture's application-mode license notice", flush=True)
        if area_list_demo and not demo_acknowledged:
            app = ax.application(process.pid)
            notices = [w for w in app.read("AXWindows") or [] if w.read("AXTitle") == area_list_title]
            if len(notices) == 1:
                notice = notices[0]
                image = build / "fixture-alp-demo.png"
                ax.capture_window(process.pid, image)
                text = " ".join(subprocess.check_output([str(executable), str(image)], text=True, timeout=10).split())
                expected_demo = "the demonstration version of AreaList Pro."
                if expected_demo in text and "fully functional for 20 minutes" in text:
                    command = subprocess.check_output(["ps", "-p", str(process.pid), "-o", "command="], text=True)
                    assert f"--project {project}" in command and "/4D.app/Contents/MacOS/4D" in command
                    assert app.read("AXFrontmost") is True, "Owned demo notice is not frontmost"
                    assert notice.read("AXSize") == (440, 208), "Unknown vendor demo notice layout"
                    x, y = notice.read("AXPosition")

                    class Point(c.Structure):
                        _fields_ = [("x", c.c_double), ("y", c.c_double)]

                    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
                    create = ax.signature(graphics, "CGEventCreateMouseEvent", c.c_void_p, c.c_void_p, c.c_uint32, Point, c.c_uint32)
                    post = ax.signature(graphics, "CGEventPost", None, c.c_uint32, c.c_void_p)
                    set_integer = ax.signature(graphics, "CGEventSetIntegerValueField", None, c.c_void_p, c.c_uint32, c.c_longlong)
                    for kind in (5, 1, 2):
                        event = create(None, kind, Point(x + 380, y + 179), 0)
                        set_integer(event, 1, 1)
                        post(1, event)  # kCGSessionEventTap, the current login session
                        ax.release(event)
                        time.sleep(0.08)
                    demo_acknowledged = True
                    print("Acknowledged the owned fixture's documented AreaList demo notice", flush=True)
        time.sleep(0.25)
    raise AssertionError("Owned 4D form did not start; no unrecognized dialog was accepted")
