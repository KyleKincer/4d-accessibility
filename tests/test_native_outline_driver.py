"""A missing acceptance source must invalidate old success before any launch."""
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("outline_driver", ROOT / "test_native_outlines.py")
driver = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {"mac_ax": types.ModuleType("mac_ax")}):
    spec.loader.exec_module(driver)


class EvidenceInvalidation(unittest.TestCase):
    def test_missing_source_invalidates_both_report_modes(self):
        for voiceover in (False, True):
            with self.subTest(voiceover=voiceover), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "build").mkdir()
                report = root / "build" / ("native-outline-voiceover.json" if voiceover else "native-outline.json")
                report.write_text(json.dumps({"passed": True, "count": 999}))
                args = ["test_native_outlines.py", "--run"] + (["--voiceover"] if voiceover else [])
                with patch.object(driver, "ROOT", root), patch.object(driver, "SOURCES", ["missing.mm"]), \
                        patch.object(sys, "argv", args), patch.object(driver.subprocess, "run", side_effect=AssertionError("Compiler must not run")), \
                        patch.object(driver.subprocess, "Popen", side_effect=AssertionError("Desktop must not launch")):
                    with self.assertRaises(FileNotFoundError):
                        driver.main()
                self.assertIs(json.loads(report.read_text())["passed"], False)
                self.assertEqual(json.loads(report.read_text())["checks"], [])

    def test_actual_missing_ax_import_invalidates_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src").mkdir(); (root / "tests").mkdir(); (root / "build").mkdir()
            (root / "test_native_outlines.py").write_text((ROOT / "test_native_outlines.py").read_text())
            for name in ("NativeOutlineFixture.mm", "voiceover.py", "ReadScreen.swift"):
                (root / "tests" / name).write_text("// Dummy source\n")
            report = root / "build/native-outline.json"
            report.write_text(json.dumps({"passed": True}))
            result = subprocess.run([sys.executable, str(root / "test_native_outlines.py"), "--run"], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FileNotFoundError", result.stderr)
            self.assertIn("mac_ax.py", result.stderr)
            self.assertIs(json.loads(report.read_text())["passed"], False)


if __name__ == "__main__":
    unittest.main()
