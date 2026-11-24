#!/usr/bin/env python3
"""Headless native unit tests for FormCatalog (loose Project/Sources + .4DZ) and GenericForms suppression."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"

TEST_SRC = r'''
#import "FormCatalog.h"
#import "GenericForms.h"
#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>

static void Check(BOOL cond, const char *msg) {
    if (!cond) {
        fprintf(stderr, "FAIL: %s\n", msg);
        exit(1);
    }
    printf("PASS: %s\n", msg);
}

static NSDictionary *Parse(NSString *raw) {
    return [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static void VerifyDerived(NSDictionary *meta, const char *mode) {
    Check([meta[@"ok"] boolValue] && [meta[@"found"] boolValue], mode);
    Check([meta[@"destination"] isEqual:@"detailScreen"], "destination extracted");
    Check([meta[@"options"][@"automationKey"] isEqual:@"invoices.derived"] && [meta[@"options"][@"label"] isEqual:@"Derived Invoice"],
          "derived root options kept without inheriting base root options");
    Check([meta[@"controls"][@"BaseBtn"][@"label"] isEqual:@"Base action"], "inherited base control metadata via catalog table name");
    Check([meta[@"controls"][@"SubCont"][@"automationKey"] isEqual:@"sold_to"], "subform container automationKey preserved");
    Check([meta[@"controls"][@"LinesLB"][@"automationKey"] isEqual:@"lines_list"] && !meta[@"controls"][@"LinesLB"][@"grid"],
          "axb.grid split into grids while keeping automationKey in controls");
    Check([meta[@"grids"][@"LinesLB"][@"columns"][@"ColQty"][@"label"] isEqual:@"Quantity"] &&
          [meta[@"grids"][@"LinesLB"][@"columns"][@"ColQty"][@"automationKey"] isEqual:@"qty"],
          "column-level axb merged into grids[name].columns");
    Check([meta[@"lists"][@"ListSub"][@"selection"] isEqual:@"single"] && [meta[@"lists"][@"ListSub"][@"enterable"] isEqual:@YES],
          "inherited list subform metadata extracted");
    Check([meta[@"header"] isEqual:@24] && [meta[@"body"] isEqual:@48], "inherited markerHeader and markerBody extracted");
    Check([meta[@"hints"][@"FindBtn"][@"tooltip"] isEqual:@"Find matching records"] && [meta[@"hints"][@"FindBtn"][@"display"] isEqual:@NO],
          "tips.json tooltip resolved and invisible display flag preserved");
    Check([meta[@"hints"][@"RefTipBtn"][@"tooltip"] isEqual:@"Find matching records"],
          "$ref tips.json tooltip resolved");
    Check([meta[@"hints"][@"LinesLB"][@"selectedItemsSource"] isEqual:@"Form.selectedLines"],
          "listbox selectedItemsSource hint extracted and detokenized");
    Check([meta[@"hints"][@"TokFld"][@"dataSource"] isEqual:@"[Invoices]InvoiceDate"],
          "tokenized dataSource stripped of table/field token numbers");
}

int main(void) {
    @autoreleasepool {
        const char *archive = getenv("AXB_TEST_CATALOG_ARCHIVE");
        const char *loose = getenv("AXB_TEST_CATALOG_LOOSE");
        const char *looseForm = getenv("AXB_TEST_CATALOG_LOOSE_FORM");
        Check(archive && loose && looseForm, "test environment configured");

        // 1. Archive (.4DZ) mode
        AXBFormCatalogSetProjectForTesting(@(archive));
        VerifyDerived(Parse(AXBFormCatalogMetadataJSON(4, @"DerivedInvoice")), "FormCatalog reads table form from .4DZ archive");
        NSDictionary *missing = Parse(AXBFormCatalogMetadataJSON(4, @"NoSuchForm"));
        Check([missing[@"ok"] boolValue] && ![missing[@"found"] boolValue], ".4DZ reports found:false for missing form");
        AXBFormCatalogShutdown();

        // 2. Loose Project/Sources mode + live mtime reload
        AXBFormCatalogSetProjectForTesting(@(loose));
        VerifyDerived(Parse(AXBFormCatalogMetadataJSON(4, @"DerivedInvoice")), "FormCatalog reads table form from loose Project/Sources");

        // Mutate loose form and advance mtime to verify cache invalidation.
        NSString *formPath = @(looseForm);
        NSData *orig = [NSData dataWithContentsOfFile:formPath];
        NSMutableDictionary *mut = [[NSJSONSerialization JSONObjectWithData:orig options:NSJSONReadingMutableContainers error:nil] mutableCopy];
        mut[@"axb"] = @{@"label": @"Updated Live", @"automationKey": @"invoices.live"};
        NSData *updated = [NSJSONSerialization dataWithJSONObject:mut options:0 error:nil];
        [updated writeToFile:formPath atomically:YES];
        NSDate *future = [NSDate dateWithTimeIntervalSinceNow:5.0];
        [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: future} ofItemAtPath:formPath error:nil];
        NSDictionary *reloaded = Parse(AXBFormCatalogMetadataJSON(4, @"DerivedInvoice"));
        Check([reloaded[@"options"][@"label"] isEqual:@"Updated Live"] && [reloaded[@"options"][@"automationKey"] isEqual:@"invoices.live"],
              "loose form cache invalidates immediately when form.4DForm mtime changes");
        AXBFormCatalogShutdown();

        // 3. GenericForms suppression API
        AXBGenericFormsSetSuppressed(YES);
        Check(AXBGenericFormsIsSuppressed(), "GenericForms suppression toggles on");
        AXBGenericFormsSetSuppressed(NO);
        Check(!AXBGenericFormsIsSuppressed(), "GenericForms suppression toggles off");
    }
    return 0;
}
'''


def populate_forms(base_dir):
    sources = base_dir / "Project/Sources"
    (sources / "TableForms/4/BaseInvoice").mkdir(parents=True)
    (sources / "TableForms/4/DerivedInvoice").mkdir(parents=True)
    (sources / "catalog.4DCatalog").write_text('<?xml version="1.0" encoding="UTF-8"?><base><table name="Invoices" id="4"/></base>')
    (sources / "tips.json").write_text(json.dumps({"SearchTip": "Find matching records"}))
    base_form = {
        "markerHeader": 24, "markerBody": 48,
        "axb": {"label": "Base only", "automationKey": "base.only"},
        "pages": [None, {"objects": {
            "BaseBtn": {"type": "button", "axb": {"label": "Base action"}},
            "SubCont": {"type": "subform", "detailForm": "Child", "axb": {"automationKey": "sold_to"}},
            "ListSub": {"type": "subform", "listForm": "Rows", "selectionMode": "single", "enterableInList": True},
        }}],
    }
    derived_form = {
        "inheritedForm": "BaseInvoice", "inheritedFormTable": "Invoices",
        "destination": "detailScreen",
        "axb": {"label": "Derived Invoice", "automationKey": "invoices.derived"},
        "pages": [None, {"objects": {
            "FindBtn": {"type": "button", "display": False, "tooltip": ":/tips.json#/SearchTip", "axb": {"automationKey": "find_btn", "label": "Find"}},
            "RefTipBtn": {"type": "button", "tooltip": {"$ref": "/SOURCES/tips.json#/SearchTip"}},
            "LinesLB": {
                "type": "listbox", "listboxType": "collection", "selectedItemsSource": "Form:C1466.selectedLines",
                "axb": {"automationKey": "lines_list", "grid": {"kind": "collection", "label": "Lines"}},
                "columns": [{"name": "ColQty", "axb": {"label": "Quantity", "automationKey": "qty"}}],
            },
            "TokFld": {"type": "input", "dataSource": "[Invoices:4]InvoiceDate:2"},
        }}],
    }
    (sources / "TableForms/4/BaseInvoice/form.4DForm").write_text(json.dumps(base_form))
    derived_path = sources / "TableForms/4/DerivedInvoice/form.4DForm"
    derived_path.write_text(json.dumps(derived_form))
    (base_dir / "Project/TestApp.4DProject").write_text("{}\n")
    return base_dir / "Project/TestApp.4DProject", derived_path, base_form, derived_form


def main():
    BUILD.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="axb-catalog-test-") as tmp:
        tmp_path = Path(tmp).resolve()
        test_mm = tmp_path / "FormCatalogTests.mm"
        test_mm.write_text(TEST_SRC)
        binary = BUILD / "FormCatalogTests"
        subprocess.run([
            "clang++", "-std=c++17", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
            "-I", str(ROOT / "src"),
            str(test_mm),
            str(ROOT / "src/FormCatalog.mm"),
            str(ROOT / "src/GenericForms.mm"),
            str(ROOT / "src/Bridge.mm"),
            str(ROOT / "src/Session.mm"),
            str(ROOT / "src/Grid.mm"),
            str(ROOT / "src/GridNative.mm"),
            str(ROOT / "src/NativeLayout.mm"),
            str(ROOT / "src/DrawnText.mm"),
            str(ROOT / "src/InternalForms.mm"),
            str(ROOT / "src/InternalTable.mm"),
            str(ROOT / "src/MessageDialogs.mm"),
            str(ROOT / "src/ProgressWindows.mm"),
            str(ROOT / "src/QueryEditor.mm"),
            str(ROOT / "src/QuickReport.mm"),
            str(ROOT / "src/OrderByEditor.mm"),
            str(ROOT / "src/FormulaEditor.mm"),
            str(ROOT / "src/Activation.mm"),
            "-framework", "Cocoa", "-framework", "CoreText", "-framework", "QuartzCore", "-lz",
            "-o", str(binary),
        ], check=True)
        project, derived_path, base_form, derived_form = populate_forms(tmp_path / "loose")
        archive = tmp_path / "TestApp.4DZ"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("Project/Sources/catalog.4DCatalog", '<?xml version="1.0" encoding="UTF-8"?><base><table name="Invoices" id="4"/></base>')
            z.writestr("Project/Sources/tips.json", json.dumps({"SearchTip": "Find matching records"}))
            z.writestr(zipfile.ZipInfo("Project/Sources/TableForms/4/BaseInvoice/form.4DForm"), json.dumps(base_form), compress_type=zipfile.ZIP_DEFLATED)
            z.writestr(zipfile.ZipInfo("Project/Sources/TableForms/4/DerivedInvoice/form.4DForm"), "\ufeff" + json.dumps(derived_form), compress_type=zipfile.ZIP_DEFLATED)
        subprocess.run([str(binary)], check=True, env={
            **os.environ,
            "AXB_TEST_CATALOG_ARCHIVE": str(archive),
            "AXB_TEST_CATALOG_LOOSE": str(project),
            "AXB_TEST_CATALOG_LOOSE_FORM": str(derived_path),
        })


if __name__ == "__main__":
    main()
