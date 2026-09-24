"""Secret-file guarantees for the bootstrap helper; uses synthetic values only."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("alp_setup", Path(__file__).parents[1] / "setup_alp_license.py")
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)
SYNTHETIC = "SYNTHETIC-LICENSE-FOR-TESTS-ONLY"


class LicenseSetupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.target = self.root / "fixture/Resources/alp.license"
        self.root_patch = patch.object(SETUP, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def invoke(self, arguments=(), response=None):
        response = response or subprocess.CompletedProcess([], 0, json.dumps({"fields": [{"id": "reg_code", "value": SYNTHETIC}]}), "")
        output = io.StringIO()
        with patch("sys.argv", ["setup_alp_license.py", *arguments]), patch.object(SETUP.subprocess, "run", return_value=response) as run, contextlib.redirect_stdout(output):
            SETUP.main()
        self.assertNotIn(SYNTHETIC, output.getvalue())
        self.assertNotIn(SYNTHETIC, str(run.call_args))
        return run

    def test_protected_file_and_no_secret_output(self):
        self.invoke()
        self.assertEqual(self.target.read_text(), SYNTHETIC)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        self.assertEqual(list(self.target.parent.iterdir()), [self.target])

    def test_existing_file_is_preserved(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("original")
        with self.assertRaises(SystemExit):
            self.invoke()
        self.assertEqual(self.target.read_text(), "original")

    def test_explicit_replace_remains_protected(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("original")
        os.chmod(self.target, 0o644)
        self.invoke(["--replace"])
        self.assertEqual(self.target.read_text(), SYNTHETIC)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)

    def test_symlink_target_is_rejected(self):
        self.target.parent.mkdir(parents=True)
        outside = self.root / "outside"
        outside.write_text("untouched")
        self.target.symlink_to(outside)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.invoke(["--replace"])
        self.assertEqual(outside.read_text(), "untouched")

    def test_failed_cli_does_not_disclose_stderr(self):
        response = subprocess.CompletedProcess([], 1, "", SYNTHETIC)
        with self.assertRaises(SystemExit) as failure:
            self.invoke(response=response)
        self.assertNotIn(SYNTHETIC, str(failure.exception))
        self.assertFalse(self.target.exists())

    def test_multiple_keys_are_rejected(self):
        response = subprocess.CompletedProcess([], 0, json.dumps({"fields": [{"id": "reg_code", "value": "first\nsecond"}]}), "")
        with self.assertRaises(SystemExit):
            self.invoke(response=response)
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main()
