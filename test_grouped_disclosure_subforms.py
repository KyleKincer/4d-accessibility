#!/usr/bin/env python3
"""Verify disclosure ownership and no ancestor reveal in repeated children."""
import argparse
import json
import platform
import subprocess
import sys
import time
import uuid

from build_component import BUILD, ROOT, sha
from prepare_hierarchy_probe import canonical_sources
from summarize_grouped_outlines import validate_prepared
from test_hierarchy_probe import finish_run, read_json

TITLE = "AX native hierarchy probe"
SOURCES = ("test_grouped_disclosure_subforms.py", "build_component.py", "prepare_hierarchy_probe.py", "summarize_grouped_outlines.py",
           "test_hierarchy_probe.py", "tests/hierarchy_subforms.py", "tests/mac_ax.py", "tests/fixture_desktop.py")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.add_argument("--compiled", action="store_true")
    args = parser.parse_args()
    mode = "compiled" if args.compiled else "interpreted"
    report_path = BUILD / ("grouped-disclosure-subforms-" + mode + ".json")
    report = {"passed": False, "checks": [], "actions": [], "commands": [], "pixels": [], "compiled": args.compiled,
              "environment": {"macOS": platform.mac_ver()[0], "hostArchitecture": platform.machine()}}
    report_path.write_text(json.dumps(report) + "\n")
    prepared_path, prepared = validate_prepared(ROOT)
    assert prepared["disclosure"] and prepared["subforms"]
    sources = {name: sha(ROOT / name) for name in SOURCES}
    report.update({"driverSourceSHA256": sources, "compileReportSHA256": sha(prepared_path),
                   **{name: prepared[name] for name in ("sources_sha256", "canonicalSourceSHA256", "nativeSourceSHA256", "componentSourceSHA256", "nativeSHA256", "componentPackageSHA256", "compiledHostSHA256")}})
    sys.path.insert(0, str(ROOT / "tests"))
    import mac_ax as ax
    from fixture_desktop import activate_fixture, capture_fixture_window, wait_for_start
    from PIL import Image, ImageChops
    ax.require_test_input()
    for name in ("4D", "4D Server"):
        assert subprocess.run(["pgrep", "-x", name], capture_output=True).returncode != 0
    fixture = BUILD / "hierarchy-probe"
    project, resources = fixture / "Project/Hierarchy.4DProject", fixture / "Resources"
    run_id = (resources / "run-id.txt").read_text()
    (resources / "launch-variant.txt").write_text("nested")
    (resources / "read-only.txt").unlink(missing_ok=True)
    report["runId"] = run_id
    for name in ("state.json", "peer-state.json", "root-state.json", "request.json", "peer-request.json", "root-request.json", "error.json", "close.json", "closed.json"):
        (resources / name).unlink(missing_ok=True)

    def state(instance="root"):
        assert not (resources / "error.json").exists(), read_json(resources / "error.json")
        filename = {"root": "root-state.json", "main": "state.json", "peer": "peer-state.json"}[instance]
        value = read_json(resources / filename)
        return value if value and value.get("runId") == run_id else None

    def check(condition, message):
        assert condition, message
        report["checks"].append(message)
        print("PASS:", message, flush=True)

    process, finished = None, False
    with (BUILD / ("grouped-disclosure-subforms-" + mode + ".log")).open("w") as log:
        try:
            process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless",
                                        "--opening-mode", mode, "--webadmin-auto-start", "false"], stdout=log, stderr=log)
            report["pid"] = process.pid
            ready, report["modeNoticeAcknowledged"] = wait_for_start(process, project, state, BUILD)
            check(ready["compiled"] is args.compiled, "actual nested desktop mode matches the requested run")
            app, window = activate_fixture(process, project, TITLE)
            report["window"] = {"title": window.read("AXTitle"), "position": window.read("AXPosition"), "size": window.read("AXSize")}

            def find(predicate):
                pending = [window]
                while pending:
                    item = pending.pop()
                    if predicate(item):
                        return item
                    if item.read("AXRole") not in ("AXOutline", "AXTable"):
                        pending.extend(item.read("AXChildren") or [])

            def table(instance):
                return find(lambda e: e.read("AXRole") == "AXOutline" and str(e.read("AXDescription")).endswith(instance.title() + " grouped items"))

            def groups(instance):
                current = table(instance)
                return [r for r in current.read("AXRows") or [] if r.read("AXDisclosureLevel") == 0 and r.is_settable("AXDisclosing")]

            def root():
                return find(lambda e: e.read("AXRole") == "AXGroup" and str(e.read("AXIdentifier")).startswith("axb/"))

            def snapshot():
                def coherent():
                    value = {name: state(name) for name in ("root", "main", "peer")}
                    return value if all(value.values()) and len({s.get("rootTick") for s in value.values()}) == 1 else None
                return ax.wait_for(coherent, "Nested observations did not complete one coherent root tick")

            def ancestors(value):
                parent = value["root"]
                return {"outer": parent["outerScroll"], "main": parent["main"]["innerScroll"], "peer": parent["peer"]["innerScroll"]}

            def command(instance, operation, **payload):
                identifier = uuid.uuid4().hex
                destination = resources / {"root": "root-request.json", "main": "request.json", "peer": "peer-request.json"}[instance]
                temporary = destination.with_suffix(".tmp")
                temporary.write_text(json.dumps({"id": identifier, "operation": operation, **payload}))
                temporary.replace(destination)
                ax.wait_for(lambda: (s := state(instance)) and s["command"]["id"] == identifier, "Nested fixture command did not complete")
                time.sleep(.2)
                value = snapshot()
                report["commands"].append({"instance": instance, "operation": operation, "payload": payload, "state": value})
                return value

            def settle():
                receipt = ax.wait_for(lambda: value if (r := root()) and (value := r.read("AXHelp")) and value not in
                                      ("Action queued", "Waiting for the application to complete the action") else None,
                                      "Nested disclosure did not finish", timeout=15)
                tick = snapshot()["root"]["rootTick"]
                ax.wait_for(lambda: snapshot()["root"]["rootTick"] > tick, "Independent root and both child states did not refresh after completion")
                return receipt

            def disclose(instance, expanded, calls=1, rejected=False, disclosure_child=False):
                before = snapshot()
                row = groups(instance)[0]
                key = before[instance]["outline"]["rows"][int(row.read("AXIndex"))]
                content = table(instance).cell(0, int(row.read("AXIndex"))).read("AXChildren")[0] if disclosure_child else None
                check((content.press() if content else row.set_boolean("AXDisclosing", expanded)) == 0, "external AX accepts the instance-scoped disclosure request")
                receipt = settle()
                after = snapshot()
                new_calls = after[instance]["disclosureCalls"][len(before[instance]["disclosureCalls"]):]
                report["actions"].append({"instance": instance, "rowKey": key, "expanded": expanded, "disclosureChildPress": disclosure_child, "receipt": receipt, "before": before, "after": after, "calls": new_calls})
                check(len(new_calls) == calls and (receipt != "Group disclosure confirmed" if rejected else receipt in
                      ("Group disclosure confirmed", "Group already has the requested disclosure state")), "instance controller count and completion receipt match the requested result")
                if new_calls:
                    check(new_calls[0]["objectName"] == "Grouped" and new_calls[0]["backingRow"] == 1 and new_calls[0]["breakLevel"] == 1
                          and new_calls[0]["expanded"] is expanded, "nested controller receives resolved local native coordinates")
                other = "peer" if instance == "main" else "main"
                check(before[other]["disclosureCalls"] == after[other]["disclosureCalls"] and before[other]["beforeGroup"] == after[other]["beforeGroup"]
                      and before[other]["events"] == after[other]["events"],
                      "disclosure preserves the independently bound sibling's data, topology, selection and handlers")
                check(ancestors(before) == ancestors(after), "successful, rejected or idempotent disclosure never scrolls an ancestor")
                return before, after

            ax.wait_for(lambda: table("main") and table("peer"), "Both nested outlines were not discovered")
            command("main", "groupCase", name="repeated")
            command("peer", "groupCase", name="repeated")
            observed = snapshot()
            check(observed["main"]["beforeGroup"]["keys"] == observed["peer"]["beforeGroup"]["keys"]
                  and observed["main"]["beforeGroup"]["levels"][0]["variable"] != observed["peer"]["beforeGroup"]["levels"][0]["variable"],
                  "repeated controls share keys and captions while binding independent native arrays")
            check(table("main").read("AXIdentifier") != table("peer").read("AXIdentifier"), "nested public paths distinguish identical control names")
            check(sum(a.get("registered") is True for a in observed["main"]["bridge"]["areas"]) == 1, "only the parent lifecycle area owns both nested branches")
            for target, outer, inner in (("main", (40, 15), (20, 10)), ("peer", (30, 12), (10, 5))):
                command("root", "outerScroll", target=target, vertical=outer[0], horizontal=outer[1])
                command("root", "innerScroll", target=target, vertical=inner[0], horizontal=inner[1])
            initial_scroll = ancestors(snapshot())
            check(all(n > 0 for pair in initial_scroll["outer"].values() for n in pair)
                  and all(n > 0 for pair in (initial_scroll["main"], initial_scroll["peer"]) for n in pair),
                  "both axes at both ancestor levels begin with independently measured nonzero scrolling")
            disclose("main", False, disclosure_child=True)
            disclose("main", True)
            disclose("main", True, calls=0)
            command("peer", "focusGrouped")
            _, after = disclose("main", False)
            check(after["peer"]["focus"] == "Grouped" and not after["peer"]["editing"], "main disclosure preserves the sibling's nonediting grouped focus")
            close = find(lambda e: e.read("AXRole") == "AXButton" and e.read("AXDescription") == "Close probe")
            command("root", "rootFocus")
            settle()
            check(snapshot()["root"]["focus"] == "Close" and app.read("AXFocusedUIElement").same_as(close), "ordinary parent focus resolves to the exact root Close owner")
            command("main", "groupCase", name="repeated")
            note = find(lambda e: e.read("AXRole") == "AXTextField" and "PeerWrapper/Child/Note" in str(e.read("AXIdentifier")))
            check(note is not None and note.set_boolean("AXFocused", True) == 0, "sibling editor accepts ordinary instance-scoped focus")
            settle()
            check(note.set_text("Peer pending α 🎸") == 0, "sibling editor accepts pending Unicode text")
            settle()
            ax.wait_for(lambda: (value := state("peer")) and value.get("editedText") == "Peer pending α 🎸", "Sibling native pending text did not arrive")
            check(note.set_range("AXSelectedTextRange", 5, 7) == 0, "sibling editor accepts its native text highlight")
            settle()
            _, after = disclose("main", False, calls=0, rejected=True)
            check(after["peer"]["editedText"] == "Peer pending α 🎸" and note.read("AXSelectedTextRange") == (5, 7),
                  "cross-instance disclosure rejects without changing the sibling's pending text or highlight")
            command("root", "rootFocus")
            settle()
            check(snapshot()["root"]["focus"] == "Close" and app.read("AXFocusedUIElement").same_as(close), "root Close regains actual ownership after the sibling editor")
            for fault in ("childScope", "childReady", "replace", "rootScope"):
                command("root", "childReady", target="main", ready=True)
                command("main", "groupCase", name="repeated")
                command("main", "groupControllerRestore")
                command("main", "groupControllerMode", mode="ignore")
                retained_main, retained_peer = groups("main")[0], groups("peer")[0]
                before = snapshot()
                key = before["main"]["outline"]["rows"][int(retained_main.read("AXIndex"))]
                check(retained_main.set_boolean("AXDisclosing", False) == 0, "pending nested request reaches its current controller")
                dispatched = ax.wait_for(lambda: value if (value := state("main")) and
                                         len(value["disclosureCalls"]) == len(before["main"]["disclosureCalls"]) + 1 else None,
                                         "Pending controller did not record its one invocation")
                invocation = dispatched["disclosureCalls"][-1]
                command("root", fault, target="main", ready=False)
                receipt = settle()
                after = snapshot()
                report["actions"].append({"fault": fault, "instance": "main", "rowKey": key, "expanded": False,
                                           "receipt": receipt, "before": before, "after": after,
                                           "calls": after["main"]["disclosureCalls"][len(before["main"]["disclosureCalls"]):]})
                check(receipt not in ("Group disclosure confirmed", "Group already has the requested disclosure state"), fault + " rejects confirmation after the one dispatched callback")
                check(after["main"]["disclosureCalls"] == before["main"]["disclosureCalls"] + [invocation]
                      and invocation["actionID"], fault + " retains exactly one invocation in the root-owned ledger across replacement")
                if fault == "replace":
                    check(after["main"]["loadSerial"] > before["main"]["loadSerial"], "replacement actually runs the new child form's native On Load")
                check(retained_main.read("AXRole") is None, fault + " retires old main disclosure handles")
                check(after["peer"]["disclosureCalls"] == before["peer"]["disclosureCalls"] and after["peer"]["beforeGroup"] == before["peer"]["beforeGroup"]
                      and after["peer"]["events"] == before["peer"]["events"],
                      fault + " preserves sibling business and controller state")
                check((retained_peer.read("AXRole") is None) if fault == "rootScope" else retained_peer.read("AXRole") == "AXRow",
                      fault + " retires exactly the affected form branches")
                count = len(after["main"]["disclosureCalls"])
                time.sleep(.3)
                check(len(snapshot()["main"]["disclosureCalls"]) == count, fault + " never replays a callback into the replacement or recovered child")
                command("root", "childReady", target="main", ready=True)
                ax.wait_for(lambda: table("main"), "Main outline did not recover")
                check(snapshot()["main"]["disclosureCalls"] == before["main"]["disclosureCalls"] + [invocation], fault + " recovery retains the same single actionID without replay")
            command("main", "groupControllerMode", mode="normal")
            command("main", "groupControllerRestore")
            command("main", "groupCase", name="repeated")
            command("root", "clip", target="main", height=200)
            before_image, after_image = [BUILD / ("disclosure-subforms-" + mode + "-" + uuid.uuid4().hex + ".png") for _ in range(2)]
            before_window = capture_fixture_window(process, window, before_image)
            disclose("main", False)
            after_window = capture_fixture_window(process, window, after_image)
            images = [Image.open(p).convert("RGBA") for p in (before_image, after_image)]
            diff = ImageChops.difference(*images)
            changed = sum(n for n, color in diff.getcolors(diff.width * diff.height) if color != (0, 0, 0, 0))
            check(changed == 0, "fully clipped disclosure changes no pixel and reveals no ancestor")
            report["pixels"].append({"baseline": {"path": before_image.name, "sha256": sha(before_image), "capturedWindow": before_window},
                                   "integrated": {"path": after_image.name, "sha256": sha(after_image), "capturedWindow": after_window},
                                   "changedPixels": changed, "wholeWindow": True, "mask": False, "tolerance": 0})
            disclose("main", False, calls=0)
            command("main", "groupControllerMode", mode="ignore")
            disclose("main", True, rejected=True)
            check(sources == {name: sha(ROOT / name) for name in SOURCES} and prepared["canonicalSourceSHA256"] == canonical_sources(),
                  "nested canonical methods and every imported driver source remain unchanged")
            report["finalState"] = snapshot()
            finished = True
        except BaseException as error:
            report["error"] = repr(error)
            raise
        finally:
            if process is not None:
                finish_run(process, resources, run_id, report, report_path, finished)
            else:
                report_path.write_text(json.dumps(report, indent=2) + "\n")
    try:
        assert report["passed"]
        check(report["closed"]["clearedTrees"] == len(report["finalState"]["root"]["ownedTrees"]), "shutdown clears every tracked native tree including retired children")
    except BaseException as error:
        report["passed"] = False
        report["error"] = repr(error)
        raise
    finally:
        report_path.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
