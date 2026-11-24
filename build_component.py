#!/usr/bin/env python3
"""Build compiled 4D components from the canonical host methods.

Uses the compile/copy/strip/ZIP sequence in 4D's Build4D 4D-20.x builder.
All compilation and packaging occur in a fresh disposable utility project.
Never opens a host application or copies its data, settings, credentials, or resources.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
CORE = ("AXB_Start", "AXB_Stop", "AXB_Pulse", "AXB_Poll", "AXB_ControlNode", "AXB_Dispatch", "AXB_WatcherTick", "AXB_Bridge")
PUBLIC = ("AXB_Start", "AXB_Stop", "AXB_ControlNode", "AXB_ComponentInfo", "AXB_Dispatch", "AXB_WatcherTick", "AXB_Bridge", "AXB_PictureEquals")
ALP_CORE = ("AXB_ALPGrid", "AXB_ALPGridAction", "AXB_ALPGridConfirm", "AXB_ALPGridValue", "AXB_ALPEditor", "AXB_ALPNode", "AXB_ALPRows", "AXB_ALPRowsSelect", "AXB_ALPSelect", "AXB_ALPTable")
ALP_PUBLIC = ("AXB_ALPGrid",)
TARGETS = ("arm64_macOS_lib", "x86_64_generic")
PACKAGE = BUILD / "AccessibilityBridge.4dbase"
ALP_PACKAGE = BUILD / "AccessibilityBridge_ALP.4dbase"
REPORT = BUILD / "component-build-report.json"
ALP_REPORT = BUILD / "alp-component-build-report.json"
FIXTURE = BUILD / "component-fixture"


def optional_methods():
    return tuple(sorted(p.stem for p in (ROOT / "host/OptionalMethods").glob("AXB_*.4dm")))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def literal(value):
    return json.dumps(str(value), ensure_ascii=False)


def project_at(root, name):
    sources = root / "Project/Sources"
    (sources / "Methods").mkdir(parents=True)
    (root / "Resources").mkdir()
    project = root / f"Project/{name}.4DProject"
    project.write_text("{}\n")
    (sources / "catalog.4DCatalog").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE base SYSTEM "http://www.4d.com/dtd/2007/base.dtd">\n'
        f'<base name="{name}" uuid="{uuid.uuid4().hex.upper()}" collation_locale="en">'
        '<schema name="DEFAULT_SCHEMA"/></base>\n'
    )
    return project


def run_utility(executable, driver, body, timeout):
    result = driver / "Resources/result.json"
    result.unlink(missing_ok=True)
    (driver / "Project/Sources/Methods/AXBC_Run.4dm").write_text(
        'var $result; $options : Object\nON ERR CALL("AXBC_Error")\n'
        + body + '\nFile("/RESOURCES/result.json").setText(JSON Stringify($result; *))\nQUIT 4D\n'
    )
    (driver / "Project/Sources/Methods/AXBC_Error.4dm").write_text(
        'var $failure : Object\n'
        '$failure:=New object("success"; False; "error"; Error; "method"; Error method; "line"; Error line)\n'
        'File("/RESOURCES/result.json").setText(JSON Stringify($failure))\nQUIT 4D\nABORT\n'
    )
    with open(driver / "stdout.log", "wb") as out, open(driver / "stderr.log", "wb") as err:
        os.chmod(out.name, 0o600)
        os.chmod(err.name, 0o600)
        completed = subprocess.run([
            str(executable), "--project", str(driver / "Project/Driver.4DProject"),
            "--dataless", "--skip-onstartup", "--startup-method", "AXBC_Run",
            *([] if executable.name == "tool4d" else ["--headless", "--utility", "--webadmin-auto-start", "false"]),
        ], stdout=out, stderr=err, timeout=timeout)
    if completed.returncode or not result.is_file():
        raise RuntimeError(f"4D utility exited {completed.returncode} without a result")
    return json.loads(result.read_text(encoding="utf-8-sig"))


def verify_package(package):
    archive = package / "AccessibilityBridge.4DZ"
    library = package / "Libraries/lib4d-arm64.dylib"
    if not library.is_file() or library.stat().st_size == 0:
        raise RuntimeError("Missing compiled ARM library")
    if not (package / "Resources/watcher-capabilities.json").is_file():
        raise RuntimeError("Missing watcher-capabilities.json")
    expected_methods = set(CORE) | set(optional_methods()) | {"AXB_ComponentInfo", "Compiler_AXBCore"}
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise RuntimeError("Component archive failed its CRC check")
        names = z.namelist()
        if any(n.lower().endswith(".4dm") or ".." in Path(n).parts or n.startswith("/") for n in names):
            raise RuntimeError("Archive includes method source or an invalid path")
        mapping = json.loads(z.read("Project/DerivedData/CompiledCode/map.json"))
        if any(mapping.get("targets", {}).get(t) is not True for t in TARGETS):
            raise RuntimeError("Component does not contain both compiled targets")
        methods = {Path(m["path"]).stem for m in mapping["map"]}
        if methods != expected_methods:
            missing = sorted(expected_methods - methods)
            extra = sorted(methods - expected_methods)
            raise RuntimeError(f"Unexpected compiled methods in component (missing={missing}, extra={extra})")
        attributes = json.loads(z.read("Project/DerivedData/methodAttributes.json"))
        shared = {name for name, value in attributes["methods"].items() if value.get("attributes", {}).get("shared") is True}
        if shared != set(PUBLIC):
            raise RuntimeError(f"Component exports differ from the declared public interface: {sorted(shared)}")
    return {"archiveEntries": len(names), "targets": mapping["targets"], "methodAttributes": attributes}


def verify_alp_package(package):
    archive = package / "AccessibilityBridge_ALP.4DZ"
    library = package / "Libraries/lib4d-arm64.dylib"
    if not library.is_file() or library.stat().st_size == 0:
        raise RuntimeError("Missing compiled ARM library in ALP component")
    expected_methods = set(ALP_CORE) | {"Compiler_AXBALP"}
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise RuntimeError("ALP component archive failed its CRC check")
        names = z.namelist()
        if any(n.lower().endswith(".4dm") or ".." in Path(n).parts or n.startswith("/") for n in names):
            raise RuntimeError("ALP archive includes method source or an invalid path")
        mapping = json.loads(z.read("Project/DerivedData/CompiledCode/map.json"))
        if any(mapping.get("targets", {}).get(t) is not True for t in TARGETS):
            raise RuntimeError("ALP component does not contain both compiled targets")
        methods = {Path(m["path"]).stem for m in mapping["map"]}
        if methods != expected_methods:
            raise RuntimeError(f"Unexpected compiled methods in ALP component: {sorted(methods)}")
        attributes = json.loads(z.read("Project/DerivedData/methodAttributes.json"))
        shared = {name for name, value in attributes["methods"].items() if value.get("attributes", {}).get("shared") is True}
        if shared != set(ALP_PUBLIC):
            raise RuntimeError(f"ALP component exports differ from declared interface: {sorted(shared)}")
    return {"archiveEntries": len(names), "targets": mapping["targets"], "methodAttributes": attributes}


def prepare_fixture():
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        raise RuntimeError("Close 4D before preparing the disposable component fixture")
    source = ROOT / "fixture"
    # Preserve previous generated fixtures for diagnosis; never replace loaded files.
    if FIXTURE.exists():
        FIXTURE.rename(BUILD / ("component-fixture-previous-" + uuid.uuid4().hex))
    (FIXTURE / "Project").mkdir(parents=True)
    shutil.copy2(source / "Project/AccessibilityProbe.4DProject", FIXTURE / "Project/AccessibilityProbe.4DProject")
    shutil.copytree(source / "Project/Sources", FIXTURE / "Project/Sources")
    (FIXTURE / "Plugins").mkdir()
    for name in ("AccessibilityBridge.bundle", "ALP.bundle"):
        plugin = BUILD / name if name == "AccessibilityBridge.bundle" else source / "Plugins" / name
        shutil.copytree(plugin, FIXTURE / "Plugins" / name)
    shutil.copytree(PACKAGE, FIXTURE / "Components/AccessibilityBridge.4dbase")
    (FIXTURE / "Resources").mkdir()
    (FIXTURE / "Data").mkdir()
    license_file = source / "Resources/alp.license"
    if license_file.exists():
        shutil.copy2(license_file, FIXTURE / "Resources/alp.license")
        os.chmod(FIXTURE / "Resources/alp.license", 0o600)
    for name in CORE:
        (FIXTURE / f"Project/Sources/Methods/{name}.4dm").unlink(missing_ok=True)
    compiler = FIXTURE / "Project/Sources/Methods/Compiler_AXB.4dm"
    compiler.write_text("\n".join(line for line in compiler.read_text().splitlines() if "AXB_ALP" in line) + "\n")
    method = FIXTURE / "Project/Sources/Forms/Probe/method.4dm"
    content = method.read_text().replace("var $error : Integer", "var $error : Integer\nvar $componentInfo : Object")
    content = content.replace('  Form.build:=$nativeStatus+"; 4D mode: "+$mode',
        '  $componentInfo:=AXB_ComponentInfo\n'
        '  File("/RESOURCES/component-info.json").setText(JSON Stringify($componentInfo))\n'
        '  Form.build:=$nativeStatus+"; 4D mode: "+$mode+"; component mode: "+Choose($componentInfo.compiled; "compiled"; "interpreted")')
    method.write_text(content)
    print(f"Prepared disposable fixture: {FIXTURE}")


def build_alp_component(executable, app, alp_plugin, version, timeout):
    if not alp_plugin.is_dir():
        raise RuntimeError(f"AreaList Pro plugin not found: {alp_plugin}")
    with tempfile.TemporaryDirectory(prefix="axb-alp-component-") as temp_dir:
        temp = Path(temp_dir).resolve()
        driver = temp / "driver"
        source = temp / "source"
        output = temp / "AccessibilityBridge_ALP.4dbase"
        project_at(driver, "Driver")
        project = project_at(source, "AccessibilityBridge_ALP")
        methods = source / "Project/Sources/Methods"
        source_hashes = {}
        for name in ALP_CORE:
            src = ROOT / f"host/Methods/{name}.4dm"
            source_hashes[f"host/Methods/{name}.4dm"] = sha(src)
            header = '//%attributes = {"shared":true}\n' if name in ALP_PUBLIC else '//%attributes = {"shared":false}\n'
            (methods / f"{name}.4dm").write_text(header + src.read_text())
        compiler_lines = [line for line in (ROOT / "host/Methods/Compiler_AXB.4dm").read_text().splitlines() if "AXB_ALP" in line]
        (methods / "Compiler_AXBALP.4dm").write_text("\n".join(compiler_lines) + "\n")
        shutil.copytree(alp_plugin, source / "Plugins" / alp_plugin.name)

        compile_result = run_utility(executable, driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none"; "generateTypingMethods"; "keep"; "generateSymbols"; False)\n'
            f'$result:=Compile project(File({literal(project)}; fk platform path); $options)', timeout)
        if not compile_result.get("success"):
            ALP_REPORT.write_text(json.dumps({"passed": False, "compile": compile_result}, indent=2) + "\n")
            raise RuntimeError("ALP component compilation failed; inspect alp-component-build-report.json")

        shutil.copytree(source / "Project", output / "Project")
        shutil.copytree(source / "Libraries", output / "Libraries")
        shutil.copytree(source / "Resources", output / "Resources")
        shutil.rmtree(output / "Project/Sources/Methods")
        for path in list((output / "Project/DerivedData/CompiledCode").glob("*.json")):
            if path.name != "map.json":
                path.unlink()
        zip_result = run_utility(executable, driver,
            f'$result:=ZIP Create archive(Folder({literal(output / "Project")}; fk platform path); File({literal(output / "AccessibilityBridge_ALP.4DZ")}; fk platform path); New object("compression"; ZIP Compression standard; "level"; 6))',
            timeout)
        if not zip_result.get("success"):
            raise RuntimeError("ALP component packaging failed")
        shutil.rmtree(output / "Project")
        verification = verify_alp_package(output)
        if ALP_PACKAGE.exists():
            shutil.rmtree(ALP_PACKAGE)
        shutil.copytree(output, ALP_PACKAGE)
        ALP_REPORT.write_text(json.dumps({
            "passed": True,
            "version": version,
            "compiler": str(app),
            "alpPlugin": alp_plugin.name,
            "sources": source_hashes,
            "publicMethods": list(ALP_PUBLIC),
            "compile": compile_result,
            "verification": verification,
            "archiveSHA256": sha(ALP_PACKAGE / "AccessibilityBridge_ALP.4DZ"),
        }, indent=2) + "\n")
        print(f"Built ALP component: {ALP_PACKAGE}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    compiler = parser.add_mutually_exclusive_group(required=True)
    compiler.add_argument("--server", type=Path, help="Licensed 4D Server application")
    compiler.add_argument("--tool4d", type=Path, help="tool4d application for headless CI builds")
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--prepare-fixture", action="store_true")
    parser.add_argument("--area-list", action="store_true", help="Also build optional AccessibilityBridge_ALP.4dbase")
    parser.add_argument("--alp-plugin", type=Path, help="Path to AreaList Pro plugin bundle for --area-list")
    args = parser.parse_args()
    if args.timeout < 1:
        raise SystemExit("timeout must be positive")
    app = args.server or args.tool4d
    executable = app / ("Contents/MacOS/4D Server" if args.server else "Contents/MacOS/tool4d")
    if not executable.is_file():
        raise SystemExit(f"4D compiler executable not found: {executable}")
    plugin = BUILD / "AccessibilityBridge.bundle"
    if not plugin.is_dir():
        raise SystemExit(f"Build the native plugin first: {plugin}")
    version = plistlib.loads((plugin / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
    opt_names = optional_methods()
    with tempfile.TemporaryDirectory(prefix="axb-component-") as temp_dir:
        temp = Path(temp_dir).resolve()
        driver = temp / "driver"
        source = temp / "source"
        output = temp / "AccessibilityBridge.4dbase"
        project_at(driver, "Driver")
        project = project_at(source, "AccessibilityBridge")
        methods = source / "Project/Sources/Methods"
        source_hashes = {}
        for name in CORE:
            src = ROOT / f"host/Methods/{name}.4dm"
            source_hashes[f"host/Methods/{name}.4dm"] = sha(src)
            header = '//%attributes = {"shared":true}\n' if name in PUBLIC else '//%attributes = {"shared":false}\n'
            (methods / f"{name}.4dm").write_text(header + src.read_text())
        for name in opt_names:
            src = ROOT / f"host/OptionalMethods/{name}.4dm"
            source_hashes[f"host/OptionalMethods/{name}.4dm"] = sha(src)
            header = '//%attributes = {"shared":true}\n' if name in PUBLIC else '//%attributes = {"shared":false}\n'
            (methods / f"{name}.4dm").write_text(header + src.read_text())
        (methods / "AXB_ComponentInfo.4dm").write_text(
            '//%attributes = {"shared":true}\n'
            '#DECLARE() -> $info : Object\n'
            f'$info:=New object("version"; {literal(version)}; "hostAPI"; 1; "consolidated"; True; "autoWatch"; True; "compiled"; Is compiled mode; "component"; "AccessibilityBridge")\n'
        )
        compiler_lines = [line for line in (ROOT / "host/Methods/Compiler_AXB.4dm").read_text().splitlines() if "AXB_ALP" not in line]
        host_compiler_lines = (ROOT / "host/OptionalMethods/Compiler_AXBHost.4dm").read_text().splitlines()
        (methods / "Compiler_AXBCore.4dm").write_text(
            "\n".join(compiler_lines)
            + "\n"
            + "\n".join(host_compiler_lines)
            + '\nC_OBJECT(AXB_ComponentInfo; $0)\nC_OBJECT(AXB_CoreWindows)\n'
        )
        shutil.copytree(plugin, source / "Plugins/AccessibilityBridge.bundle")

        compile_result = run_utility(executable, driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none"; "generateTypingMethods"; "keep"; "generateSymbols"; False)\n'
            f'$result:=Compile project(File({literal(project)}; fk platform path); $options)', args.timeout)
        if not compile_result.get("success"):
            REPORT.write_text(json.dumps({"passed": False, "compile": compile_result}, indent=2) + "\n")
            raise RuntimeError("Component compilation failed; inspect component-build-report.json")

        shutil.copytree(source / "Project", output / "Project")
        shutil.copytree(source / "Libraries", output / "Libraries")
        shutil.copytree(source / "Resources", output / "Resources")
        (output / "Resources/watcher-capabilities.json").write_text(json.dumps({
            "schema": 1,
            "version": version,
            "watcherMethod": "AXB_WatcherTick",
            "consolidated": True,
        }, indent=2) + "\n")
        shutil.rmtree(output / "Project/Sources/Methods")
        for path in list((output / "Project/DerivedData/CompiledCode").glob("*.json")):
            if path.name != "map.json":
                path.unlink()
        zip_result = run_utility(executable, driver,
            f'$result:=ZIP Create archive(Folder({literal(output / "Project")}; fk platform path); File({literal(output / "AccessibilityBridge.4DZ")}; fk platform path); New object("compression"; ZIP Compression standard; "level"; 6))',
            args.timeout)
        if not zip_result.get("success"):
            REPORT.write_text(json.dumps({"passed": False, "compile": compile_result, "zip": zip_result}, indent=2) + "\n")
            raise RuntimeError("Component packaging failed; inspect component-build-report.json")
        shutil.rmtree(output / "Project")
        verification = verify_package(output)
        if PACKAGE.exists():
            shutil.rmtree(PACKAGE)
        shutil.copytree(output, PACKAGE)
        native_binary = plugin / "Contents/MacOS/AccessibilityBridge"
        REPORT.write_text(json.dumps({
            "passed": True,
            "version": version,
            "compiler": str(app),
            "nativeSHA256": sha(native_binary),
            "sources": source_hashes,
            "publicMethods": list(PUBLIC),
            "compile": compile_result,
            "verification": verification,
            "archiveSHA256": sha(PACKAGE / "AccessibilityBridge.4DZ"),
            "arm64LibrarySHA256": sha(PACKAGE / "Libraries/lib4d-arm64.dylib"),
        }, indent=2) + "\n")
        print(f"Built component: {PACKAGE}")
    if args.area_list:
        alp_plugin = args.alp_plugin or (ROOT / "fixture/Plugins/ALP.bundle")
        build_alp_component(executable, app, alp_plugin, version, args.timeout)
    if args.prepare_fixture:
        prepare_fixture()


if __name__ == "__main__":
    main()
