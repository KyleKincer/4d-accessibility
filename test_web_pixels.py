#!/usr/bin/env python3
"""Compare the complete native HTML/4D window with and without the bridge."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageChops
from build_component import sha
from prepare_web_fixture import BUILD, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--kit", required=True, type=Path)
    args = parser.parse_args()
    if not args.run:
        parser.error("--run is required for sequential desktop comparisons")
    report = {"passed": False, "compiled": True, "engine": "system", "images": {}, "reports": {}, "driver_sha256": sha(Path(__file__))}
    try:
        for baseline in (True, False):
            variant = "baseline" if baseline else "bridge"
            subprocess.run([sys.executable, "prepare_web_fixture.py", "--server", str(args.server), "--kit", str(args.kit), *(["--baseline"] if baseline else [])], cwd=ROOT, check=True)
            subprocess.run([sys.executable, "test_web_fixture.py", "--run", "--compiled", "--pixels"], cwd=ROOT, check=True)
            path = BUILD / ("web-system-" + variant + "-compiled-pixels.png")
            image = Image.open(path).convert("RGB")
            report["images"][variant] = {"sha256": sha(path), "size": list(image.size)}
            report["reports"][variant] = sha(BUILD / ("web-system-" + variant + "-pixels-compiled.json"))
        baseline = Image.open(BUILD / "web-system-baseline-compiled-pixels.png").convert("RGB")
        integrated = Image.open(BUILD / "web-system-bridge-compiled-pixels.png").convert("RGB")
        assert baseline.size == integrated.size, "Native web/form dimensions changed"
        difference = ImageChops.difference(baseline, integrated)
        difference.save(BUILD / "web-system-pixel-difference.png")
        report["differenceBounds"] = difference.getbbox()
        report["changedPixels"] = sum(count for count, color in difference.getcolors(difference.width * difference.height) if color != (0, 0, 0))
        assert report["changedPixels"] == 0, "Native web/form rendering changed"
        report["passed"] = True
        print("PASS: whole native web/4D window is pixel-identical; no masks or tolerance")
    finally:
        (BUILD / "web-system-pixels.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
