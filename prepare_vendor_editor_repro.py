#!/usr/bin/env python3
"""Prepare a bridge-free AreaList Unicode reproduction in an ignored directory."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil

from build_component import project_at

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--area-list-plugin", type=Path, required=True)
    parser.add_argument("--license-file", type=Path)
    parser.add_argument("--operation", choices=["get", "value", "copy", "commit"], default="get")
    parser.add_argument("--text", choices=["ascii", "bmp", "supplementary"], default="supplementary")
    args = parser.parse_args()
    vendor = args.area_list_plugin.resolve()
    metadata = plistlib.loads((vendor / "Contents/Info.plist").read_bytes())
    if metadata.get("CFBundleExecutable") != "ALP":
        parser.error("--area-list-plugin must be the AreaList Pro bundle")
    base = ROOT / "build/vendor-editor-repro"
    if base.exists():
        parser.error("build/vendor-editor-repro already exists; retain its evidence or remove that disposable project first")
    project = project_at(base, "VendorEditorRepro")
    base.chmod(0o700)
    shutil.copytree(vendor, base / "Plugins/ALP.bundle")
    if args.license_file:
        license_file = base / "Resources/alp.license"
        # Restrict access before copying any license bytes.
        license_file.touch(mode=0o600)
        license_file.write_bytes(args.license_file.read_bytes())
    text = {"ascii": "Plain text " * 500, "bmp": "café Łódź 中文 e\u0301 " * 500,
            "supplementary": "🎸" * 1000}[args.text]
    (base / "Resources/input.txt").write_text(text)
    (base / "Resources/config.json").write_text(json.dumps({"operation": args.operation, "text": args.text,
        "vendorVersion": metadata["CFBundleVersion"]}, indent=2) + "\n")
    methods = base / "Project/Sources/Methods"
    database = base / "Project/Sources/DatabaseMethods"
    database.mkdir()
    (methods / "Compiler.4dm").write_text("ARRAY TEXT(reproText; 0)\n")
    (database / "onStartup.4dm").write_text('''var $window; $registration : Integer
If (File("/RESOURCES/alp.license").exists)
 $registration:=AL_Register(File("/RESOURCES/alp.license").getText(); 0)
End if
ARRAY TEXT(reproText; 1)
reproText{1}:="Original value"
$window:=Open form window("Editor"; Plain form window)
DIALOG("Editor"; New object("ticks"; 0; "running"; False))
CLOSE WINDOW($window)
QUIT 4D
''')
    (methods / "RunRepro.4dm").write_text('''Form.running:=True
Form.ticks:=0
GOTO OBJECT(*; "Items")
AL_SetAreaTextProperty(Form.area; ALP_Area_EntryGotoCell; "1,1")
''')
    (methods / "Editor.4dm").write_text('''var $pointer : Pointer
var $error : Integer
var $text : Text
var $config; $result : Object
Case of
 : (Form event code=On Load)
  $pointer:=OBJECT Get pointer(Object named; "Items")
  Form.area:=$pointer->
  $error:=AL_SetArraysNam(Form.area; 1; 1; "reproText")
  AL_SetColumnLongProperty(Form.area; 1; ALP_Column_Enterable; 1)
  AL_SetColumnRealProperty(Form.area; 1; ALP_Column_Width; 380)
  AL_SetColumnTextProperty(Form.area; 1; ALP_Column_HeaderText; "Description")
  SET TIMER(6)
 : ((Form event code=On Timer) & Form.running)
  Form.ticks:=Form.ticks+1
  If (Form.ticks=2)
   SET TEXT TO PASTEBOARD(File("/RESOURCES/input.txt").getText())
   INVOKE ACTION(ak paste)
  End if
  If (Form.ticks=4)
   $config:=JSON Parse(File("/RESOURCES/config.json").getText())
   File("/RESOURCES/result.json").setText(JSON Stringify(New object("phase"; "before operation"; "operation"; $config.operation)))
   Case of
    : ($config.operation="get")
     $text:=AL_GetAreaTextProperty(Form.area; ALP_Area_EntryText)
    : ($config.operation="value")
     $error:=AL_GetAreaPtrProperty(Form.area; ALP_Area_EntryValue; ->$text)
    : ($config.operation="copy")
     INVOKE ACTION(ak select all)
     INVOKE ACTION(ak copy)
     $text:=Get text from pasteboard
    : ($config.operation="commit")
     GOTO OBJECT(*; "Run")
   End case
   $result:=New object("phase"; "after operation"; "operation"; $config.operation; "text"; $text)
   File("/RESOURCES/result.json").setText(JSON Stringify($result))
  End if
  If (Form.ticks=8)
   File("/RESOURCES/settled.json").setText(JSON Stringify(New object("value"; reproText{1})))
   Form.running:=False
  End if
End case
''')
    form = {"windowTitle": "AreaList Unicode reproduction", "width": 440, "height": 280,
        "method": "Editor", "events": ["onLoad", "onTimer"], "pages": [None, {"objects": {
            "Items": {"type": "plugin", "pluginAreaKind": "%AreaListPro", "dataSource": "",
                "dataSourceTypeHint": "integer", "left": 10, "top": 10, "width": 420, "height": 200},
            "Run": {"type": "button", "text": "Run reproduction", "left": 20, "top": 235,
                "width": 180, "height": 28, "method": "RunRepro", "events": ["onClick"]},
            "Close": {"type": "button", "text": "Close", "left": 320, "top": 235,
                "width": 100, "height": 28, "action": "cancel"}}}]}
    folder = base / "Project/Sources/Forms/Editor"
    folder.mkdir(parents=True)
    (folder / "form.4DForm").write_text(json.dumps(form, indent=2) + "\n")
    print(f"Prepared bridge-free reproduction: {project}")
    print("Run reproduction replaces the clipboard with synthetic text and can crash 4D. Use an isolated test session.")


if __name__ == "__main__":
    main()
