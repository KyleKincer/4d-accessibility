#!/usr/bin/env python3
"""Create or remove a temporary release keychain without logging credentials."""
import base64
import os
from pathlib import Path
import secrets
import subprocess
import sys


def run(*args):
    subprocess.run(list(args), check=True, stdout=subprocess.DEVNULL)


def main():
    temporary = Path(os.environ["RUNNER_TEMP"])
    keychain = temporary / "accessibility-release.keychain-db"
    certificate = temporary / "accessibility-release.p12"
    if sys.argv[1:] == ["cleanup"]:
        if keychain.exists():
            run("security", "delete-keychain", str(keychain))
        certificate.unlink(missing_ok=True)
        return
    names = ["APPLE_DEVELOPER_ID_CERTIFICATE", "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD", "APPLE_SIGNING_IDENTITY", "APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_PASSWORD"]
    for name in names:
        if not os.environ.get(name):
            raise SystemExit(f"Missing release secret: {name}")
    if os.environ.get("PLUGIN_ID_REGISTERED") != "true":
        raise SystemExit("Register the native plugin ID and set PLUGIN_ID_REGISTERED=true before publishing")
    password = secrets.token_urlsafe(32)
    with certificate.open("wb") as out:
        os.chmod(certificate, 0o600)
        out.write(base64.b64decode(os.environ[names[0]], validate=True))
    run("security", "create-keychain", "-p", password, str(keychain))
    run("security", "set-keychain-settings", "-lut", "3600", str(keychain))
    run("security", "unlock-keychain", "-p", password, str(keychain))
    run("security", "import", str(certificate), "-P", os.environ[names[1]], "-k", str(keychain), "-T", "/usr/bin/codesign")
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain))
    run("xcrun", "notarytool", "store-credentials", "accessibility-release", "--keychain", str(keychain),
        "--apple-id", os.environ["APPLE_ID"], "--team-id", os.environ["APPLE_TEAM_ID"], "--password", os.environ["APPLE_APP_PASSWORD"])
    certificate.unlink()


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        # CalledProcessError's repr includes command arguments, which can contain secrets.
        raise SystemExit(f"Signing setup command failed with exit code {error.returncode}") from None
