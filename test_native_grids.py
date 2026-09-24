#!/usr/bin/env python3
"""External AX validation of production logical grids in an owned native window."""
import argparse
import ctypes as c
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true", help="Also verify whole-table navigation with the owned VoiceOver session")
    args = parser.parse_args()
    binary = ROOT / "build/NativeGridFixture"
    subprocess.run([
        "xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-g", "-I", str(ROOT / "src"),
        *[str(ROOT / path) for path in ["src/Session.mm", "src/Grid.mm", "src/Bridge.mm", "src/GridNative.mm", "tests/NativeGridFixture.mm"]],
        "-framework", "Cocoa", "-o", str(binary),
    ], check=True)
    if not args.run:
        print("Built native grid fixture; use --run on an unlocked desktop.")
        return
    if not ax.trusted():
        parser.error("The invoking process needs its existing Accessibility permission")
    import doctor
    if not doctor.desktop_session()["unlocked"]:
        parser.error("The desktop is locked")
    checks = []
    equal = ax.signature(ax.CF, "CFEqual", c.c_bool, c.c_void_p, c.c_void_p)

    def same(left, right):
        return isinstance(left, ax.Element) and isinstance(right, ax.Element) and equal(left.pointer, right.pointer)

    def check(condition, description):
        if not condition:
            raise AssertionError(description)
        checks.append(description)
        print("PASS:", description, flush=True)

    with tempfile.TemporaryDirectory(prefix="axb-native-grid-") as directory:
        directory = Path(directory)
        with (ROOT / "build/native-grid-host.log").open("w") as log:
            process = subprocess.Popen([str(binary), str(directory)], stdout=log, stderr=log)
        sequence = 0
        voiceover_steps = []

        def state():
            try:
                value = json.loads((directory / "state.json").read_text())
                assert value["pid"] == process.pid
                return value
            except (FileNotFoundError, json.JSONDecodeError):
                return None

        def command(operation):
            nonlocal sequence
            assert process.poll() is None
            sequence += 1
            temporary = directory / "command.tmp"
            temporary.write_text(json.dumps({"id": sequence, "operation": operation}))
            temporary.replace(directory / "command.json")
            if operation != "quit":
                ax.wait_for(lambda: state() and state()["command"] == sequence, "Fixture command timed out", timeout=15)

        try:
            ax.wait_for(state, "Grid fixture did not start", timeout=15)
            app = ax.application(process.pid)
            windows = app.read("AXWindows")
            check(len(windows) == 1 and windows[0].read("AXTitle") == "AXB complete logical grid fixture", "exact owned native grid window")
            pending = [windows[0]]
            table = None
            while pending:
                item = pending.pop()
                if item.read("AXRole") == "AXTable":
                    table = item
                    break
                pending.extend(item.read("AXChildren") or [])
            check(table is not None, "logical table is discoverable without traversing its rows")
            check(not table.cell(0, 0).is_settable("AXValue"), "read-only cell does not advertise AXValue mutation")
            check(table.count("AXRows") == 50000 and table.count("AXColumns") == 24, "native counts include every logical row and column")
            check(len(table.read("AXVisibleRows")) == 12, "visible rows are a separate viewport subset")
            check(len(table.read("AXColumnHeaderUIElements")) == 24, "all columns have header relationships")
            for index in (0, 24999, 49999):
                rows = table.slice("AXRows", index, 1)
                check(len(rows) == 1 and rows[0].read("AXIndex") == index, f"indexed row {index + 1} has its logical position")
                check(same(rows[0].read("AXParent"), table), f"row {index + 1} belongs to its table")
            far_row = table.slice("AXRows", 49999, 1)[0]
            far = table.cell(23, 49999)
            identity = far.read("AXIdentifier")
            check(same(far.read("AXParent"), far_row), "far cell belongs to its stable row")
            check(far.read("AXRowIndexRange") == (49999, 1) and far.read("AXColumnIndexRange") == (23, 1), "far cell has full row and column index ranges")
            first_value = far.read("AXValue")
            check(first_value == "Loading", "uncached external read reports loading")
            ax.wait_for(lambda: far.read("AXValue") == "row-49999 / column-23 / value-0", "Asynchronous far cell did not load", timeout=15)
            check(True, "owning provider supplies the offscreen value on a later cycle")
            check(far.read("AXSize") == (240.0, 28.0), "offscreen cell retains its actual layout bounds for VoiceOver navigation")
            check(not any(same(far, visible) for visible in table.read("AXVisibleCells")), "offscreen layout does not invent viewport visibility")
            check("AXPress" not in far.actions() and "AXScrollToVisible" in far.actions(), "read-only cells expose reveal without inventing edit or selection actions")
            check("AXScrollToVisible" in far.read("AXChildren")[0].actions(), "the readable offscreen content offers the same reveal action as its cell")
            visible = table.cell(1, 0)
            position, size = visible.read("AXPosition"), visible.read("AXSize")
            content = visible.read("AXChildren")[0]
            check(content.read("AXRole") == "AXStaticText" and same(content.read("AXParent"), visible), "a structural cell contains its readable text")
            check(same(app.at_position(position[0] + size[0] / 2, position[1] + size[1] / 2), content), "position lookup reaches visible cell text without scanning 50000 rows")
            check(table.count("AXChildren") == 50025, "complete children include rows columns and one header group")
            if args.voiceover:
                from voiceover import VoiceOver
                ocr = ROOT / "build/read-fixture-screen"
                subprocess.run(["xcrun", "swiftc", str(ROOT / "tests/ReadScreen.swift"), "-o", str(ocr)], check=True)
                vo = VoiceOver(process, None, "AXB complete logical grid fixture", ROOT / "build/native-grid-voiceover", ocr)
                try:
                    vo.start()
                    voiceover_steps = vo.steps
                    vo.key("home")
                    vo.key("down", shift=True)
                    caption = vo.key("end")
                    check("50000" in caption.replace(",", "").replace(" ", ""), "VoiceOver End reaches logical row 50000")
                    ax.wait_for(lambda: state()["firstRow"] == 49988 and state()["firstColumn"] == 21, "VoiceOver did not reveal the final cell", timeout=15)
                    check(any(same(far, visible) for visible in table.read("AXVisibleCells")), "VoiceOver reveals the final cell inside the actual viewport")
                    caption = vo.key("right")
                    check("49999" in caption and "23" in caption, "VoiceOver reads the final row and column value")
                    voiceover_steps = vo.steps
                finally:
                    vo.stop()
            command("sort")
            ax.wait_for(lambda: far.read("AXRowIndexRange") == (0, 1), "Retained row did not follow sort", timeout=15)
            check(same(table.cell(23, 0), far) and far.read("AXIdentifier") == identity, "sorting preserves the same row and cell objects by key")
            ax.wait_for(lambda: far.read("AXValue") == "row-49999 / column-23 / value-0", "Sorted cell did not reload", timeout=15)
            check(True, "post-sort loading resolves current positions without changing identity")
            command("values")
            ax.wait_for(lambda: far.read("AXValue") == "row-49999 / column-23 / value-1", "Changed cell value did not refresh", timeout=15)
            check(True, "cached values refresh independently of the form revision")
            command("remove")
            check(table.count("AXRows") == 49999 and far.read("AXSize") in (None, (0.0, 0.0)), "removed row retires retained geometry and changes logical count")
            retained = table.cell(0, 0)
            command("replace")
            fresh = table.cell(0, 0)
            check(not same(fresh, retained) and fresh.read("AXIdentifier") != retained.read("AXIdentifier"), "replacement creates new identities even for the same row key")
            command("quit")
            process.wait(timeout=10)
            check(process.returncode == 0, "owned grid host exits normally")
            sources = ["src/Session.mm", "src/Grid.mm", "src/GridNative.mm", "src/Bridge.mm", "src/BridgePrivate.h", "tests/NativeGridFixture.mm", "tests/mac_ax.py", "test_native_grids.py"]
            (ROOT / "build/native-grid-report.json").write_text(json.dumps({"checks": checks, "count": len(checks), "voiceover": voiceover_steps, "sources_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sources}}, indent=2) + "\n")
        except Exception as error:
            (ROOT / "build/native-grid-report.json").write_text(json.dumps({
                "passed": False, "error": str(error), "checks": checks,
                "final_state": state(), "voiceover": voiceover_steps,
            }, indent=2) + "\n")
            raise
        finally:
            if process.poll() is None:
                command("quit")
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
