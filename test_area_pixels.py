#!/usr/bin/env python3
"""Compare unchanged synthetic forms with and without lifecycle areas."""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageChops
from prepare_area_fixture import BUILD, FIXTURE, ROOT, TITLE
from build_component import sha

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import activate_fixture, wait_for_start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run or not ax.trusted():
        parser.error("--run and Accessibility permission are required")
    output = BUILD / "area-pixels"
    output.mkdir(exist_ok=True)
    report = {"passed": False, "compiled": True, "images": {}, "baseline": {}}
    try:
        for area in (False, True):
            name = "area" if area else "baseline"
            subprocess.run([sys.executable, "prepare_area_fixture.py", "--server", str(args.server), "--pixel-focus", *([] if area else ["--no-area"])], cwd=ROOT, check=True)
            report["baseline"][name] = json.loads((FIXTURE / "Resources/form-baseline.json").read_text())
            report[name + "CompileSHA256"] = sha(BUILD / "area-compile-report.json")
            project = FIXTURE / "Project/Area.4DProject"
            status = FIXTURE / "Resources/state.json"
            def state():
                try:
                    value = json.loads(status.read_text(encoding="utf-8-sig"))
                except (OSError, ValueError):
                    return {}
                assert not value.get("error"), value
                return value
            with (output / (name + ".log")).open("w") as log:
                process = subprocess.Popen(["/Applications/4D/4D.app/Contents/MacOS/4D", "--project", str(project), "--dataless", "--opening-mode", "compiled", "--webadmin-auto-start", "false"], stdout=log, stderr=log)
                try:
                    wait_for_start(process, project, state, BUILD)
                    activate_fixture(process, project, TITLE)
                    ax.wait_for(lambda: state().get("ticks", 0) >= 3 and (not area or state().get("diagnostics", {}).get("ready")), "Fixture did not finish initialization")
                    assert state()["name"] == "After initialization" and state()["child"]["name"] == "Child"
                    target = output / (name + ".png")
                    previous = None
                    for _ in range(10):
                        ax.capture_window(process.pid, target, include_shadow=False)
                        current = Image.open(target).convert("RGB")
                        if previous is not None and ImageChops.difference(previous, current).getbbox() is None:
                            break
                        previous = current
                        time.sleep(0.15)
                    else:
                        raise AssertionError("Window rendering did not settle")
                    report["images"][name] = {"sha256": sha(target), "size": list(current.size)}
                    (FIXTURE / "Resources/close.json").write_text("{}")
                    process.wait(timeout=15)
                    assert process.returncode == 0
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=10)
        assert report["baseline"]["area"] == report["baseline"]["baseline"], "Original form definitions changed"
        baseline = Image.open(output / "baseline.png").convert("RGB")
        candidate = Image.open(output / "area.png").convert("RGB")
        assert baseline.size == candidate.size, "Window dimensions changed"
        difference = ImageChops.difference(baseline, candidate)
        difference.save(output / "difference.png")
        report["differenceBounds"] = difference.getbbox()
        assert report["differenceBounds"] is None, "Rendered forms differ"
        report["passed"] = True
        print("PASS: lifecycle areas preserve every rendered window pixel; no masks or tolerance")
    finally:
        (BUILD / "area-pixels.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
