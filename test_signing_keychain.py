#!/usr/bin/env python3
"""Check temporary signing material and both notarization credential paths."""
import base64
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from ci import signing_keychain


class SigningKeychainTests(unittest.TestCase):
    def setup(self, directory):
        return {
            "RUNNER_TEMP": str(directory),
            "APPLE_DEVELOPER_ID_CERTIFICATE": base64.b64encode(b"certificate").decode(),
            "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD": "certificate-password",
            "APPLE_SIGNING_IDENTITY": "Developer ID Application: Example",
        }

    def execute(self, environment):
        calls = []
        with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(signing_keychain, "run", side_effect=lambda *args: calls.append(args)), mock.patch.object(signing_keychain, "identity_available", return_value=True), mock.patch("sys.argv", ["signing_keychain.py"]):
            signing_keychain.main()
        return calls

    def test_api_key_path_removes_temporary_material(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            environment = self.setup(directory) | {
                "APPLE_NOTARY_API_KEY_BASE64": base64.b64encode(b"notary-key").decode(),
                "APPLE_NOTARY_KEY_ID": "KEYID",
                "APPLE_NOTARY_ISSUER_ID": "ISSUER",
            }
            calls = self.execute(environment)
            imports = [call for call in calls if call[:2] == ("security", "import")]
            self.assertEqual(imports[0][2], str(signing_keychain.APPLE_DEVELOPER_ID_G1))
            self.assertEqual(imports[1][2], str(directory / "accessibility-release.p12"))
            notary = next(call for call in calls if call[:3] == ("xcrun", "notarytool", "store-credentials"))
            self.assertIn("--key-id", notary)
            self.assertIn("--issuer", notary)
            self.assertNotIn("--apple-id", notary)
            self.assertFalse((directory / "accessibility-release.p12").exists())
            self.assertFalse((directory / "accessibility-notary-key.p8").exists())

    def test_password_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            environment = self.setup(Path(temp)) | {"APPLE_ID": "example@example.com", "APPLE_TEAM_ID": "TEAM", "APPLE_APP_PASSWORD": "app-password"}
            calls = self.execute(environment)
            notary = next(call for call in calls if call[:3] == ("xcrun", "notarytool", "store-credentials"))
            self.assertIn("--apple-id", notary)
            self.assertNotIn("--key", notary)

    def test_partial_api_key_rejects_before_import(self):
        with tempfile.TemporaryDirectory() as temp:
            environment = self.setup(Path(temp)) | {"APPLE_NOTARY_KEY_ID": "KEYID"}
            with self.assertRaisesRegex(SystemExit, "APPLE_NOTARY_API_KEY_BASE64"):
                self.execute(environment)


if __name__ == "__main__":
    unittest.main()
