#!/usr/bin/env python3
"""Build a disposable public-AppKit hierarchy observer, never a runtime adapter."""

import argparse
import io
import json
from pathlib import Path
import subprocess
import tarfile
import uuid

from build_component import BUILD, ROOT, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--source", default="HEAD", help="Committed production source to observe")
    args = parser.parse_args()
    destination = BUILD / "hierarchy-observer"
    if destination.exists():
        if destination.is_symlink():
            parser.error("Observer destination must not be a symlink")
        destination.rename(BUILD / ("hierarchy-observer-previous-" + uuid.uuid4().hex))
    destination.mkdir(parents=True)
    revision = subprocess.check_output(["git", "rev-parse", "--verify", "--end-of-options",
        args.source + "^{commit}"], cwd=ROOT, text=True).strip()
    archive = subprocess.check_output(["git", "archive", revision], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(destination, filter="data")
    helper = ROOT / "tests/NativeHierarchyProbe.inc"
    plugin = destination / "src/Plugin.mm"
    source = plugin.read_text()
    patches = [
        ("#import <Foundation/Foundation.h>", "#import <Foundation/Foundation.h>\n#import <objc/runtime.h>"),
        ("static NSString *TextParameter", helper.read_text() + "\nstatic NSString *TextParameter"),
        ("if (request) request.result = request.layout ?",
         'if (request && [request.layout isEqual:@"hierarchyProbe"]) { request.result=ProbeNativeHierarchy(request.nativeWindow); return; }\n        if (request) request.result = request.layout ?'),
        ("case kServerInitPlugin: AXBInitialize(); break;",
         "case kServerInitPlugin: InitializeCellProbe(); AXBInitialize(); break;"),
    ]
    for before, after in patches:
        assert source.count(before) == 1, before
        source = source.replace(before, after)
    plugin.write_text(source)
    report = {"productionSourceCommit": revision, "observerTemplateSHA256": sha(helper),
        "observerPluginSourceSHA256": sha(plugin), "preparerSHA256": sha(Path(__file__)),
        "scope": "Disposable native view and public NSCell drawing observation, no adapter acceptance"}
    if not args.prepare_only:
        subprocess.run(["python3", "build.py"], cwd=destination, check=True)
        report["diagnosticNativeSHA256"] = sha(
            destination / "build/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")
    (BUILD / "hierarchy-observer-build.json").write_text(json.dumps(report, indent=2) + "\n")
    print(destination / "build/AccessibilityBridge.bundle")


if __name__ == "__main__":
    main()
