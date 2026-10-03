"""Invalid input-probe flags must reject before input or evidence changes."""

import io
from pathlib import Path
import sys
import tempfile
from types import ModuleType
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_hierarchy_probe as driver


class InputFlagTests(unittest.TestCase):
    def check_rejected(self, flags):
        with tempfile.TemporaryDirectory() as directory:
            build = Path(directory)
            image = build / "grouped-state-interpreted-0.png"
            image.write_bytes(b"existing evidence")
            ax = ModuleType("mac_ax")
            ax.require_test_input = Mock(side_effect=AssertionError("No input check may start"))
            desktop = ModuleType("fixture_desktop")
            desktop.activate_fixture = Mock()
            desktop.wait_for_start = Mock()
            stderr = io.StringIO()
            with (
                patch.object(driver, "BUILD", build),
                patch.object(sys, "argv", ["test_hierarchy_probe.py", "--run", *flags]),
                patch.object(sys, "stderr", stderr),
                patch.dict(sys.modules, {"mac_ax": ax, "fixture_desktop": desktop}),
                patch("subprocess.Popen", side_effect=AssertionError("No process may start")) as popen,
            ):
                with self.assertRaises(SystemExit) as error:
                    driver.main()
            self.assertEqual(error.exception.code, 2)
            self.assertIn("--grouped-inputs requires --commands and cannot combine with --grouped-states", stderr.getvalue())
            ax.require_test_input.assert_not_called()
            desktop.activate_fixture.assert_not_called()
            desktop.wait_for_start.assert_not_called()
            popen.assert_not_called()
            self.assertEqual(image.read_bytes(), b"existing evidence")
            self.assertEqual(list(build.iterdir()), [image])

    def test_requires_commands_before_input(self):
        self.check_rejected(["--grouped-inputs"])

    def test_rejects_combined_states_before_input(self):
        self.check_rejected(["--commands", "--grouped-inputs", "--grouped-states"])


if __name__ == "__main__":
    unittest.main()
