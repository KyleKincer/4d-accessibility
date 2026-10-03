"""Reject prepared evidence after a canonical probe method disappears."""

import json
from pathlib import Path
import sys
import tempfile
from types import ModuleType
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import summarize_grouped_probe as summary


class SummaryTests(unittest.TestCase):
    def check_changed_method(self, *, rename):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / "build"
            canonical = root / "tests/4d"
            prepared = build / "hierarchy-probe/Project/Sources/Methods"
            canonical.mkdir(parents=True)
            prepared.mkdir(parents=True)
            preparer = root / "prepare_hierarchy_probe.py"
            preparer.write_text("# Synthetic preparer\n")
            for name in ("AXHP_Kept.4dm", "AXHP_Removed.4dm"):
                (canonical / name).write_text("// Synthetic method\n")
                (prepared / name).write_text("// Synthetic method\n")
            manifest = {
                "Project/Sources/Methods/" + path.name: summary.sha(path)
                for path in prepared.glob("*.4dm")
            }
            (build / "hierarchy-probe-compile.json").write_text(json.dumps({
                "passed": True,
                "compiler": {"success": True, "errors": []},
                "changed_during_compile": [],
                "preparerSHA256": summary.sha(preparer),
                "sources_sha256": manifest,
            }))
            removed = canonical / "AXHP_Removed.4dm"
            if rename:
                removed.rename(canonical / "AXHP_Renamed.4dm")
            else:
                removed.unlink()
            output = build / "published.json"
            output.write_text('{"passed": true, "date": "old"}\n')
            pillow = ModuleType("PIL")
            pillow.Image = ModuleType("Image")
            pillow.ImageChops = ModuleType("ImageChops")
            with (
                patch.object(summary, "ROOT", root),
                patch.object(summary, "BUILD", build),
                patch.object(sys, "argv", ["summarize_grouped_probe.py", "--output", str(output)]),
                patch.dict(sys.modules, {"PIL": pillow}),
                patch("subprocess.Popen", side_effect=AssertionError("No subprocess may start")) as popen,
                patch.object(summary.unittest.defaultTestLoader, "discover", side_effect=AssertionError("Source validation must reject first")) as discover,
            ):
                with self.assertRaisesRegex(AssertionError, "Canonical, prepared and manifest AXHP methods differ"):
                    summary.main()
            record = json.loads(output.read_text())
            self.assertFalse(record["passed"])
            self.assertNotEqual(record["date"], "old")
            self.assertIn("Canonical, prepared and manifest AXHP methods differ", record["failure"])
            popen.assert_not_called()
            discover.assert_not_called()

    def test_deleted_method_invalidates_old_success(self):
        self.check_changed_method(rename=False)

    def test_renamed_method_invalidates_old_success(self):
        self.check_changed_method(rename=True)


if __name__ == "__main__":
    unittest.main()
