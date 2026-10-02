#!/usr/bin/env python3
"""Exercise native styled editing through external AX in an owned 4D fixture."""
import argparse
import json
import subprocess
import sys

from build_component import sha
from prepare_discovery_fixture import BUILD, FIXTURE, ROOT, TITLE

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--compiled", action="store_true")
    parser.add_argument("--voiceover", action="store_true", help="Read the styled field and link label through VoiceOver")
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error("--run and Accessibility permission are required")
    for name in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential fixture")
    compiled = json.loads((BUILD / "discovery-compile-report.json").read_text())
    if not compiled.get("passed") or not compiled.get("styled") or not compiled.get("area"):
        parser.error("Prepare the fixture with --area --styled")
    for relative, expected in compiled["sources_sha256"].items():
        if sha(FIXTURE / relative) != expected:
            parser.error("Fixture source changed after compilation: " + relative)
    for key, relative in (("component_sha256", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ"),
                          ("native_sha256", "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")):
        if sha(FIXTURE / relative) != compiled[key]:
            parser.error("Package changed after compilation")
    config = json.loads((FIXTURE / "Resources/launch.json").read_text())
    for name in ("runtime-status.json", "closed.json"):
        (FIXTURE / "Resources" / name).unlink(missing_ok=True)
    report = {"passed": False, "checks": [], "compiled": args.compiled,
              "scope": "AX styled reading/editing and optional VoiceOver reading; no full rich-reference claim",
              "voiceoverRequested": args.voiceover,
              "generated": compiled["dynamic"],
              "native_sha256": compiled["native_sha256"],
              "component_sha256": compiled["component_sha256"],
              "compile_report_sha256": sha(BUILD / "discovery-compile-report.json")}

    def state():
        try:
            result = json.loads((FIXTURE / "Resources/runtime-status.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            return {}
        if result.get("failure"):
            raise AssertionError(result["failure"])
        return result if result.get("runId") == config["runId"] else {}

    def check(passed, name):
        report["checks"].append({"name": name, "passed": bool(passed)})
        assert passed, name
        print("PASS: " + name, flush=True)

    project = FIXTURE / "Project/Discovery.4DProject"
    with (BUILD / "styled-desktop.log").open("w") as log:
        process = subprocess.Popen([
            "/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless",
            "--opening-mode", "compiled" if args.compiled else "interpreted", "--webadmin-auto-start", "false",
        ], stdout=log, stderr=log)
        try:
            ready, _ = wait_for_start(process, project, state, BUILD)
            check(ready["compiled"] is args.compiled, "actual requested desktop mode")
            report["architecture"] = ax.process_architecture(process.pid)
            app, window = activate_fixture(process, project, TITLE)
            group = ax.wait_for(lambda: next((e for e in window.read("AXChildren") or []
                if str(e.read("AXIdentifier")).startswith("axb/")), None), "Area-owned provider", timeout=20)

            def find(label):
                # Captions and their editors share an accessible name. Select
                # the control rather than treating its reading label as input.
                return next((e for e in group.read("AXChildren") or []
                    if e.read("AXDescription") == label and e.read("AXRole") != "AXStaticText"), None)

            def settle():
                ax.wait_for(lambda: group.read("AXHelp") not in (
                    None, "Action queued", "Waiting for the application to complete the action"), "Final receipt", timeout=20)

            styled = ax.wait_for(lambda: find("Styled notes"), "Styled editor", timeout=20)
            report["initialStyled"] = {name: styled.read(name) for name in (
                "AXValue", "AXRole", "AXDescription", "AXIdentifier")}
            check(styled.read("AXValue") == "Alpha βeta 🎸", "styled value contains visible text without markup")
            check(styled.read("AXRole") == "AXTextArea", "styled multiline editor retains text-area semantics")
            reference = find("Linked help")
            check(reference.read("AXValue") == "Read the help", "reference displays its visible link label")
            check(not reference.is_settable("AXValue"), "reference does not advertise an unsupported edit")
            check(find("Name").read("AXValue") == "Ada", "ordinary text still reads normally")
            check(find("Password").read("AXValue") == "", "protected input remains undisclosed")
            ax.wait_for(lambda: find("Name").read("AXFocused") is True, "Normal initial focus", timeout=20)
            check(styled.set_boolean("AXFocused", True) == 0, "styled focus request accepted")
            ax.wait_for(lambda: styled.read("AXFocused") is True, "Styled native focus", timeout=20)
            settle()
            check(styled.set_range("AXSelectedTextRange", 6, 4) == 0, "styled range request accepted")
            ax.wait_for(lambda: styled.read("AXSelectedTextRange") == (6, 4), "Styled selection", timeout=20)
            settle()
            check(styled.read("AXSelectedText") == "βeta", "selection indexes refer to visible text")
            check(styled.set_string("AXSelectedText", "gamma") == 0, "styled partial replacement accepted")
            ax.wait_for(lambda: styled.read("AXValue") == "Alpha gamma 🎸", "Styled editor replacement", timeout=20)
            settle()
            edit = next(item for item in app.read("AXMenuBar").read("AXChildren") or []
                        if item.read("AXTitle") == "Edit")
            actions = {item.read("AXTitle"): item for menu in edit.read("AXChildren") or []
                       for item in menu.read("AXChildren") or []}
            check(actions["Undo"].read("AXEnabled") is True and actions["Undo"].press() == 0,
                  "ordinary Undo accepts the styled native edit")
            ax.wait_for(lambda: styled.read("AXValue") != "Alpha gamma 🎸", "Styled native Undo", timeout=20)
            report["afterUndo"] = {"text": styled.read("AXValue"),
                "redoEnabled": actions["Redo"].read("AXEnabled")}
            # 4D 20.8's default application Edit menu also leaves Redo disabled
            # after this ordinary native edit in the bridge-free baseline.
            # Preserve that menu behavior; do not invent a second undo stack.
            check(actions["Redo"].read("AXEnabled") is False,
                  "Redo availability matches the observed native 4D baseline")
            check(styled.set_range("AXSelectedTextRange", 6, 4) == 0,
                  "styled selection recovers after native Undo")
            ax.wait_for(lambda: styled.read("AXSelectedTextRange") == (6, 4),
                        "Styled selection after Undo", timeout=20)
            settle()
            check(styled.set_string("AXSelectedText", "gamma") == 0,
                  "styled native editor accepts another replacement after Undo")
            ax.wait_for(lambda: styled.read("AXValue") == "Alpha gamma 🎸",
                        "Styled edit recovery", timeout=20)
            settle()
            check(find("Save contact").press() == 0, "ordinary commit handler accepted")
            ax.wait_for(lambda: state().get("styledCommits", 0) > 0, "Original data-change handler", timeout=20)
            settle()
            check("gamma" in state()["styled"] and state()["styledWordBold"], "native commit preserves surrounding text and bold style")
            check(styled.set_text("A#B") == 0, "styled filtered input requested")
            ax.wait_for(lambda: styled.read("AXValue") == "A", "Original keystroke rejection", timeout=20)
            settle()
            check("rejected" in str(group.read("AXHelp")).lower(), "original keystroke filter stops the remaining text")
            check(styled.set_text("Recovered 🎹") == 0, "styled editor recovers after rejection")
            ax.wait_for(lambda: styled.read("AXValue") == "Recovered 🎹", "Complete Unicode recovery", timeout=20)
            settle()
            check(find("Save contact").press() == 0, "recovered text uses the ordinary commit handler")
            ax.wait_for(lambda: "Recovered" in state()["styled"], "Committed recovered text", timeout=20)
            settle()
            check(styled.set_text("Recovered 🎹\nSecond styled line") == 0,
                  "styled multiline replacement accepted")
            ax.wait_for(lambda: styled.read("AXValue") == "Recovered 🎹\rSecond styled line",
                        "Styled multiline Unicode text", timeout=20)
            settle()
            check(styled.read("AXNumberOfCharacters") == 31,
                  "styled character count uses visible UTF-16 text without markup")
            check(find("Save contact").press() == 0, "multiline styled text uses the original commit handler")
            ax.wait_for(lambda: "Second styled line" in state()["styled"],
                        "Committed multiline styled text", timeout=20)
            settle()
            if args.voiceover:
                from voiceover import VoiceOver
                vo = VoiceOver(process, project, TITLE, BUILD / "styled-voiceover", BUILD / "read-fixture-screen")
                report["voiceover"] = vo.steps
                before = state()

                def read_key(key, **modifiers):
                    caption = vo.key(key, **modifiers)
                    assert "not responding" not in caption.lower(), "VoiceOver reports an unresponsive styled form"
                    return caption

                try:
                    vo.start()
                    caption = read_key("home", command=True)
                    for _ in range(4):
                        if "close button" in caption.lower().replace(",", ""):
                            break
                        caption = read_key("home", command=True)
                    check("close button" in caption.lower().replace(",", ""),
                          "VoiceOver reaches the window independently of editor focus")
                    for _ in range(8):
                        caption = read_key("right")
                        if "Contact details" in caption and "group" in caption.lower():
                            break
                    check("Contact details" in caption and "group" in caption.lower(),
                          "VoiceOver reaches the complete form group")
                    read_key("down", shift=True)
                    caption = read_key("home")
                    read_styled = read_link = False
                    for _ in range(45):
                        if "Styled notes" in caption and "Recovered" in caption:
                            check("<span" not in caption and "font-weight" not in caption,
                                  "VoiceOver reads the styled editor name and visible text without markup")
                            read_styled = True
                        if "Linked help" in caption and "Read the help" in caption:
                            check("<a " not in caption and "href=" not in caption,
                                  "VoiceOver reads the link's visible label without source markup")
                            read_link = True
                        if read_styled and read_link:
                            break
                        caption = read_key("right")
                    check(read_styled and read_link, "VoiceOver navigation reaches both styled fields")
                    after = state()
                    check(all(after[key] == before[key] for key in ("styled", "reference", "saved")),
                          "read-only VoiceOver navigation preserves form content and saved results")
                finally:
                    vo.stop()
            check(find("Close fixture").press() == 0, "ordinary close accepted")
            process.wait(timeout=20)
            check(not styled.read("AXEnabled"), "closed styled reference retires")
            report["passed"] = True
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            mode = "compiled" if args.compiled else "interpreted"
            generated = "generated-" if compiled["dynamic"] else ""
            (BUILD / ("styled-" + generated + mode + ("-voiceover" if args.voiceover else "") + ".json")).write_text(
                json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
