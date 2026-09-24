#!/usr/bin/env python3
"""Compile complete AreaList grids in repeated automatic input subforms."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import struct
import tempfile
import uuid
import zlib

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package
from install_host_methods import AREA_METHODS

FIXTURE = BUILD / "alp-grid-fixture"
TITLE = "AXB complete AreaList grids"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--area-list-plugin", type=Path, default=ROOT / "fixture/Plugins/ALP.bundle", help="Vendor bundle to validate in this isolated fixture")
    parser.add_argument("--key-type", choices=["text", "integer", "longint"], default="text", help="Keep stable IDs in the vendor's original bound array type")
    parser.add_argument("--controls", action="store_true", help="Add Boolean and integer checkbox columns to the repeated form fixture")
    parser.add_argument("--license-file", type=Path, help="Existing protected vendor license file; contents are never printed")
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before preparing the disposable fixture")
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    verify_package(PACKAGE)
    vendor = args.area_list_plugin.expanduser().resolve()
    vendor_info = plistlib.loads((vendor / "Contents/Info.plist").read_bytes())
    if vendor.name != "ALP.bundle" or vendor_info.get("CFBundleName") != "AreaList Pro":
        parser.error("--area-list-plugin must identify the AreaList vendor bundle")
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("alp-grid-previous-" + uuid.uuid4().hex))
    project = project_at(FIXTURE, "ALPGridFixture")
    sources = FIXTURE / "Project/Sources"
    methods = sources / "Methods"
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    for origin in [BUILD / "AccessibilityBridge.bundle", vendor]:
        shutil.copytree(origin, FIXTURE / "Plugins" / origin.name)
    for directory, pattern in [(ROOT / "host/OptionalMethods", "*.4dm"), (ROOT / "tests/4d", "AXBP_*.4dm")]:
        for method in directory.glob(pattern):
            shutil.copy2(method, methods / method.name)
    for name in AREA_METHODS:
        shutil.copy2(ROOT / "host/Methods" / (name + ".4dm"), methods / (name + ".4dm"))
    declarations = [line for line in (ROOT / "host/Methods/Compiler_AXB.4dm").read_text().splitlines()
                    if any("(" + name + ";" in line for name in AREA_METHODS)]
    declarations += ["C_OBJECT(AXBP_Failed; $1)", "C_OBJECT(AXBP_LeftData; AXBP_RightData)",
                     "C_LONGINT(AXBP_EntryStart; $1; $2; $3)", "C_LONGINT(AXBP_EntryEnd; $1; $2)", "C_BOOLEAN(AXBP_EntryEnd; $0)"]
    for side in ["Left", "Right"]:
        declarations += [f"ARRAY TEXT(a{side}Key; 0)", f"ARRAY TEXT(a{side}Item; 0)", f"ARRAY TEXT(a{side}Description; 0)", f"ARRAY REAL(a{side}Amount; 0)", f"ARRAY TEXT(a{side}Styled; 0)", f"ARRAY TEXT(a{side}Spacer; 0)", f"ARRAY PICTURE(a{side}Picture; 0)"]
    (methods / "Compiler_AXBP.4dm").write_text("\n".join(declarations) + "\n")
    database = sources / "DatabaseMethods"
    database.mkdir()
    (database / "onStartup.4dm").write_text("AXBP_Open\n")

    def save(name, form):
        folder = sources / "Forms" / name
        folder.mkdir(parents=True)
        (folder / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")

    save("Lines", {"width": 380, "height": 260, "method": "AXBP_Child", "events": ["onLoad"], "pages": [None, {"objects": {
        "Items": {"type": "plugin", "pluginAreaKind": "%AreaListPro", "dataSource": "", "dataSourceTypeHint": "integer",
                  "left": 10, "top": 10, "width": 360, "height": 200, "events": ["onPluginArea"], "method": "AXBP_GridEvent"},
        "NoteLabel": {"type": "text", "text": "Note", "left": 10, "top": 225, "width": 45, "height": 24},
        "Note": {"type": "input", "dataSource": "Form.note", "left": 60, "top": 225, "width": 300, "height": 24},
    }}]})
    objects = {side: {"type": "subform", "detailForm": "Lines", "dataSource": "Form." + side.lower(),
                     "left": left, "top": 20, "width": 380, "height": 260}
               for side, left in [("Left", 10), ("Right", 400)]}
    for index, name in enumerate(["Sort", "Bottom", "Top", "Scope", "Hide", "Loading", "Edit", "Close"]):
        button = {"type": "button", "text": name, "left": 10 + index * 98, "top": 305, "width": 92, "height": 28}
        if name == "Close":
            button["action"] = "accept"
        else:
            button.update(method="AXBP_Click", events=["onClick"])
        objects[name] = button
    save("Grid", {"windowTitle": TITLE, "width": 800, "height": 365, "method": "AXBP_Form", "events": ["onLoad", "onTimer", "onUnload"], "pages": [None, {"objects": objects}]})
    def png_chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    icon = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 12, 12, 8, 6, 0, 0, 0))
    icon += png_chunk(b"IDAT", zlib.compress((b"\0" + bytes([0, 140, 40, 255]) * 12) * 12)) + png_chunk(b"IEND", b"")
    (FIXTURE / "Resources/ready.png").write_bytes(icon)
    license_file = args.license_file.expanduser().resolve() if args.license_file else ROOT / "fixture/Resources/alp.license"
    if args.license_file and not license_file.is_file():
        parser.error("--license-file must identify an existing vendor license file")
    if license_file.exists() and license_file.stat().st_mode & 0o077:
        parser.error("The vendor license file must have mode 0600")
    if license_file.exists():
        shutil.copy2(license_file, FIXTURE / "Resources/alp.license")
        (FIXTURE / "Resources/alp.license").chmod(0o600)
    config = {"runId": uuid.uuid4().hex, "licenseMode": "registered" if license_file.exists() else "demo",
              "areaListVersion": vendor_info["CFBundleVersion"], "areaListTitle": vendor_info["CFBundleShortVersionString"],
              "areaListSha256": sha(vendor / "Contents/MacOS/ALP")}
    (FIXTURE / "Resources/launch.json").write_text(json.dumps(config) + "\n")
    config["keyType"] = args.key_type
    config["controls"] = args.controls
    (FIXTURE / "Resources/launch.json").write_text(json.dumps(config) + "\n")
    if args.key_type != "text":
        command = "ARRAY INTEGER" if args.key_type == "integer" else "ARRAY LONGINT"
        for method in [methods / "Compiler_AXBP.4dm", methods / "AXBP_Open.4dm"]:
            text = method.read_text()
            for side in ["Left", "Right"]:
                text = text.replace(f"ARRAY TEXT(a{side}Key;", f"{command}(a{side}Key;")
            text = text.replace('aLeftKey{$row}:="line-"+String($row; "0000")', 'aLeftKey{$row}:=$row')
            method.write_text(text)
    if args.controls:
        for name in ("Compiler_AXBP", "AXBP_Open"):
            method = methods / (name + ".4dm")
            content = method.read_text()
            declarations = "\n".join(f"ARRAY {kind}(a{side}{field}; {0 if name.startswith('Compiler') else 600})"
                                     for side in ("Left", "Right")
                                     for kind, field in (("BOOLEAN", "Direct"), ("BOOLEAN", "Focusable"), ("LONGINT", "Mixed"), ("INTEGER", "Numeric"))) + "\n"
            if name.startswith("Compiler"):
                content += declarations
            else:
                content = content.replace('READ PICTURE FILE(', declarations + 'READ PICTURE FILE(', 1)
                content = content.replace('For ($row; 1; 600)', 'For ($row; 1; 600)\n aLeftMixed{$row}:=2\n aRightMixed{$row}:=2', 1)
            method.write_text(content)
        method = methods / "AXBP_Child.4dm"
        content = method.read_text()
        content = content.rsplit("End if", 1)[0] + (ROOT / "tests/4d/AXPK_Setup.4dm").read_text() + "End if\n"
        method.write_text(content)
        method = methods / "AXBP_State.4dm"
        content = method.read_text()
        start = content.index('If (AL_GetAreaLongProperty(Form.left.area; ALP_Area_EntryInProgress)=1)')
        end = content.index('File("/RESOURCES/runtime-status.json")', start)
        content = content[:start] + (ROOT / "tests/4d/AXPK_State.4dm").read_text() + content[end:]
        method.write_text(content)
        (methods / "AXBP_Enter.4dm").write_text((ROOT / "tests/4d/AXPK_Enter.4dm").read_text())
        method = methods / "AXBP_EntryEnd.4dm"
        content = method.read_text()
        marker = ' If ((AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)=2) & ($row>0))'
        content = content.replace(marker, ''' If (($data.reject=True) & (AL_GetAreaLongProperty($area; ALP_Area_EntryColumn)=8) & ($row>0))
  aLeftDirect{$row}:=aLeftDirect{0}
  $data.rejections:=$data.rejections+1
  $accepted:=False
 End if
''' + marker)
        method.write_text(content)
    hashes = {str(p.relative_to(FIXTURE)): sha(p) for p in sources.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="alp-grid-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        compiled = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(FIXTURE / "Plugins")})\n'
            f'$options.components:=New collection(File({literal(FIXTURE / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
    unexpected = []
    for diagnostic in compiled.get("errors", []):
        method = diagnostic.get("code", {}).get("methodName", "")
        line = diagnostic.get("lineInFile", 0)
        path = methods / (method + ".4dm")
        lines = path.read_text().splitlines() if path.exists() else []
        known_call = 0 < line <= len(lines) and lines[line - 1].strip().removeprefix("$error:=").startswith(("AL_SetArraysNam(", "AL_SetHeaders(", "AL_SetWidths(", "AL_SetColumnLongProperty("))
        if not (diagnostic.get("isError") is False and method == "AXBP_Child" and known_call
                and diagnostic.get("message") == "Missing parameter in the plug-in procedure call. (533.4)"):
            unexpected.append(diagnostic)
    passed = compiled.get("success") is True and not unexpected
    report = {"passed": passed, "compiler": compiled, "sources_sha256": hashes, **config,
              "unexpectedDiagnostics": unexpected,
              "native_sha256": sha(FIXTURE / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge"),
              "component_sha256": sha(PACKAGE / "AccessibilityBridge.4DZ")}
    (BUILD / "alp-grid-compile-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: complete AreaList fixture compilation")
    for diagnostic in unexpected:
        print(diagnostic)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
