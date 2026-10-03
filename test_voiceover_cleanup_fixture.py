"""Verify owned VoiceOver cleanup after window disappearance and foreground loss."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
import voiceover

def cleanup_owned_fixtures(processes):
    errors = []
    for process in processes:
        try:
            if process.poll() is None:
                process.terminate()
        except BaseException as error:
            errors.append(error)
        try:
            process.wait(timeout=15)
        except BaseException as error:
            errors.append(error)
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ocr", type=Path, required=True)
    args = parser.parse_args()
    output = ROOT / "build/voiceover-cleanup"
    output.mkdir(parents=True, exist_ok=True)
    report_path = output / "report.json"
    report = {"passed": False, "cases": [], "helperSHA256": hashlib.sha256(Path(voiceover.__file__).read_bytes()).hexdigest()}
    report_path.write_text(json.dumps(report) + "\n")
    source = ROOT / "tests/VoiceOverCleanupFixture.swift"
    binary = output / "OwnedVOFixture"
    dependencies = [Path(__file__), Path(voiceover.__file__), Path(ax.__file__), source, args.ocr.resolve()]
    frozen = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in dependencies}
    report["dependenciesSHA256"] = frozen
    ax.require_test_input()
    subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True)
    report["fixtureSourceSHA256"] = hashlib.sha256(source.read_bytes()).hexdigest()
    report["fixtureBinarySHA256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    for case in ("window-missing", "foreground-lost"):
        processes = []
        vo = None
        primary_failure = None
        try:
            assert not voiceover.VoiceOver.pids("VoiceOver") and not voiceover.VoiceOver.pids("VoiceOver Quickstart")
            title = "VO cleanup " + uuid.uuid4().hex
            process = subprocess.Popen([str(binary), title])
            processes.append(process)
            app = ax.application(process.pid)
            window = ax.wait_for(lambda: next((w for w in app.read("AXWindows") or [] if w.read("AXTitle") == title), None), "Owned native window missing")
            ax.wait_for(lambda: app.read("AXFrontmost") is True, "Owned native app is not frontmost")
            vo = voiceover.VoiceOver(process, None, title, output / case, args.ocr)
            vo.start()
            caption_restoration_exercised = vo.changed_caption
            if case == "window-missing":
                close = window.read("AXCloseButton")
                assert close and close.press() == 0
                ax.wait_for(lambda: not any(w.read("AXTitle") == title for w in app.read("AXWindows") or []), "Owned window did not close")
                expected = "Owned fixture window missing"
            else:
                second = subprocess.Popen([str(binary), "VO cleanup other " + uuid.uuid4().hex])
                processes.append(second)
                other = ax.application(second.pid)
                ax.wait_for(lambda: other.read("AXFrontmost") is True and app.read("AXFrontmost") is not True, "Other owned app did not take foreground")
                expected = "Owned fixture lost foreground"
            try:
                vo.stop()
                raise AssertionError("Cleanup erased the original guard failure")
            except AssertionError as failure:
                assert str(failure) == expected, repr(failure)
                assert not getattr(failure, "__notes__", []), getattr(failure, "__notes__", [])
            assert not vo.owned and not vo.changed_caption
            assert all(not application.alive() for application in vo.owned_applications.values())
            assert not vo.pids("VoiceOver") and not vo.pids("VoiceOver Quickstart")
            report["cases"].append({"case": case, "passed": True, "guardFailurePreserved": expected,
                                  "captionRestorationExercised": caption_restoration_exercised,
                                  "captionHiddenBaselineVerified": vo.caption_restoration_verified,
                                  "ownedAssistiveProcessesExited": True})
            print("PASS", case, flush=True)
        except BaseException as error:
            primary_failure = error
            report["cases"].append({"case": case, "passed": False, "error": repr(error)})
            raise
        finally:
            cleanup_errors = []
            try:
                if vo is not None and vo.owned:
                    try:
                        vo.stop()
                    except BaseException as error:
                        cleanup_errors.append(error)
                cleanup_errors.extend(cleanup_owned_fixtures(processes))
                if cleanup_errors:
                    report.setdefault("cleanupErrors", []).extend(repr(error) for error in cleanup_errors)
                    if primary_failure is not None:
                        for error in cleanup_errors:
                            primary_failure.add_note("Owned fixture cleanup failed: " + repr(error))
                    else:
                        raise cleanup_errors[0]
            finally:
                report_path.write_text(json.dumps(report, indent=2) + "\n")
    assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in frozen.items()), "A cleanup-fixture dependency changed during execution"
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == report["fixtureBinarySHA256"], "The cleanup-fixture binary changed during execution"
    report["passed"] = True
    report_path.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
