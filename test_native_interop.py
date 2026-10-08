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
        str(root / "src/Session.mm"), str(root / "src/Grid.mm"), str(root / "src/Bridge.mm"), str(root / "src/GridNative.mm"), str(root / "src/NativeLayout.mm"), str(root / "src/DrawnText.mm"), str(root / "src/InternalForms.mm"), str(root / "src/InternalTable.mm"), str(root / "src/MessageDialogs.mm"), str(root / "src/ProgressWindows.mm"), str(root / "src/QueryEditor.mm"), str(root / "src/QuickReport.mm"), str(root / "src/OrderByEditor.mm"), str(root / "src/GenericForms.mm"),
        "-framework", "Cocoa", "-framework", "WebKit", "-framework", "CoreText", "-framework", "QuartzCore", "-lz", "-o", str(binary),
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
    regressions = []
    states = []
    passed = False

    def check(condition, message):
        if not condition:
            raise AssertionError(message)
        print("PASS:", message, flush=True)
        checks.append(message)

    def regression(condition, message):
        regressions.append({"name": message, "passed": bool(condition)})
        print(("PASS: " if condition else "FAIL: ") + message, flush=True)

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
            state = ax.wait_for(completed, f"Fixture command timed out: {operation}", timeout=20)
            states.append({"operation": operation, "state": state})
            return state

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
            check(state["containerClass"] == "NSView" and state["metadata"]["role"] == "AXUnknown",
                  "the bridge-free plain container has the expected native default role")
            button = ax.wait_for(lambda: find("native.button"), "Native button absent")
            first = find("native.first")
            second = find("native.second")
            def ready_web():
                candidate = find(title="Web action")
                return candidate if candidate is not None and same(hit(candidate), candidate) else None
            # WebKit can replace its first remote AX handle during initial
            # layout. Readiness uses the current handle, not a retained one.
            web = ax.wait_for(ready_web, "Native WebKit hit provider did not become ready", timeout=10)
            expected_presses = 0
            for phase in ["baseline", "attach", "refresh", "move"]:
                if phase != "baseline":
                    if phase == "attach":
                        command("hideWeb")
                        command("attach")
                        retained_root = find("axb/form")
                        check(retained_root is not None, "the web-free form uses its separate virtual root")
                        command("showWeb")
                        regression(not (retained_root.read("AXChildren") or []), "a retained separate root stops exposing children after native composition")
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
                    proxy = app.find("/proxy")
                    check(not proxy.is_settable("AXFocused"), f"{phase}: non-focusable bridge button does not advertise a focus setter")
                    target = hit(proxy)
                    check(same(target, proxy), f"{phase}: external hit finds bridge control")
                    group = proxy.read("AXParent")
                    status = find("axb/form")
                    check(status is not None and same(status.read("AXParent"), group) and
                          not (status.read("AXChildren") or []) and
                          any(same(child, proxy) for child in group.read("AXChildren") or []),
                          f"{phase}: bridge status and controls share the native parent")
                    children = group.read("AXChildren") or []
                    check(any(same(child, first) for child in children) and
                          all(same(child.read("AXParent"), group) for child in children),
                          f"{phase}: native and virtual root children agree on parentage")
                    check(len(children) == len({child.pointer for child in children}),
                          f"{phase}: mixed root children are not duplicated")
                    check(command("read")["metadata"]["order"][-1] == "axb/form",
                          f"{phase}: the complete navigation order leaves the empty status group last")
                    table = app.find("/table")
                    row = (table.read("AXRows") or [])[0]
                    check(table.is_settable("AXSelectedRows"), f"{phase}: legacy table selection advertises its setter without recursion")
                    check(row.is_settable("AXSelected"), f"{phase}: legacy row selection advertises its setter without recursion")
                    cell = (row.read("AXChildren") or [])[0]
                    check(same(hit(cell), cell), f"{phase}: external hit finds deepest bridge cell")
            for role in ("text", "group", "button", "revealable"):
                command("overlap." + role)
                proxy, overlay = app.find("/proxy"), app.find("/overlay")
                regression(same(hit(proxy), overlay if role == "button" else proxy),
                      f"overlapping {role}: external hit follows form control arbitration and clipping")
                if role == "revealable":
                    x, y = overlay.read("AXPosition")
                    regression(same(app.at_position(x + 10, y + 10), overlay), "a clipped revealable control remains hittable inside its viewport")
            command("clearOverlap")
            command("lateChild")
            late = find("native.late")
            check(same(hit(late), late), "native children added after attachment remain hittable")
            command("refresh")
            check(ax.wait_for(lambda: command("read")["lateOrdered"] and command("read")["orderComplete"],
                              "New native child missing from navigation order", timeout=5),
                  "the next publication includes the newly added native control in navigation order")
            check(proxy.press() == 0, "bridge action accepts one request")
            check(status.read("AXHelp") == "Action queued", "root receipt changes immediately when an action queues")
            command("deliverAction")
            check(status.read("AXHelp") == "Waiting for the application to complete the action", "root distinguishes delivery from completion")
            command("completeAction")
            check(status.read("AXHelp") == "Native fixture completed", "root exposes the exact host completion message")
            check(first.set_boolean("AXFocused", True) == 0, "native editor accepts focus")
            command("focusProxy")
            check((app.read("AXFocusedUIElement").read("AXIdentifier") or "").endswith("/editor"), "bridge focus is exposed")
            error = ax.signature(ax.AX, "AXObserverCreate", c.c_int, c.c_int, callback_type, c.POINTER(c.c_void_p))(
                process.pid, notified, c.byref(observer))
            if error:
                raise AssertionError(f"Cannot create fixture observer: {error}")
            source = ax.signature(ax.AX, "AXObserverGetRunLoopSource", c.c_void_p, c.c_void_p)(observer)
            ax.signature(ax.CF, "CFRunLoopAddSource", None, c.c_void_p, c.c_void_p, c.c_void_p)(run_loop, source, default_mode)
            window = app.read("AXWindows")[0]
            proxy_editor = app.find("/editor")
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
            command("hideWeb")
            check(not (group.read("AXIdentifier") or "").startswith("axb/") and command("read")["metadataRestored"],
                  "hiding the only web area restores the native container metadata")
            command("showWeb")
            check(same(proxy.read("AXParent"), group), "showing the web area restores mixed containment")
            command("addWeb")
            auxiliary = ax.wait_for(lambda: find(title="Auxiliary web action"), "Second native web area missing")
            command("refresh")
            check(same(hit(auxiliary), auxiliary) and same(hit(web), web) and command("read")["orderComplete"],
                  "two native web areas retain their own providers and complete mixed navigation order")
            command("removeWeb")
            check(find(title="Auxiliary web action") is None and command("read")["orderComplete"],
                  "removing a web area removes its native tree and navigation stop")
            command("resize")
            check(same(hit(web), web) and same(hit(second), second), "resizing preserves native web and editor hit testing")
            command("replaceContainer")
            replacement = proxy.read("AXParent")
            check(not same(replacement, group) and command("read")["previousMetadataRestored"],
                  "replacing the native container restores the retired container")
            check(same(hit(proxy), proxy) and same(hit(web), web), "container replacement preserves virtual and native hits")
            # The host reparented its physical controls. AppKit may retire
            # their old AX handles; inspect the current native elements.
            button, first, second, late = (find(identifier) for identifier in
                                           ("native.button", "native.first", "native.second", "native.late"))
            check(first.read("AXValue") == "First native value" and second.read("AXValue") == "Second native value",
                  "host container replacement preserves the native editor values")
            command("hostMetadata")
            check(command("read")["metadata"]["label"] == "Host-updated group" and
                  same(proxy.read("AXParent"), replacement),
                  "a newer host metadata assignment wins over the bridge")
            state = command("detach")
            check(state["metadataRestored"], "detach restores native metadata getter values and computed navigation")
            check(not (status.read("AXChildren") or []), "retained bridge status is empty after detach")
            check(proxy.press() != 0, "retained bridge action is unusable after detach")
            for label, element in [("button", button), ("editor", second), ("web button", web), ("late button", late)]:
                check(same(hit(element), element), f"detach: external hit preserves native {label}")
            old_session = state["session"]
            state = command("reopen")
            fresh = app.find("/proxy")
            check(state["session"] != old_session and not same(fresh, proxy), "restart allocates a new session and virtual element")
            check(proxy.press() != 0 and same(hit(fresh), fresh), "restart keeps retained old actions unusable")
            check(command("detach")["metadataRestored"], "repeated detach restores the host's newer metadata")
            command("customNavigation")
            command("reopen")
            check(command("read")["customNavigationPreserved"] and not command("read")["metadata"]["element"],
                  "a distinct custom host navigation order keeps the original integration path")
            check(same(hit(find("native.button")), find("native.button")) and same(hit(web), web),
                  "custom navigation fallback preserves native controls and web hit testing")
            check(command("detach")["customNavigationPreserved"], "custom host navigation remains unchanged after detach")
            for kind in ("legacyContainer", "customChildrenContainer"):
                command(kind)
                command("tooltip")
                command("reopen")
                fresh = app.find("/proxy")
                regression(not command("read")["metadata"]["element"],
                      f"{kind}: incompatible native provider keeps the separate virtual root")
                if kind == "legacyContainer":
                    regression(fresh is not None and fresh.read("AXParent").read("AXIdentifier") == "axb/form" and same(hit(fresh), fresh),
                               "legacy ignored container: the separate bridge root remains discoverable and hittable")
                else:
                    check(fresh is None, "a custom children provider omitting the drawing anchor cannot enumerate bridge controls")
                # A custom provider can omit the drawing anchor entirely.
                # Fallback preserves that native provider; it cannot invent
                # bridge enumeration behind its custom children override.
                check(same(hit(find("native.button")), find("native.button")), f"{kind}: native controls remain hittable")
                command("detach")
                command("changeTooltip")
                regression(command("read")["metadata"]["help"] == "Changed native tooltip",
                           f"{kind}: rejected composition preserves computed native help")
            command("focusableContainer")
            command("reopen")
            command("focusProxy")
            command("focusContent")
            regression(not command("detach")["focusedIsContainer"], "detach leaves no application focus override on the restored ignored native container")
            command("replaceContainer")
            command("detach")
            command("tooltip")
            check(command("read")["metadata"]["help"] == "Original native tooltip", "bridge-free help follows the native tooltip")
            command("changeTooltip")
            check(command("read")["metadata"]["help"] == "Changed native tooltip", "bridge-free help follows a tooltip change")
            command("tooltip")
            command("reopen")
            command("detach")
            command("changeTooltip")
            regression(command("read")["metadata"]["help"] == "Changed native tooltip", "detach preserves computed native help after its source changes")
            command("replaceContainer")
            command("reopen")
            state = command("hostRole")
            check(state["metadata"]["role"] == "AXLayoutArea" and not state["metadata"]["element"],
                  "a newer host role assignment yields composition without overwriting the role")
            check(command("detach")["metadataRestored"], "the newer host role survives detach")
            command("replaceContainer")
            command("hostGroup")
            state = command("reopen")
            check(state["metadata"]["role"] == "AXGroup" and not state["metadata"]["element"],
                  "an existing host group role keeps the original integration path")
            check(command("detach")["metadataRestored"], "the existing host group role survives detach")
            assert all(case["passed"] for case in regressions), "Native composition regression failures"
            passed = True
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
            sources = ["src/Bridge.mm", "src/BridgePrivate.h", "src/Session.mm", "src/Grid.mm", "src/GridNative.mm", "src/NativeLayout.mm",
                       "tests/NativeInteropFixture.mm", "test_native_interop.py", "tests/mac_ax.py"]
            failure = sys.exc_info()[1]
            (root / "build/native-interop-report.json").write_text(json.dumps({"passed": passed, "checks": checks,
                "failure": str(failure) if failure else None, "states": states, "exitCode": process.returncode,
                "notifications": notifications, "regressions": regressions,
                "sources": {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}}, indent=2) + "\n")


if __name__ == "__main__":
    main()
