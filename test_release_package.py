#!/usr/bin/env python3
"""Exercise the actual download: manifest integrity and isolated host installation."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

from package_release import signing_identity

ROOT = Path(__file__).resolve().parent


class ReleaseTests(unittest.TestCase):
    def test_signing_uses_exact_valid_identity_fingerprint(self):
        fingerprint = "A" * 40
        output = f'  1) {fingerprint} "Developer ID Application: Example (TEAM)"\n     1 valid identities found\n'
        with mock.patch("package_release.subprocess.run", return_value=mock.Mock(stdout=output)):
            self.assertEqual(signing_identity("/tmp/release.keychain-db", "Developer ID Application: Example (TEAM)"), fingerprint)
            with self.assertRaisesRegex(ValueError, "not valid"):
                signing_identity("/tmp/release.keychain-db", "Developer ID Application: Other (TEAM)")

    def test_complete_kit_installs_matching_helpers_without_business_files(self):
        version = (ROOT / "VERSION").read_text().strip()
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            kit = base / "kit"
            with zipfile.ZipFile(ROOT / f"dist/4d-accessibility-{version}-macos.zip") as archive:
                self.assertIsNone(archive.testzip())
                self.assertTrue(all(not p.startswith("/") and ".." not in Path(p).parts for p in archive.namelist()))
                archive.extractall(kit)
            manifest = json.loads((kit / "manifest.json").read_text())
            self.assertEqual(manifest["version"], version)
            actual = {str(p.relative_to(kit)): hashlib.sha256(p.read_bytes()).hexdigest() for p in kit.rglob("*") if p.is_file() and p != kit / "manifest.json"}
            self.assertEqual(manifest["files"], actual)
            self.assertTrue(all(not name.endswith((".license", ".p12", ".key", ".4dd")) for name in actual))
            self.assertFalse(any("ALP.bundle" in name or name.startswith("fixture/") for name in actual))
            for name in ["Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge", "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ", "skills/4d-accessibility/SKILL.md", "inspect_ax.py", "tests/mac_ax.py", "inventory_forms.py", "LICENSE", "4D-SDK-LICENSE.md", "validation/area-owned-integration.json", "validation/area-form.png", "tests/native-messages/README.md", "tests/native-messages/Project/NativeMessages.4DProject"]:
                self.assertIn(name, actual)
            for doc in [*kit.joinpath("skills").rglob("*.md"), *kit.joinpath("tests/native-messages").rglob("*.md")]:
                for link in re.findall(r"\]\(([^)]+)\)", doc.read_text()):
                    if re.match(r"\w+://", link) or link.startswith("mailto:"):
                        continue
                    target = link.partition("#")[0]
                    if target:
                        resolved = (doc.parent / target).resolve()
                        self.assertTrue(resolved.is_relative_to(kit.resolve()), f"Nonportable kit link: {doc.name} -> {link}")
                        self.assertTrue(resolved.exists(), f"Missing kit document: {doc.name} -> {link}")
            project = base / "host/Project"
            methods = project / "Sources/Methods"
            methods.mkdir(parents=True)
            owned = methods / "SaveRecord.4dm"
            owned.write_text("// Existing application behavior\n")
            form_path = project / "Sources/Forms/Customer/form.4DForm"
            form_path.parent.mkdir(parents=True)
            form = {"method": "SaveRecord", "events": ["onLoad", "onTimer"], "width": 300, "height": 100,
                    "pages": [None, {"objects": {"Save": {"type": "button", "text": "Save", "method": "SaveRecord", "events": ["onClick"], "left": 20, "top": 20, "width": 80, "height": 24}}}]}
            form_path.write_text(json.dumps(form))
            command = [sys.executable, str(kit / "install_host_methods.py"), "--project-dir", str(project), "--area-list", "--form", "Customer"]
            subprocess.run([*command, "--dry-run"], check=True, capture_output=True)
            self.assertEqual(json.loads(form_path.read_text()), form)
            subprocess.run(command, check=True, capture_output=True)
            first = {p.name: p.read_bytes() for p in methods.iterdir()}
            installed_form = form_path.read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(first, {p.name: p.read_bytes() for p in methods.iterdir()})
            self.assertEqual(form_path.read_bytes(), installed_form)
            integrated = json.loads(installed_form)
            self.assertEqual(integrated["pages"][0]["objects"]["__AXB_Bridge"]["pluginAreaKind"], "%AXB Area")
            integrated["pages"][0] = None
            self.assertEqual(integrated, form)
            self.assertEqual(owned.read_text(), "// Existing application behavior\n")
            self.assertEqual((methods / "AXB_Form.4dm").read_text().split("\n", 1)[1], (kit / "host/OptionalMethods/AXB_Form.4dm").read_text())

    def test_component_download_is_compiled_and_self_contained(self):
        from build_component import verify_package
        with tempfile.TemporaryDirectory() as temporary:
            with zipfile.ZipFile(ROOT / "dist/4d-accessibility.zip") as archive:
                self.assertTrue(all(p.startswith("AccessibilityBridge.4dbase/") for p in archive.namelist()))
                archive.extractall(temporary)
            package = Path(temporary) / "AccessibilityBridge.4dbase"
            self.assertTrue((package / "Resources/LICENSE").is_file())
            result = verify_package(package)
            self.assertTrue(result["targets"]["arm64_macOS_lib"])
            self.assertTrue(result["targets"]["x86_64_generic"])


if __name__ == "__main__":
    unittest.main()
