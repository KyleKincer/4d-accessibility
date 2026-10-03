"""Reject changed or missing acceptance inputs before publishing old success."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("outline_summary", ROOT / "summarize_native_outlines.py")
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class SourceGuard(unittest.TestCase):
    def test_changed_source_sets_invalidate_success(self):
        for change in ("delete", "rename", "add"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "src").mkdir(); (root / "tests").mkdir(); (root / "build").mkdir()
                inputs = ["src/Grid.mm", "tests/NativeOutlineFixture.mm", "test_native_outlines.py",
                          "tests/mac_ax.py", "tests/voiceover.py", "tests/ReadScreen.swift"]
                for name in inputs:
                    (root / name).write_text("synthetic input\n")
                expected = {name: summary.sha(root / name) for name in inputs}
                for mode, count in (("ax", 47), ("voiceover", 52)):
                    report = {"passed": True, "normalClose": True, "exitCode": 0, "sourceSHA256": expected,
                              "count": count, "checks": ["synthetic check"] * count, "finalState": {"runID": "owned", "pid": 7},
                              "runID": "owned", "pid": 7, "binarySHA256": "synthetic", "voiceover": []}
                    name = "native-outline.json" if mode == "ax" else "native-outline-voiceover.json"
                    (root / "build" / name).write_text(json.dumps(report))
                output = root / "summary.json"
                output.write_text(json.dumps({"passed": True}))
                source = root / "src/Grid.mm"
                if change == "delete":
                    source.unlink()
                elif change == "rename":
                    source.rename(root / "src/Renamed.mm")
                else:
                    (root / "src/New.mm").write_text("new production input\n")
                with self.assertRaises(AssertionError):
                    summary.publish(root, output)
                self.assertIs(json.loads(output.read_text())["passed"], False)


if __name__ == "__main__":
    unittest.main()
