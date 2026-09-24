#!/usr/bin/env python3
"""Verify the optional host API without opening a host application or business data.

The host compiles with neither dependency present. The identical compiled host
then runs with neither, either, and both dependencies in fresh utility projects.
The actual host entry point checks both dependencies and API compatibility.
Unknown operations and attempts to use UI operations without a form are rejected.
No accessibility actions are performed.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    args = parser.parse_args()
    server = args.server.expanduser().resolve()
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.4D.4DServer":
        parser.error("--server must identify 4D Server")
    executable = server / "Contents/MacOS" / info["CFBundleExecutable"]
    plugin = BUILD / "AccessibilityBridge.bundle"
    report_file = BUILD / "optional-loading-report.json"
    report = {"passed": False, "state": "running", "cases": []}
    report_file.write_text(json.dumps(report) + "\n")
    with tempfile.TemporaryDirectory(prefix="optional-loading-", dir=BUILD) as temp:
        stage = Path(temp)
        host = stage / "host"
        project = project_at(host, "OptionalHost")
        methods = host / "Project/Sources/Methods"
        for method in (ROOT / "host/OptionalMethods").glob("*.4dm"):
            shutil.copy2(method, methods / method.name)
        source = '''var $result : Object
ON ERR CALL("AXBO_Error")
$result:=New object("success"; True; "compiled"; Is compiled mode)
$result.info:=AXB_Host("info"; New object)
$result.unknown:=AXB_Host("QUIT 4D"; New object)
$result.invalid:=AXB_Host("info"; Null)
$result.start:=AXB_Host("start"; New object)
$result.stop:=AXB_Host("stop"; New object)
$result.node:=AXB_Host("node"; New object)
$result.exchange:=AXB_Host("exchange"; New object)
File("/RESOURCES/result.json").setText(JSON Stringify($result; *))
QUIT 4D
'''
        (methods / "AXBO_Run.4dm").write_text(source)
        (methods / "AXBO_Error.4dm").write_text('''File("/RESOURCES/result.json").setText(JSON Stringify(New object("success"; False; "error"; Error; "method"; Error method; "line"; Error line)))
QUIT 4D
ABORT
''')
        driver = stage / "driver"
        project_at(driver, "Driver")
        compiled = run_utility(executable, driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$result:=Compile project(File({literal(project)}); $options)', 90)
        report["compiler"] = compiled
        report["sourceSha256"] = sha(methods / "AXBO_Run.4dm")
        report["hostSourceSha256"] = {p.name: sha(p) for p in (ROOT / "host/OptionalMethods").glob("*.4dm")}
        report["nativeSha256"] = sha(plugin / "Contents/MacOS/AccessibilityBridge")
        report["componentSha256"] = sha(PACKAGE / "AccessibilityBridge.4DZ")
        if compiled.get("success") is not True or compiled.get("errors"):
            report_file.write_text(json.dumps(report, indent=2) + "\n")
            raise SystemExit("Optional host did not compile cleanly without dependencies")
        # AreaList-specific hosts require the vendor plugin itself. Its host adapters must not
        # require either optional bridge dependency merely to compile.
        grid_host = stage / "grid-host"
        grid_project = project_at(grid_host, "OptionalGridHost")
        grid_methods = grid_host / "Project/Sources/Methods"
        for method in (ROOT / "host/Methods").glob("AXB_ALP*.4dm"):
            shutil.copy2(method, grid_methods / method.name)
        for method in (ROOT / "host/OptionalMethods").glob("*.4dm"):
            shutil.copy2(method, grid_methods / method.name)
        declarations = (ROOT / "host/Methods/Compiler_AXB.4dm").read_text().splitlines()
        (grid_methods / "Compiler_Grid.4dm").write_text("\n".join(line for line in declarations if "AXB_ALP" in line) + "\n")
        shutil.copytree(ROOT / "fixture/Plugins/ALP.bundle", grid_host / "Plugins/ALP.bundle")
        grid_compiled = run_utility(executable, driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(grid_host / "Plugins")})\n'
            f'$result:=Compile project(File({literal(grid_project)}); $options)', 90)
        report["areaListHostCompile"] = {"compiler": grid_compiled, "nativeInstalled": False, "componentInstalled": False,
                                        "sources_sha256": {p.name: sha(p) for p in grid_methods.glob("*.4dm")}}
        if grid_compiled.get("success") is not True or grid_compiled.get("errors"):
            report_file.write_text(json.dumps(report, indent=2) + "\n")
            raise SystemExit("AreaList host adapters did not compile without bridge dependencies")
        print("PASS: AreaList host adapters compile with neither bridge dependency", flush=True)
        incompatible = stage / "incompatible/AccessibilityBridge.4dbase"
        incompatible_project = project_at(incompatible, "AccessibilityBridge")
        (incompatible / "Project/Sources/Methods/AXB_ComponentInfo.4dm").write_text('''//%attributes = {"shared":true}
#DECLARE -> $info : Object
$info:=New object("protocol"; 1; "hostAPI"; 999; "compiled"; True)
''')
        (incompatible / "Project/Sources/Methods/Compiler_Info.4dm").write_text('C_OBJECT(AXB_ComponentInfo; $0)\n')
        # This component deliberately has no AXB_Dispatch. The compatibility
        # guard must reject it before attempting that fixed method call.
        incompatible_compiled = run_utility(executable, driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$result:=Compile project(File({literal(incompatible_project)}); $options)', 90)
        if incompatible_compiled.get("success") is not True or incompatible_compiled.get("errors"):
            raise SystemExit("Incompatible component fixture did not compile")
        for native, component, compatible in ((False, False, True), (True, False, True), (False, True, True), (True, True, True), (True, True, False)):
            case = stage / f"case-{int(native)}-{int(component)}-{int(compatible)}"
            shutil.copytree(host, case)
            if native:
                shutil.copytree(plugin, case / "Plugins/AccessibilityBridge.bundle")
            if component:
                shutil.copytree(PACKAGE if compatible else incompatible, case / "Components/AccessibilityBridge.4dbase")
            for mode in ("interpreted", "compiled"):
                output = case / "Resources/result.json"
                output.unlink(missing_ok=True)
                with open(case / "stdout.log", "wb") as stdout, open(case / "stderr.log", "wb") as stderr:
                    os.chmod(stdout.name, 0o600)
                    os.chmod(stderr.name, 0o600)
                    completed = subprocess.run([
                        str(executable), "--project", str(case / "Project/OptionalHost.4DProject"),
                        "--headless", "--dataless", "--utility", "--skip-onstartup",
                        "--opening-mode", mode, "--startup-method", "AXBO_Run",
                        "--webadmin-auto-start", "false",
                    ], stdout=stdout, stderr=stderr, timeout=45)
                result = json.loads(output.read_text(encoding="utf-8-sig")) if output.exists() else {}
                passed = completed.returncode == 0 and result.get("success") is True
                passed = passed and result.get("compiled") is (mode == "compiled")
                passed = passed and result.get("unknown") == {"ok": False, "error": "unsupportedOperation"}
                passed = passed and result.get("invalid") == {"ok": False, "error": "invalidRequest"}
                info = result.get("info", {})
                if native and component and compatible:
                    component_info = info.get("componentInfo", {})
                    passed = passed and info.get("ok") is True and info.get("hostAPI") == 1
                    passed = passed and info.get("nativeStatus", "").startswith("Accessibility Bridge ")
                    passed = passed and component_info.get("protocol") == 1 and component_info.get("hostAPI") == 1 and component_info.get("compiled") is True
                    passed = passed and component_info.get("hostCompiled") is (mode == "compiled")
                elif not native or not component:
                    passed = passed and info == {"ok": False, "error": "dependencyUnavailable", "native": native, "component": component}
                else:
                    passed = passed and info == {"ok": False, "error": "incompatibleComponent"}
                for operation in ("start", "stop", "node", "exchange"):
                    expected = {"ok": False, "error": "noFormContext"} if native and component and compatible else info
                    passed = passed and result.get(operation) == expected
                report["cases"].append({"nativeInstalled": native, "componentInstalled": component, "compatibleComponent": compatible, "mode": mode, "passed": passed, "runtime": result})
                report_file.write_text(json.dumps(report, indent=2) + "\n")
                print(f"{'PASS' if passed else 'FAIL'}: native={native}, component={component}, compatible={compatible}, mode={mode}", flush=True)
                if not passed:
                    raise SystemExit("Optional dependency runtime probe failed; see report")
    report.update(passed=True, state="finished")
    report_file.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (Exception, SystemExit):
        report_file = BUILD / "optional-loading-report.json"
        if report_file.exists():
            report = json.loads(report_file.read_text())
            if report.get("state") == "running":
                report.update(passed=False, state="failed")
                report_file.write_text(json.dumps(report, indent=2) + "\n")
        raise
