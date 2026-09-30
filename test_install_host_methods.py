#!/usr/bin/env python3
"""Protect application-owned source while refreshing generated host helpers."""
import subprocess
import json
import sys
import tempfile
import unittest
from pathlib import Path

from install_host_methods import AREA, AREA_NAME, BEGIN, END, ROOT, area_form, main


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
        return {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}

    def form(self, name="Customer", *, table=False, page_zero=None):
        path = self.project / "Sources" / ("TableForms/1" if table else "Forms") / name / "form.4DForm"
        path.parent.mkdir(parents=True, exist_ok=True)
        value = {"width": 640, "height": 480, "method": "ExistingBusiness", "events": ["onLoad", "onUnload", "onTimer"],
                 "pages": [page_zero, {"objects": {"Name": {"type": "input", "dataSource": "Form.name", "left": 15, "top": 20, "width": 220, "height": 24}}}]}
        path.write_text(json.dumps(value, indent=2) + "\n")
        return path, value

    def test_area_preserves_layout_events_and_business_sources(self):
        path, original = self.form(page_zero={"objects": {"Caption": {"type": "text", "text": "Customer", "left": 20, "top": 5, "width": 200, "height": 20}}, "custom": "keep"})
        business = self.methods / "ExistingBusiness.4dm"
        business.write_text("// Existing initialization, timer and close behavior\n")
        self.run_installer("--form", "Customer")
        changed = json.loads(path.read_text())
        self.assertEqual(changed["pages"][0]["objects"].pop(AREA_NAME), AREA)
        self.assertEqual(changed, original)
        self.assertEqual(business.read_text(), "// Existing initialization, timer and close behavior\n")
        first = self.snapshot()
        self.run_installer("--form", "Customer")
        self.assertEqual(first, self.snapshot())

    def test_all_forms_includes_table_forms_and_page_zero(self):
        ordinary, _ = self.form()
        table, _ = self.form("Input", table=True)
        self.run_installer("--all-forms")
        for path in (ordinary, table):
            self.assertEqual(json.loads(path.read_text())["pages"][0]["objects"][AREA_NAME], AREA)

    def test_inherited_forms_install_once_in_the_shared_base(self):
        base, _ = self.form("Base")
        derived, value = self.form("Customer")
        value["inheritedForm"] = "Base"
        derived.write_text(json.dumps(value))
        second, second_value = self.form("Invoice")
        second_value["inheritedForm"] = "Customer"
        second.write_text(json.dumps(second_value))
        before = {p: p.read_bytes() for p in (derived, second)}
        preview = self.run_installer("--form", "Invoice", "--dry-run")
        self.assertIn("Shared lifecycle base: Sources/Forms/Base", preview.stdout)
        self.assertIn("Inherited by: Sources/Forms/Customer", preview.stdout)
        self.assertIn("Inherited by: Sources/Forms/Invoice", preview.stdout)
        self.run_installer("--form", "Invoice")
        self.assertEqual(json.loads(base.read_text())["pages"][0]["objects"][AREA_NAME], AREA)
        self.assertEqual(before, {p: p.read_bytes() for p in (derived, second)})
        first = self.snapshot()
        self.run_installer("--all-forms")
        self.assertEqual(first, self.snapshot())

    def test_shared_base_preview_reports_unselected_output_and_print_uses(self):
        self.form("Base")
        for name, destination in (("Editor", "detailScreen"), ("Listing", "listScreen"), ("Print", "detailPrinter")):
            path, value = self.form(name)
            value.update(inheritedForm="Base", destination=destination)
            path.write_text(json.dumps(value))
        before = self.snapshot()
        result = self.run_installer("--form", "Editor", "--dry-run")
        self.assertIn("Sources/Forms/Listing/form.4DForm [listScreen]", result.stdout)
        self.assertIn("Sources/Forms/Print/form.4DForm [detailPrinter]", result.stdout)
        self.assertEqual(before, self.snapshot())

    def test_table_inheritance_resolves_numbers_and_catalog_names(self):
        base, _ = self.form("Input", table=True)
        (self.project / "Sources/catalog.4DCatalog").write_text('<base><table id="1" name="Customers"/></base>')
        for table in (1, "Customers"):
            derived, value = self.form("Customer" + str(table))
            value.update(inheritedForm="Input", inheritedFormTable=table)
            derived.write_text(json.dumps(value))
        self.run_installer("--all-forms")
        self.assertEqual(json.loads(base.read_text())["pages"][0]["objects"][AREA_NAME], AREA)
        for path in (self.project / "Sources/Forms").glob("*/form.4DForm"):
            self.assertIsNone(json.loads(path.read_text())["pages"][0])

    def test_bulk_skips_output_and_print_forms_but_explicit_selection_rejects(self):
        for destination in ("listScreen", "detailPrinter", "listPrinter"):
            path, value = self.form(destination)
            value["destination"] = destination
            path.write_text(json.dumps(value))
        before = {p: p.read_bytes() for p in self.project.rglob("form.4DForm")}
        result = self.run_installer("--all-forms")
        self.assertEqual(result.stdout.count("Skipped non-detail form"), 3)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        snapshot = self.snapshot()
        self.run_installer("--form", "listScreen", success=False)
        self.assertEqual(snapshot, self.snapshot())

    def test_inheritance_errors_and_duplicate_areas_block_every_write(self):
        base, original = self.form("Base")
        derived, value = self.form("Customer")
        for inherited in ("Missing", "Customer", "../external.json", {"pages": [None, {}]}):
            value["inheritedForm"] = inherited
            derived.write_text(json.dumps(value))
            before = self.snapshot()
            self.run_installer("--all-forms", success=False)
            self.assertEqual(before, self.snapshot())
        value["inheritedForm"] = "Base"
        value["pages"][0] = {"objects": {AREA_NAME: AREA}}
        derived.write_text(json.dumps(value))
        before = self.snapshot()
        self.run_installer("--all-forms", success=False)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(json.loads(base.read_text()), original)

    def test_generated_configuration_key_is_idempotent_and_keeps_business_data(self):
        _, value = self.form()
        value["custom"] = {"name": "Business definition"}
        prepared = area_form(value, "Invoice-editor")
        self.assertEqual(prepared["pages"][0]["objects"], {AREA_NAME + ".Invoice-editor": AREA})
        self.assertEqual(area_form(prepared, "Invoice-editor"), prepared)
        self.assertIsNone(value["pages"][0])
        self.assertEqual(prepared["custom"], value["custom"])
        for key in ("Other", "contains space", "x" * 65):
            with self.assertRaises(ValueError):
                area_form(prepared, key)

    def test_dry_run_validates_everything_without_writes(self):
        self.form()
        before = self.snapshot()
        result = self.run_installer("--all-forms", "--dry-run")
        self.assertIn("Forms/Customer/form.4DForm", result.stdout)
        self.assertEqual(before, self.snapshot())

    def test_conflicting_or_edited_area_blocks_every_write(self):
        path, _ = self.form()
        self.run_installer("--all-forms")
        content = json.loads(path.read_text())
        content["pages"][0]["objects"][AREA_NAME]["width"] = 20
        path.write_text(json.dumps(content))
        before = self.snapshot()
        self.run_installer("--all-forms", success=False)
        self.assertEqual(before, self.snapshot())

    def test_method_only_refresh_never_reads_forms(self):
        path, _ = self.form()
        path.write_text("{not json")
        self.run_installer()
        self.assertEqual(path.read_text(), "{not json")
        self.assertTrue((self.methods / "AXB_Area.4dm").exists())
        before = self.snapshot()
        self.run_installer("--all-forms", success=False)
        self.assertEqual(before, self.snapshot())

    def test_unknown_and_invalid_form_block_every_write(self):
        path, _ = self.form()
        for option in ("Missing", "Customer"):
            if option == "Customer":
                path.write_text('{"pages": "invalid"}')
            before = self.snapshot()
            self.run_installer("--form", option, success=False)
            self.assertEqual(before, self.snapshot())

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

    def test_instrumentation_failure_blocks_every_write(self):
        self.run_installer()
        before = self.snapshot()
        visited = []
        def instrument(body, name):
            visited.append(name)
            if len(visited) == 3:
                raise ValueError("Application instrumentation failed")
            return body + "// instrumentation\n"
        with self.assertRaisesRegex(ValueError, "instrumentation failed"):
            main(["--project-dir", str(self.project), "--compiler-method", "Compiler_Application"],
                 transform=instrument)
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
