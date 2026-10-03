#!/usr/bin/env python3
"""Protect application-owned source while refreshing generated host helpers."""
import subprocess
import json
import sys
import tempfile
import unittest
from pathlib import Path

from install_host_methods import AREA, AREA_NAME, BEGIN, END, ROOT, METADATA_NAME, area_form, main


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

    def test_list_metadata_is_packaged_without_changing_row_forms(self):
        self.form()
        row, value = self.form("Rows", table=True)
        value.update(destination="listScreen", markerHeader=28, markerBody=52)
        row.write_text(json.dumps(value))
        original = row.read_bytes()
        preview = self.run_installer("--form", "Customer", "--dry-run")
        resource = self.project.parent / "Resources" / METADATA_NAME
        self.assertIn("../Resources/" + METADATA_NAME, preview.stdout)
        self.assertFalse(resource.exists())
        self.run_installer("--form", "Customer")
        self.assertEqual(
            json.loads(resource.read_text())["forms"],
            {"1": {"Rows": {"header": 28, "body": 52}}},
        )
        self.assertEqual(row.read_bytes(), original)
        first = resource.read_bytes()
        self.run_installer()
        self.assertEqual(resource.read_bytes(), first)
        value["markerBody"] = 56
        row.write_text(json.dumps(value))
        self.run_installer()
        self.assertEqual(
            json.loads(resource.read_text())["forms"]["1"]["Rows"]["body"], 56
        )

    def test_current_project_directory_places_metadata_beside_project(self):
        self.form()
        row, value = self.form("Rows", table=True)
        value.update(markerHeader=0, markerBody=24)
        row.write_text(json.dumps(value))
        command = [sys.executable, str(ROOT / "install_host_methods.py"),
                   "--project-dir", ".", "--compiler-method", "Compiler_Application",
                   "--form", "Customer"]
        preview = subprocess.run([*command, "--dry-run"], cwd=self.project,
                                 capture_output=True, text=True)
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertIn("../Resources/" + METADATA_NAME, preview.stdout)
        result = subprocess.run(command, cwd=self.project, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.project.parent / "Resources" / METADATA_NAME).is_file())
        self.assertFalse((self.project / "Resources" / METADATA_NAME).exists())

    def test_bulk_preserves_referenced_rows_with_unspecified_destination(self):
        parent, value = self.form()
        row, _ = self.form("Rows", table=True)
        value["pages"][1]["objects"]["Items"] = {
            "type": "subform", "table": 1, "listForm": "Rows"}
        parent.write_text(json.dumps(value))
        before = row.read_bytes()
        preview = self.run_installer("--all-forms", "--dry-run")
        self.assertIn("Skipped list-row form: Sources/TableForms/1/Rows", preview.stdout)
        self.run_installer("--all-forms")
        self.assertEqual(row.read_bytes(), before)
        self.assertEqual(json.loads(parent.read_text())["pages"][0]["objects"][AREA_NAME], AREA)
        snapshot = self.snapshot()
        self.run_installer("--form", "TableForms/1/Rows", success=False)
        self.assertEqual(snapshot, self.snapshot())

    def test_shared_list_row_base_keeps_area_in_detail_branch(self):
        base, _ = self.form("Base")
        parent, value = self.form()
        value["inheritedForm"] = "Base"
        value["pages"][1]["objects"]["Items"] = {
            "type": "subform", "table": "Customers", "listForm": "Rows"}
        parent.write_text(json.dumps(value))
        row, value = self.form("Rows", table=True)
        value["inheritedForm"] = "Base"
        row.write_text(json.dumps(value))
        (self.project / "Sources/catalog.4DCatalog").write_text(
            '<base><table id="1" name="Customers"/></base>')
        before = {p: p.read_bytes() for p in (base, row)}
        self.run_installer("--all-forms")
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertEqual(json.loads(parent.read_text())["pages"][0]["objects"][AREA_NAME], AREA)
        snapshot = self.snapshot()
        self.run_installer("--all-forms")
        self.run_installer("--form", "Customer")
        self.assertEqual(snapshot, self.snapshot())

    def legacy_row_base(self):
        base, value = self.form("Base", page_zero={"objects": {AREA_NAME: AREA.copy()}})
        parent, value = self.form()
        value["inheritedForm"] = "Base"
        value["pages"][1]["objects"]["Items"] = {
            "type": "subform", "table": 1, "listForm": "Rows"}
        parent.write_text(json.dumps(value))
        row, value = self.form("Rows", table=True,
                               page_zero={"objects": {AREA_NAME: AREA.copy()}})
        value["inheritedForm"] = "Base"
        row.write_text(json.dumps(value))
        return base, parent, row

    def test_bulk_migrates_old_row_and_shared_base_areas(self):
        base, parent, row = self.legacy_row_base()
        original = {p: json.loads(p.read_text()) for p in (base, row)}
        preview = self.run_installer("--all-forms", "--dry-run")
        self.assertIn("Removed legacy list-row lifecycle", preview.stdout)
        for path in (base, row):
            self.assertEqual(json.loads(path.read_text()), original[path])
        self.run_installer("--all-forms")
        for path in (base, row):
            expected = original[path]
            del expected["pages"][0]["objects"][AREA_NAME]
            self.assertEqual(json.loads(path.read_text()), expected)
        self.assertEqual(json.loads(parent.read_text())["pages"][0]["objects"][AREA_NAME], AREA)
        snapshot = self.snapshot()
        self.run_installer("--all-forms")
        self.assertEqual(snapshot, self.snapshot())

    def test_named_install_requires_bulk_migration_of_old_row_areas(self):
        self.legacy_row_base()
        before = self.snapshot()
        result = self.run_installer("--form", "Customer", success=False)
        self.assertIn("--all-forms", result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_edited_legacy_row_area_blocks_bulk_before_any_writes(self):
        _, _, row = self.legacy_row_base()
        value = json.loads(row.read_text())
        value["pages"][0]["objects"][AREA_NAME]["left"] = 5
        row.write_text(json.dumps(value))
        before = self.snapshot()
        result = self.run_installer("--all-forms", success=False)
        self.assertIn("differs", result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_metadata_only_update_preserves_every_form(self):
        parent, value = self.form()
        row, value = self.form("Rows", table=True)
        value.update(destination="listScreen", markerHeader=0, markerBody=24)
        row.write_text(json.dumps(value))
        before = {p: p.read_bytes() for p in (parent, row)}
        self.run_installer("--form-metadata")
        resource = self.project.parent / "Resources" / METADATA_NAME
        self.assertTrue(resource.is_file())
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_list_parent_settings_follow_native_defaults_and_inheritance(self):
        parent, value = self.form()
        value["pages"][1]["objects"]["Items"] = {
            "type": "subform",
            "table": 1,
            "listForm": "Rows",
        }
        parent.write_text(json.dumps(value))
        inherited, child = self.form("Child")
        child["inheritedForm"] = "Customer"
        inherited.write_text(json.dumps(child))
        self.run_installer("--form", "Customer")
        resource = self.project.parent / "Resources" / METADATA_NAME
        forms = json.loads(resource.read_text())["forms"]["0"]
        expected = {"selection": "none", "enterable": False}
        self.assertEqual(forms["Customer"]["lists"]["Items"], expected)
        self.assertEqual(forms["Child"]["lists"]["Items"], expected)
        value["pages"][1]["objects"]["Items"].update(
            selectionMode="single", enterableInList=True
        )
        parent.write_text(json.dumps(value))
        self.run_installer()
        forms = json.loads(resource.read_text())["forms"]["0"]
        expected = {"selection": "single", "enterable": True}
        self.assertEqual(forms["Customer"]["lists"]["Items"], expected)
        self.assertEqual(forms["Child"]["lists"]["Items"], expected)

    def test_list_metadata_inherits_markers_and_omits_unknown_layouts(self):
        self.form()
        base, value = self.form("Base")
        value.update(markerHeader=30, markerBody=54)
        base.write_text(json.dumps(value))
        row, value = self.form("Rows", table=True)
        value.update(inheritedForm="Base", markerBody=58)
        row.write_text(json.dumps(value))
        for name, body in (("Unknown", None), ("Invalid", -1), ("Boolean", True)):
            path, value = self.form(name, table=True)
            value["markerBody"] = body
            path.write_text(json.dumps(value))
        self.run_installer("--form", "Customer")
        resource = self.project.parent / "Resources" / METADATA_NAME
        self.assertEqual(
            json.loads(resource.read_text())["forms"],
            {
                "0": {"Base": {"header": 30, "body": 54}},
                "1": {"Rows": {"header": 30, "body": 58}},
            },
        )

    def test_edited_list_metadata_blocks_all_writes(self):
        self.form()
        row, value = self.form("Rows", table=True)
        value.update(markerHeader=0, markerBody=24)
        row.write_text(json.dumps(value))
        self.run_installer("--form", "Customer")
        resource = self.project.parent / "Resources" / METADATA_NAME
        edited = json.loads(resource.read_text())
        edited["forms"]["1"]["Rows"]["body"] = 32
        resource.write_text(json.dumps(edited))
        before = self.snapshot()
        text = resource.read_bytes()
        self.run_installer(success=False)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(text, resource.read_bytes())



if __name__ == "__main__":
    unittest.main()
