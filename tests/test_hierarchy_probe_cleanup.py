"""Reject stale success and bound cleanup of an owned hierarchy probe process."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_hierarchy_probe import finish_run


class CleanupTests(unittest.TestCase):
    def run_case(self, *, exit_code=0, marker="current", error=False, finished=True, timeout=False):
        with tempfile.TemporaryDirectory() as directory:
            resources = Path(directory)
            if marker is not None:
                (resources / "closed.json").write_text(json.dumps({"runId": marker}))
            if error:
                (resources / "error.json").write_text('{"error": 1}')
            result = resources / "result.json"
            result.write_text('{"passed": true, "runId": "old"}')
            process = Mock(returncode=exit_code)
            process.poll.return_value = exit_code
            if timeout:
                process.returncode = None
                process.poll.return_value = None
                def wait(timeout):
                    if process.returncode is None:
                        raise subprocess.TimeoutExpired("owned fixture", timeout)
                    return process.returncode
                def terminate():
                    process.returncode = -15
                    process.poll.return_value = -15
                process.wait.side_effect = wait
                process.terminate.side_effect = terminate
            report = {"passed": False, "runId": "current", "checks": []}
            finish_run(process, resources, "current", report, result, finished)
            self.assertEqual(json.loads(result.read_text()), report)
            self.assertEqual(report["runId"], "current")
            return report, process

    def test_clean_exit_and_matching_marker_pass(self):
        report, process = self.run_case()
        self.assertTrue(report["passed"])
        process.terminate.assert_not_called()

    def test_nonzero_exit_replaces_old_success(self):
        report, _ = self.run_case(exit_code=1)
        self.assertFalse(report["passed"])

    def test_missing_close_marker_replaces_old_success(self):
        report, _ = self.run_case(marker=None)
        self.assertFalse(report["passed"])

    def test_wrong_close_marker_replaces_old_success(self):
        report, _ = self.run_case(marker="old")
        self.assertFalse(report["passed"])

    def test_final_error_rejects_success(self):
        report, _ = self.run_case(error=True)
        self.assertFalse(report["passed"])

    def test_incomplete_checks_reject_success_after_clean_exit(self):
        report, _ = self.run_case(finished=False)
        self.assertFalse(report["passed"])

    def test_close_timeout_terminates_owned_process_and_writes_failure(self):
        report, process = self.run_case(timeout=True)
        self.assertFalse(report["passed"])
        self.assertEqual(report["exitCode"], -15)
        self.assertTrue(report["shutdownErrors"])
        process.terminate.assert_called_once_with()
        process.kill.assert_not_called()


if __name__ == "__main__":
    unittest.main()
