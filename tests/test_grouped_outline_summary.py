"""Reject stale grouped evidence without launching 4D or assistive input."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import summarize_grouped_outlines as summary


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def prepare(root):
    names = set(summary.canonical_sources()) | set(summary.DRIVER_SOURCES)
    names |= {str(p.relative_to(ROOT)) for directory in (ROOT / "src", ROOT / "host/Methods", ROOT / "resources/en.lproj")
              for p in directory.glob("*") if p.is_file()}
    names |= {"manifest.json", "build_component.py"}
    for name in names:
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    fixture = root / "build/hierarchy-probe"
    artifacts = ("Project/Sources/Methods/Fixture.4dm", "Libraries/lib4d-arm64.dylib", "Project/DerivedData/CompiledCode/MX64 test",
                 "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ",
                 "Components/AccessibilityBridge.4dbase/Libraries/lib4d-arm64.dylib")
    for name in artifacts:
        target = fixture / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(name + " synthetic test bytes\n")
    native_names = {name for name in names if name.startswith(("src/", "host/Methods/", "resources/en.lproj/"))} | {"manifest.json", "VERSION"}
    native_sources = {name: summary.sha(root / name) for name in sorted(native_names)}
    component_names = ["host/Methods/" + name + ".4dm" for name in summary.CORE] + ["host/Methods/Compiler_AXB.4dm", "VERSION", "build_component.py"]
    component_sources = {name: summary.sha(root / name) for name in component_names}
    native = summary.sha(fixture / artifacts[3])
    package = summary.files(fixture / "Components/AccessibilityBridge.4dbase")
    write(root / "build/build-report.json", {"binary_sha256": native, "sources_sha256": native_sources})
    write(root / "build/component-build-report.json", {"passed": True, "native_sha256": native,
          "package_sha256": package, "sources_sha256": component_sources})
    prepared = {"passed": True, "bridge": True, "compiler": {"success": True, "errors": []}, "changed_during_compile": [],
                "canonicalSourceSHA256": summary.canonical_sources(root), "preparerSHA256": summary.sha(root / "prepare_hierarchy_probe.py"),
                "sources_sha256": {"Project/Sources/" + name: value for name, value in summary.files(fixture / "Project/Sources").items()},
                "compiledHostSHA256": {name: summary.sha(fixture / name) for name in artifacts[1:3]},
                "componentPackageSHA256": package, "componentSHA256": package["AccessibilityBridge.4DZ"], "nativeSHA256": native,
                "nativeSourceSHA256": native_sources, "componentSourceSHA256": component_sources}
    write(root / "build/hierarchy-probe-compile.json", prepared)


class EvidenceGuard(unittest.TestCase):
    def test_prepared_artifact_and_source_changes_reject(self):
        mutations = ("delete", "rename", "add", "helper", "host-library", "component-library")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                prepare(root)
                summary.validate_prepared(root)
                source = root / "src/Grid.mm"
                if mutation == "delete":
                    source.unlink()
                elif mutation == "rename":
                    source.rename(source.with_name("Renamed.mm"))
                elif mutation == "add":
                    source.with_name("New.mm").write_text("new source\n")
                elif mutation == "helper":
                    (root / "host/OptionalMethods/AXB_OutlineCapture.4dm").write_text("changed helper\n")
                else:
                    name = "Libraries/lib4d-arm64.dylib" if mutation == "host-library" else "Components/AccessibilityBridge.4dbase/Libraries/lib4d-arm64.dylib"
                    (root / "build/hierarchy-probe" / name).write_text("older executable bytes\n")
                with self.assertRaises((AssertionError, OSError)):
                    summary.validate_prepared(root)
                output = root / "old-success.json"
                write(output, {"passed": True})
                with self.assertRaises((AssertionError, OSError)):
                    summary.publish(root, output)
                self.assertIs(json.loads(output.read_text())["passed"], False)

    def test_speech_subset_cannot_publish_as_full_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "speech.json"
            report = {"passed": True, "sourceSHA256": {name: summary.sha(ROOT / name) for name in summary.OUTLINE_SOURCES},
                      "cases": [{"case": name, "passed": True, "exitCode": 0} for name in summary.OUTLINE_CASES[:-1]]}
            write(path, report)
            with self.assertRaises(AssertionError):
                summary.validate_speech(ROOT, path, summary.OUTLINE_CASES, summary.OUTLINE_SOURCES)

    def test_missing_input_erases_published_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "summary.json"
            write(output, {"passed": True})
            with self.assertRaises(OSError):
                summary.publish(root, output)
            self.assertIs(json.loads(output.read_text())["passed"], False)

    def test_complete_case_names_require_actual_speech_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "speech.json"
            binary = path.parent / "NativeOutlineFixture"
            binary.write_text("synthetic binary\n")
            report = {"passed": True, "binarySHA256": summary.sha(binary),
                      "sourceSHA256": {name: summary.sha(ROOT / name) for name in summary.OUTLINE_SOURCES},
                      "cases": [{"case": name, "passed": True, "exitCode": 0} for name in summary.OUTLINE_CASES]}
            write(path, report)
            with self.assertRaises((AssertionError, KeyError)):
                summary.validate_speech(ROOT, path, summary.OUTLINE_CASES, summary.OUTLINE_SOURCES)


if __name__ == "__main__":
    unittest.main()
