#!/usr/bin/env python3
"""Check a host project's syntax without executing its database startup methods.

Uses the same Compile project command and empty target list as the standard
CheckSyntaxCommand. Required application constants must already be generated.
The application's normal syntax/CI check remains the primary project check.
"""
import argparse
import json
from pathlib import Path
import plistlib
import tempfile

from build_component import BUILD, literal, project_at, run_utility, sha


def component_files(folder):
    result = []
    if folder.is_dir():
        for package in sorted(folder.glob("*.4dbase")):
            # Prefer its compiled archive. Source projects can also contain
            # compiled metadata, as the host's XML_JSON component does.
            candidates = list(package.glob("*.4DZ")) or list(package.glob("*.4DC")) or list(package.glob("Project/*.4DProject"))
            if len(candidates) != 1:
                raise RuntimeError(f"Cannot identify exactly one component entry point: {package}")
            result.extend(candidates)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--server", required=True, type=Path)
    args = parser.parse_args()
    project = args.project.expanduser().resolve()
    server = args.server.expanduser().resolve()
    if not project.is_file() or project.suffix != ".4DProject":
        parser.error("--project must name an existing .4DProject file")
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    package = project.parent.parent
    components = component_files(package / "Components") + component_files(server / "Contents/Components")
    sources = {str(p.relative_to(package)): sha(p) for p in sorted((project.parent / "Sources").rglob("*")) if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="host-syntax-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        body = '$options:=New object("targets"; New collection)\n'
        body += f'$options.plugins:=Folder({literal(package / "Plugins")})\n'
        body += '$options.components:=New collection(' + '; '.join(f'File({literal(p)})' for p in components) + ')\n'
        body += f'$result:=Compile project(File({literal(project)}); $options)'
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver, body, 300)
    errors = [entry for entry in result.get("errors", []) if entry.get("isError")]
    passed = result.get("success") is True and not errors
    (BUILD / "host-project-syntax-raw.json").write_text(json.dumps(result, indent=2) + "\n")
    summary = {"passed": passed, "errors": len(errors), "warnings": len(result.get("errors", [])) - len(errors),
               "serverVersion": info.get("CFBundleShortVersionString"), "componentCount": len(components),
               "scope": "Syntax check only; no startup, business data, or generated machine code",
               "sources_sha256": sources, "diagnostics": errors}
    (BUILD / "host-project-syntax-report.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: host project syntax; {summary['errors']} errors, {summary['warnings']} warnings")
    for error in errors[:30]:
        print(error.get("code", {}).get("path"), error.get("line"), error.get("message"))
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
