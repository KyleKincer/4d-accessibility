#!/usr/bin/env python3
"""External AX and optional VoiceOver checks of the production outline seam.

The owned AppKit fixture supplies synthetic topology. This is not 4D hierarchy
discovery, native disclosure-action or Symphony workflow acceptance.
"""
import argparse
import ctypes as c
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))

COMPILE_SOURCES = ["src/Session.mm", "src/Grid.mm", "src/Bridge.mm", "src/GridNative.mm",
                   "src/NativeLayout.mm", "src/DrawnText.mm", "src/MessageDialogs.mm", "src/ProgressWindows.mm", "tests/NativeOutlineFixture.mm"]
SOURCES = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "src").glob("*") if p.is_file()) + [
    "tests/NativeOutlineFixture.mm", "test_native_outlines.py", "tests/mac_ax.py", "tests/voiceover.py", "tests/ReadScreen.swift"]
TITLE = "AXB native outline fixture"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    args = parser.parse_args()
    if args.voiceover and not args.run:
        parser.error("--voiceover requires --run")
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    path = build / ("native-outline-voiceover.json" if args.voiceover else "native-outline.json")
    report = {"passed": False, "checks": [], "voiceover": [], "scope": __doc__.strip()}

    def save():
        path.write_text(json.dumps(report, indent=2) + "\n")

    save()
    report["sourceSHA256"] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}
    import mac_ax as ax
    binary = build / "NativeOutlineFixture"
    subprocess.run(["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-g", "-I", str(ROOT / "src"),
                    *[str(ROOT / name) for name in COMPILE_SOURCES],
                    "-framework", "Cocoa", "-framework", "CoreText", "-framework", "QuartzCore", "-o", str(binary)], check=True)
    report["binarySHA256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    save()
    if not args.run:
        print("Built native outline fixture; use --run on an unlocked desktop.")
        return
    ax.require_test_input()
    if not ax.trusted():
        parser.error("The invoking process needs its existing Accessibility permission")
    if args.voiceover:
        from voiceover import VoiceOver
        if VoiceOver.pids("VoiceOver") or VoiceOver.pids("VoiceOver Quickstart"):
            parser.error("Existing VoiceOver session belongs to the user")
    run_id = uuid.uuid4().hex
    report["runID"] = run_id

    def check(condition, description):
        assert condition, description
        report["checks"].append(description)
        print("PASS:", description, flush=True)

    def attribute(element, name):
        key = ax.make_string(None, name.encode(), ax.UTF8)
        value = c.c_void_p()
        try:
            error = ax.copy_attribute(element.pointer, key, c.byref(value))
            return error, ax.convert(value.value) if value.value else None
        finally:
            if value.value:
                ax.release(value.value)
            ax.release(key)

    with tempfile.TemporaryDirectory(prefix="axb-native-outline-") as directory:
        directory = Path(directory)
        process = None
        vo = None
        sequence = 0
        normal = False
        with (build / "native-outline.log").open("w") as log:
            try:
                process = subprocess.Popen([str(binary), str(directory), run_id], stdout=log, stderr=log)
                report["pid"] = process.pid

                def state():
                    try:
                        value = json.loads((directory / "state.json").read_text())
                        assert value["pid"] == process.pid and value["runID"] == run_id
                        return value
                    except (FileNotFoundError, json.JSONDecodeError):
                        return None

                def command(operation):
                    nonlocal sequence
                    assert process.poll() is None
                    sequence += 1
                    temporary = directory / "command.tmp"
                    temporary.write_text(json.dumps({"runID": run_id, "id": sequence, "operation": operation}))
                    temporary.replace(directory / "command.json")
                    if operation != "quit":
                        ax.wait_for(lambda: state() and state()["command"] == sequence, "Fixture command timed out", timeout=10)

                ax.wait_for(state, "Outline fixture did not start", timeout=10)
                app = ax.application(process.pid)
                windows = app.read("AXWindows")
                check(len(windows) == 1 and windows[0].read("AXTitle") == TITLE, "one exact owned native outline window")
                pending = [windows[0]]
                outline = None
                while pending:
                    item = pending.pop()
                    if item.read("AXRole") == "AXOutline":
                        outline = item
                        break
                    pending.extend(item.read("AXChildren") or [])
                check(outline is not None, "production provider exposes AXOutline")
                check(outline.read("AXRoleDescription") == "outline", "outline role description matches its actual native role")
                check(outline.count("AXRows") == 25 and outline.count("AXColumns") == 2, "outline counts all disclosed logical rows")
                check(len(outline.read("AXVisibleRows")) == 10, "viewport rows remain separate from disclosed rows")
                rows = outline.slice("AXRows", 0, 5)
                first, nested, leaf, second_leaf, later = rows
                for row, level in zip(rows, (0, 1, 2, 2, 0)):
                    check(row.read("AXDisclosureLevel") == level and row.read("AXParent").same_as(outline), "outline row keeps structural parent and exact disclosure level")
                    error, value = attribute(row, "AXSelected")
                    check(error in (-25205, -25212) and value is None and not row.is_settable("AXSelected"), "unknown row selection is absent through external AX")
                    check("AXPress" not in row.actions(), "read-only outline row has no invented selection action")
                for child, parent in ((nested, first), (leaf, nested), (second_leaf, nested)):
                    check(child.read("AXDisclosedByRow").same_as(parent), "logical parent relationship resolves the exact group")
                check(first.read("AXDisclosing") is True and later.read("AXDisclosing") is False, "known expanded and collapsed group states remain distinct")
                check([item.read("AXIdentifier") for item in first.read("AXDisclosedRows")] == [nested.read("AXIdentifier")], "group discloses only its direct child rows")
                check(len(nested.read("AXDisclosedRows")) == 2, "nested group exposes both direct leaves")
                check(attribute(leaf, "AXDisclosing")[1] is None, "leaf does not masquerade as a collapsed group")
                error, value = attribute(outline, "AXSelectedRows")
                check(error in (-25205, -25212) and value is None and not outline.is_settable("AXSelectedRows"), "unknown complete selection is absent through external AX")
                for row in (first, nested, later):
                    check(not row.is_settable("AXDisclosing"), "unimplemented disclosure action is not advertised")
                first_cell = outline.cell(0, 0)
                check(first_cell.read("AXValue") == "Repeated group" and len(first.read("AXChildren")) == 1,
                      "group exposes its immediate label and one structural cell")
                try:
                    absent = outline.cell(1, 0) is None
                except RuntimeError as error:
                    absent = str(error) == "AX indexed cell failed: 1, 0, -25212"
                check(absent, "group cannot expose other backing columns")
                check(attribute(first_cell, "AXSelected")[1] is None, "group cell cannot invent unknown selected state")
                content = first_cell.read("AXChildren")[0]
                check(content.read("AXRole") == "AXStaticText" and content.read("AXValue") == "Repeated group" and not content.is_settable("AXValue"),
                      "group content has no editor or loading placeholder")
                check(attribute(content, "AXSelected")[1] is None, "group label cannot invent unknown selected state")
                check(first.read("AXSize")[0] == 500 and first_cell.read("AXSize")[0] == 500, "native group geometry spans its complete row")
                far = outline.slice("AXRows", 24, 1)[0]
                far_cell = outline.cell(0, 24)
                check(far.read("AXIndex") == 24 and far.read("AXSize")[1] > 0 and far_cell.read("AXSize")[1] > 0,
                      "offscreen disclosed row retains logical index and nonempty bounds")
                ax.wait_for(lambda: far_cell.read("AXValue") == "Distant leaf", "Distant outline value did not load", timeout=10)
                check(far_cell.read("AXValue") == "Distant leaf", "offscreen leaf values arrive through the existing page cache")
                if args.voiceover:
                    ocr = build / "ReadScreen"
                    subprocess.run(["xcrun", "swiftc", str(ROOT / "tests/ReadScreen.swift"), "-o", str(ocr)], check=True)
                    vo = VoiceOver(process, None, TITLE, build / "native-outline-captions", ocr)
                    report["voiceover"] = vo.steps
                    vo.start()
                    caption = vo.key("home")
                    for _ in range(4):
                        if "Grouped items" in caption:
                            break
                        caption = vo.key("right")
                    report["voiceoverEntryCaption"] = caption
                    check("Grouped items" in caption and outline.read("AXRole") == "AXOutline", "VoiceOver reaches the owned logical outline")
                    caption = vo.key("down", shift=True)
                    captions = [caption]
                    for _ in range(7):
                        captions.append(vo.key("right"))
                    text = " ".join(captions)
                    check("Repeated group" in text and any("Nested group" in caption and "level 1" in caption for caption in captions) and
                          any("leaf/1" in caption and "level 2" in caption for caption in captions),
                          "VoiceOver reads repeated groups, nested ancestry and original leaf values")
                    check("not responding" not in text.lower() and "selected" not in text.lower(),
                          "unknown-selection outline remains responsive without inventing selected state")
                    caption = vo.key("end")
                    check("root/19" in caption and "25" in caption, "VoiceOver End reaches the final disclosed row and column")
                    caption = vo.key("left")
                    check("Distant leaf" in caption, "VoiceOver reaches the final disclosed offscreen leaf")
                    vo.stop()
                command("collapse")
                ax.wait_for(lambda: outline.count("AXRows") == 22 and first.read("AXDisclosing") is False, "Outline collapse did not publish", timeout=10)
                check(outline.slice("AXRows", 0, 1)[0].same_as(first) and not first.read("AXDisclosedRows"), "external collapse preserves the group and removes disclosed descendants")
                check(leaf.read("AXRole") is None and nested.read("AXRole") is None, "collapsed descendants retire retained AX handles")
                command("expand")
                ax.wait_for(lambda: outline.count("AXRows") == 25 and first.read("AXDisclosing") is True, "Outline reopening did not publish", timeout=10)
                check(not outline.slice("AXRows", 2, 1)[0].same_as(leaf), "reopening reacquires fresh descendant handles")
                command("knownSelection")
                ax.wait_for(lambda: outline.read("AXSelectedRows") is not None, "Authoritative selection did not publish", timeout=10)
                check(len(outline.read("AXSelectedRows")) == 1 and outline.read("AXSelectedRows")[0].same_as(later) and later.read("AXSelected") is True,
                      "authoritative selection is exposed when the provider supplies it")
                command("unknownSelection")
                ax.wait_for(lambda: attribute(outline, "AXSelectedRows")[0] in (-25205, -25212), "Unknown selection did not retire the attribute", timeout=10)
                check(attribute(later, "AXSelected")[1] is None, "returning to unknown selection removes retained row state")
                command("replace")
                ax.wait_for(lambda: first.read("AXRole") is None, "Replacement did not retire the group", timeout=10)
                check(not outline.slice("AXRows", 0, 1)[0].same_as(first), "replacement generation retires group identity")
                report["finalState"] = state()
                command("quit")
                process.wait(timeout=10)
                closed = json.loads((directory / "closed.json").read_text())
                normal = process.returncode == 0 and closed == {"runID": run_id, "pid": process.pid}
                check(normal, "owned fixture exits normally with matching close evidence")
                check(report["sourceSHA256"] == {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}, "recorded production sources stay unchanged during acceptance")
                report["passed"] = True
            except BaseException as error:
                report["error"] = repr(error)
                raise
            finally:
                if vo and vo.owned:
                    try:
                        vo.stop()
                    except BaseException as error:
                        report["voiceoverCleanupError"] = repr(error)
                        report["passed"] = False
                if process and process.poll() is None:
                    try:
                        command("quit")
                        process.wait(timeout=5)
                    except BaseException:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill(); process.wait(timeout=5)
                    report["passed"] = False
                report["normalClose"] = normal
                report["exitCode"] = process.returncode if process else None
                report["count"] = len(report["checks"])
                save()
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
