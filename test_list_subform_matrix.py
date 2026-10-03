#!/usr/bin/env python3
"""Prepare fresh data and run the sequential list-subform acceptance matrix."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys

from build_component import BUILD, ROOT, sha

VARIANTS = {
    "automatic": [],
    "table-parent": ["--table-parent", "--header", "--no-primary-key"],
    "single-header-multiline": [
        "--selection-mode",
        "single",
        "--header",
        "--multiline",
    ],
    "nonselectable": ["--selection-mode", "none"],
    "native-default": ["--selection-mode", "default"],
    "configured-header-multiline": ["--configured", "--header", "--multiline"],
    "existing-key-no-primary": ["--no-primary-key", "--header"],
    "text-key": ["--text-key", "--header"],
    "horizontal": ["--horizontal", "--header"],
    "invalid-identity-diagnostics": ["--diagnostics-test"],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--case", choices=VARIANTS, action="append")
    parser.add_argument("--pixels", action="store_true")
    parser.add_argument("--voiceover", action="store_true")
    parser.add_argument("--intel", action="store_true")
    args = parser.parse_args()
    if not args.run:
        parser.error("--run is required for desktop input and disposable data changes")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = BUILD / ("list-subform-acceptance-" + stamp)
    output.mkdir(parents=True)
    files = [p for d in ("src", "host") for p in (ROOT / d).rglob("*") if p.is_file()]
    files += [
        ROOT / p
        for p in (
            "VERSION",
            "install_host_methods.py",
            "prepare_list_subform_fixture.py",
            "test_list_subform_fixture.py",
            "test_list_subform_pixels.py",
            "test_list_subform_matrix.py",
        )
    ]
    frozen = {str(p.relative_to(ROOT)): sha(p) for p in files}
    report = {"passed": False, "started": stamp, "source_sha256": frozen, "runs": []}

    def freeze():
        for relative, expected in frozen.items():
            assert sha(ROOT / relative) == expected, (
                "Source changed during acceptance: " + relative
            )

    def command(name, script, options):
        freeze()
        print("Running " + name, flush=True)
        with (output / (name + ".log")).open("w") as log:
            subprocess.run(
                [sys.executable, str(ROOT / script), *options],
                cwd=ROOT,
                stdout=log,
                stderr=log,
                check=True,
            )
        freeze()

    def desktop(name, options, flags):
        command(
            name + "-prepare",
            "prepare_list_subform_fixture.py",
            ["--server", str(args.server), *options],
        )
        shutil.copyfile(
            BUILD / "list-subform-compile-report.json",
            output / (name + "-compile.json"),
        )
        try:
            command(name, "test_list_subform_fixture.py", ["--run", *flags])
        finally:
            source = BUILD / "list-subform-desktop-report.json"
            if source.exists():
                shutil.copyfile(source, output / (name + ".json"))
        result = json.loads((output / (name + ".json")).read_text())
        assert result["passed"], name
        report["runs"].append(
            {
                "name": name,
                "report": name + ".json",
                "sha256": sha(output / (name + ".json")),
                "checks": len(result["checks"]),
                "compiled": result["compiled"],
                "architecture": result["architecture"],
            }
        )
        print(
            "Accepted " + name + ": " + str(len(result["checks"])) + " checks",
            flush=True,
        )

    try:
        for variant in args.case or VARIANTS:
            for compiled in (False, True):
                name = variant + ("-compiled" if compiled else "-interpreted")
                desktop(name, VARIANTS[variant], ["--compiled"] if compiled else [])
        if args.intel:
            desktop(
                "single-header-multiline-rosetta",
                VARIANTS["single-header-multiline"],
                ["--compiled", "--intel"],
            )
        if args.voiceover:
            desktop(
                "header-multiline-voiceover",
                ["--header", "--multiline"],
                ["--compiled", "--voiceover"],
            )
        if args.pixels:
            for header in (False, True):
                name = "pixels-header" if header else "pixels"
                command(
                    name,
                    "test_list_subform_pixels.py",
                    [
                        "--server",
                        str(args.server),
                        "--run",
                        *(["--header", "--multiline"] if header else []),
                    ],
                )
                source = BUILD / (
                    "list-subform-pixels" + ("-header" if header else "") + ".json"
                )
                result = json.loads(source.read_text())
                assert result["passed"], name
                shutil.copyfile(source, output / (name + ".json"))
                report["runs"].append(
                    {
                        "name": name,
                        "report": name + ".json",
                        "sha256": sha(output / (name + ".json")),
                        "pixel_difference": result["differenceBounds"],
                    }
                )
        report["passed"] = True
    except Exception as error:
        report["failure"] = str(error)
        raise
    finally:
        report["total_checks"] = sum(r.get("checks", 0) for r in report["runs"])
        (output / "matrix.json").write_text(json.dumps(report, indent=2) + "\n")
        print("Matrix report: " + str(output / "matrix.json"), flush=True)


if __name__ == "__main__":
    main()
