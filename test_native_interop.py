#!/usr/bin/env python3
"""External AX hit tests and actions against disposable native and web controls."""
import argparse
import ctypes as c
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent / "tests"))
import mac_ax as ax


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Launch the owned fixture on an unlocked desktop")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    binary = root / "build/NativeInteropFixture"
    subprocess.run([
        "xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
        "-I", str(root / "src"), str(root / "tests/NativeInteropFixture.mm"),
        str(root / "src/Session.mm"), str(root / "src/Grid.mm"), str(root / "src/Bridge.mm"), str(root / "src/GridNative.mm"),
        "-framework", "Cocoa", "-framework", "WebKit", "-o", str(binary),
    ], check=True)
    if not args.run:
        print("Built native interoperability fixture; use --run on an unlocked desktop.")
        return
    if not ax.trusted():
        parser.error("The invoking process needs macOS Accessibility permission")
    equal = ax.signature(ax.CF, "CFEqual", c.c_bool, c.c_void_p, c.c_void_p)
    def same(left, right):
        return equal(left.pointer, right.pointer)

    checks = []

    def check(condition, message):
        if not condition:
            raise AssertionError(message)
        print("PASS:", message, flush=True)
        checks.append(message)

    with tempfile.TemporaryDirectory(prefix="axb-native-interop-") as directory:
        directory = Path(directory)
        with (root / "build/native-interop-host.log").open("w") as log:
            process = subprocess.Popen([str(binary), str(directory)], stdout=log, stderr=log)
        app = ax.application(process.pid)
        sequence = 0
        command_phase = "startup"
        observer = c.c_void_p()
        notifications = []
        run_loop = ax.signature(ax.CF, "CFRunLoopGetCurrent", c.c_void_p)()
        default_mode = c.c_void_p.in_dll(ax.CF, "kCFRunLoopDefaultMode").value
        run_loop_mode = ax.signature(ax.CF, "CFRunLoopRunInMode", c.c_int, c.c_void_p, c.c_double, c.c_bool)
        source = None

        def pump():
            run_loop_mode(default_mode, 0.08, False)

        callback_type = c.CFUNCTYPE(None, c.c_void_p, c.c_void_p, c.c_void_p, c.c_void_p)

        @callback_type
        def notified(_observer, pointer, notification, _context):
            element = ax.Element(ax.retain(pointer))
            focused = app.read("AXFocusedUIElement")
            notifications.append({"phase": command_phase, "name": ax.convert(notification), "id": element.read("AXIdentifier"),
                                  "value": element.read("AXValue"),
                                  "focused": focused.read("AXIdentifier") if focused else None})

        def observe(element, name):
            key = ax.make_string(None, name.encode(), ax.UTF8)
            try:
                error = ax.signature(ax.AX, "AXObserverAddNotification", c.c_int,
                                     c.c_void_p, c.c_void_p, c.c_void_p, c.c_void_p)(observer, element.pointer, key, None)
                if error:
                    raise AssertionError(f"Cannot observe {name}: {error}")
            finally:
                ax.release(key)

        def command(operation):
            nonlocal sequence, command_phase
            command_phase = operation
            sequence += 1
            temporary = directory / "next.json"
            temporary.write_text(json.dumps({"id": sequence, "operation": operation}))
            os.replace(temporary, directory / "command.json")

            def completed():
                pump()
                if process.poll() is not None:
                    raise RuntimeError("Owned interoperability fixture exited")
                try:
                    state = json.loads((directory / "state.json").read_text())
                    return state if state["command"] == sequence else None
                except (OSError, ValueError):
                    return None
            return ax.wait_for(completed, f"Fixture command timed out: {operation}", timeout=20)

        def find(identifier=None, title=None):
            pending = [app]
            for _ in range(2000):
                if not pending:
                    return None
                element = pending.pop()
                if ((identifier and element.read("AXIdentifier") == identifier)
                        or (title and element.read("AXTitle") == title and element.read("AXRole") == "AXButton")):
                    return element
                pending.extend(x for x in element.read("AXChildren") or [] if isinstance(x, ax.Element))
            raise AssertionError("Fixture tree contains a cycle or exceeds its bound")

        def hit(element):
            position, size = element.read("AXPosition"), element.read("AXSize")
            return app.at_position(position[0] + size[0] / 2, position[1] + size[1] / 2)

        try:
            state = command("read")
            check(state["pid"] == process.pid and state["ready"], "owned local WebKit fixture is ready")
            button = ax.wait_for(lambda: find("native.button"), "Native button absent")
            first = find("native.first")
            second = find("native.second")
            web = ax.wait_for(lambda: find(title="Web action"), "Native web button absent")
            expected_presses = 0
            for phase in ["baseline", "attach", "refresh", "move"]:
                if phase != "baseline":
                    command(phase)
                for label, element in [("button", button), ("editor", first), ("web button", web)]:
                    target = hit(element)
                    check(same(target, element), f"{phase}: external hit preserves native {label}")
                expected_presses += 1
                check(hit(button).press() == 0 and command("read")["presses"] == expected_presses,
                      f"{phase}: native action works")
                expected_web = int(command("read")["webPresses"]) + 1
                check(hit(web).press() == 0 and int(command("read")["webPresses"]) == expected_web,
                      f"{phase}: web action works")
                if phase != "baseline":
                    proxy = app.find(".proxy")
                    check(not proxy.is_settable("AXFocused"), f"{phase}: non-focusable bridge button does not advertise a focus setter")
                    target = hit(proxy)
                    check(same(target, proxy), f"{phase}: external hit finds bridge control")
                    group = proxy.read("AXParent")
                    check((group.read("AXIdentifier") or "").startswith("axb.window.") and
                          any(same(child, proxy) for child in group.read("AXChildren") or []),
                          f"{phase}: virtual group and control agree on parentage")
                    table = app.find(".table")
                    row = (table.read("AXRows") or [])[0]
                    check(table.is_settable("AXSelectedRows"), f"{phase}: legacy table selection advertises its setter without recursion")
                    check(row.is_settable("AXSelected"), f"{phase}: legacy row selection advertises its setter without recursion")
                    cell = (row.read("AXChildren") or [])[0]
                    check(same(hit(cell), cell), f"{phase}: external hit finds deepest bridge cell")
            command("lateChild")
            late = find("native.late")
            check(same(hit(late), late), "native children added after attachment remain hittable")
            check(first.set_boolean("AXFocused", True) == 0, "native editor accepts focus")
            command("focusProxy")
            check((app.read("AXFocusedUIElement").read("AXIdentifier") or "").endswith(".editor"), "bridge focus is exposed")
            error = ax.signature(ax.AX, "AXObserverCreate", c.c_int, c.c_int, callback_type, c.POINTER(c.c_void_p))(
                process.pid, notified, c.byref(observer))
            if error:
                raise AssertionError(f"Cannot create fixture observer: {error}")
            source = ax.signature(ax.AX, "AXObserverGetRunLoopSource", c.c_void_p, c.c_void_p)(observer)
            ax.signature(ax.CF, "CFRunLoopAddSource", None, c.c_void_p, c.c_void_p, c.c_void_p)(run_loop, source, default_mode)
            window = app.read("AXWindows")[0]
            proxy_editor = app.find(".editor")
            observe(window, "AXLayoutChanged")
            observe(proxy_editor, "AXValueChanged")
            observe(proxy_editor, "AXSelectedTextChanged")
            command("editProxy")
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline and not any(n["name"] == "AXValueChanged" for n in notifications):
                pump()
            pump()
            check(any(n["name"] == "AXValueChanged" and n["value"] == "Updated proxy value" and
                      n["focused"] == proxy_editor.read("AXIdentifier") for n in notifications),
                  "value observer reads committed text and current focus")
            check(any(n["name"] == "AXSelectedTextChanged" for n in notifications), "selection changes notify the external client")
            check(not any(n["name"] == "AXLayoutChanged" for n in notifications), "ordinary text changes do not announce layout changes")
            check(second.set_boolean("AXFocused", True) == 0, "another native editor accepts focus")
            command("nativeFocus")
            focused = app.read("AXFocusedUIElement")
            check(same(focused, second), "leaving bridge restores current native editor focus")
            command("detach")
            check(not (group.read("AXChildren") or []), "retained virtual root is empty after detach")
            for label, element in [("button", button), ("editor", second), ("web button", web), ("late button", late)]:
                check(same(hit(element), element), f"detach: external hit preserves native {label}")
            sources = ["src/Bridge.mm", "src/Session.mm", "tests/NativeInteropFixture.mm", "test_native_interop.py", "tests/mac_ax.py"]
            (root / "build/native-interop-report.json").write_text(json.dumps({"passed": True, "checks": checks,
                "notifications": notifications, "sources": {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}}, indent=2) + "\n")
        finally:
            if source:
                ax.signature(ax.CF, "CFRunLoopRemoveSource", None, c.c_void_p, c.c_void_p, c.c_void_p)(run_loop, source, default_mode)
            if observer.value:
                ax.release(observer)
            if process.poll() is None:
                sequence += 1
                (directory / "command.json").write_text(json.dumps({"id": sequence, "operation": "quit"}))
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
