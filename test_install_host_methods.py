#!/usr/bin/env python3
"""Protect application-owned source while refreshing generated host helpers."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from install_host_methods import BEGIN, END, ROOT


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "Project"
        self.methods = self.project / "Sources/Methods"
        self.methods.mkdir(parents=True)
        self.compiler = self.methods / "Compiler_Application.4dm"
        self.compiler.write_text("// Application declarations\nC_TEXT(ExistingAction; $1)\n")

    def run_installer(self, *options, success=True):
        result = subprocess.run([sys.executable, str(ROOT / "install_host_methods.py"),
                                 "--project-dir", str(self.project), "--compiler-method",
                                 "Compiler_Application", *options], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.methods.iterdir()}

    def test_refresh_preserves_application_declarations_and_is_idempotent(self):
        self.run_installer("--area-list")
        first = self.snapshot()
        self.run_installer("--area-list")
        self.assertEqual(first, self.snapshot())
        source = self.compiler.read_text()
        self.assertIn("C_TEXT(ExistingAction; $1)", source)
        self.assertEqual(source.count(BEGIN), 1)
        self.assertEqual(source.count(END), 1)
        self.assertIn("C_OBJECT(AXB_PollGuard)", source)
        self.assertIn("C_OBJECT(AXB_ALPRowsSelect;", source)
        error = (self.methods / "AXB_FormError.4dm").read_text()
        self.assertTrue(error.endswith("ABORT\n"))


    def test_edited_generated_source_blocks_every_write(self):
        self.run_installer()
        target = self.methods / "AXB_View.4dm"
        target.write_text(target.read_text() + "// Host's change\n")
        before = self.snapshot()
        result = self.run_installer(success=False)
        self.assertIn("edited method", result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_existing_application_method_blocks_every_write(self):
        (self.methods / "AXB_View.4dm").write_text("// Application-owned method\n")
        before = self.snapshot()
        self.run_installer(success=False)
        self.assertEqual(before, self.snapshot())

    def test_removing_area_list_option_cannot_leave_untyped_helpers(self):
        self.run_installer("--area-list")
        before = self.snapshot()
        result = self.run_installer(success=False)
        self.assertIn("orphaned", result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_ambiguous_compiler_section_blocks_every_write(self):
        self.compiler.write_text(BEGIN + "\n" + BEGIN + "\n" + END)
        before = self.snapshot()
        self.run_installer(success=False)
        self.assertEqual(before, self.snapshot())

    def test_changed_compiler_target_blocks_every_write(self):
        self.run_installer("--area-list")
        before = self.snapshot()
        result = self.run_installer("--area-list", "--compiler-method", "Compiler_Another", success=False)
        self.assertIn("Compiler_Application", result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_other_methods_with_partial_declaration_blocks_block_every_write(self):
        for marker in (BEGIN, END):
            with self.subTest(marker=marker):
                target = self.methods / "ApplicationDeclarations.4dm"
                target.write_text(marker + "\n")
                before = self.snapshot()
                result = self.run_installer(success=False)
                self.assertIn("ApplicationDeclarations", result.stderr)
                self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main()
