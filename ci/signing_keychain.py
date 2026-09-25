#!/usr/bin/env python3
"""Create or remove a temporary release keychain without logging credentials."""
import base64
import hashlib
import os
from pathlib import Path
import secrets
import subprocess
import sys


APPLE_DEVELOPER_ID_G1 = Path(__file__).with_name("DeveloperIDCA.cer")
APPLE_DEVELOPER_ID_G1_SHA256 = "7afc9d01a62f03a2de9637936d4afe68090d2de18d03f29c88cfb0b1ba63587f"


def run(*args):
    subprocess.run(list(args), check=True, stdout=subprocess.DEVNULL)


def identity_available(keychain, name):
    result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)],
                            check=True, capture_output=True, text=True)
    return name in result.stdout


def main():
    temporary = Path(os.environ["RUNNER_TEMP"])
    keychain = temporary / "accessibility-release.keychain-db"
    certificate = temporary / "accessibility-release.p12"
    notary_key = temporary / "accessibility-notary-key.p8"
    if sys.argv[1:] == ["cleanup"]:
        if keychain.exists():
            run("security", "delete-keychain", str(keychain))
        certificate.unlink(missing_ok=True)
        notary_key.unlink(missing_ok=True)
        return
    names = ["APPLE_DEVELOPER_ID_CERTIFICATE", "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD", "APPLE_SIGNING_IDENTITY"]
    for name in names:
        if not os.environ.get(name):
            raise SystemExit(f"Missing release secret: {name}")
    api_names = ["APPLE_NOTARY_API_KEY_BASE64", "APPLE_NOTARY_KEY_ID", "APPLE_NOTARY_ISSUER_ID"]
    password_names = ["APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_PASSWORD"]
    notarization = api_names if any(os.environ.get(name) for name in api_names) else password_names
    for name in notarization:
        if not os.environ.get(name):
            raise SystemExit(f"Missing release secret: {name}")
    password = secrets.token_urlsafe(32)
    with certificate.open("wb") as out:
        os.chmod(certificate, 0o600)
        out.write(base64.b64decode(os.environ[names[0]], validate=True))
    run("security", "create-keychain", "-p", password, str(keychain))
    run("security", "set-keychain-settings", "-lut", "3600", str(keychain))
    run("security", "list-keychains", "-d", "user", "-s", str(keychain))
    run("security", "default-keychain", "-d", "user", "-s", str(keychain))
    run("security", "unlock-keychain", "-p", password, str(keychain))
    if hashlib.sha256(APPLE_DEVELOPER_ID_G1.read_bytes()).hexdigest() != APPLE_DEVELOPER_ID_G1_SHA256:
        raise SystemExit("Apple Developer ID intermediate certificate hash mismatch")
    run("security", "import", str(APPLE_DEVELOPER_ID_G1), "-k", str(keychain))
    run("security", "import", str(certificate), "-P", os.environ[names[1]], "-k", str(keychain), "-T", "/usr/bin/codesign")
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain))
    if not identity_available(keychain, os.environ[names[2]]):
        raise SystemExit("Imported Developer ID identity is unavailable for code signing")
    if notarization == api_names:
        with notary_key.open("wb") as out:
            os.chmod(notary_key, 0o600)
            out.write(base64.b64decode(os.environ[api_names[0]], validate=True))
        run("xcrun", "notarytool", "store-credentials", "accessibility-release", "--keychain", str(keychain),
            "--key", str(notary_key), "--key-id", os.environ[api_names[1]], "--issuer", os.environ[api_names[2]])
    else:
        run("xcrun", "notarytool", "store-credentials", "accessibility-release", "--keychain", str(keychain),
            "--apple-id", os.environ["APPLE_ID"], "--team-id", os.environ["APPLE_TEAM_ID"], "--password", os.environ["APPLE_APP_PASSWORD"])
    certificate.unlink()
    notary_key.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        # CalledProcessError's repr includes command arguments, which can contain secrets.
        raise SystemExit(f"Signing setup command failed with exit code {error.returncode}") from None
