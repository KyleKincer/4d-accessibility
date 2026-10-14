#!/usr/bin/env python3
"""Write a release's notes: which download to use, then that version's section of RELEASE-NOTES.md."""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/KyleKincer/4d-accessibility"

DOWNLOADS = """## Which download

| File | Contains | Use it to |
| --- | --- | --- |
| `4d-accessibility-{version}-macos.zip` | The native plugin, the compiled component, the host-method installer, the integration guides and the skill | Install the bridge in a 4D project on macOS. **Start here.** |
| `4d-accessibility-{version}-macos.dmg` | The same kit, as a notarized disk image | The same, from a disk image |
| `4d-accessibility.zip` | Only the compiled component | Let 4D's Dependency Manager fetch the component. You still need the plugin and host methods from the macOS kit. 4D requires this file name. |
| `SHA256SUMS` | Checksums of the other files | Verify a download |
| `signed-download-checks-{version}.json` | The checks run on these exact files before publication | Audit the release |

Install the plugin, the component and the host methods from the same kit.

**Windows:** the bridge runs only on macOS, so there is nothing to install on Windows. A project with lifecycle areas and host methods should still compile and run there: host methods reach the component only through `EXECUTE METHOD`, and an area without its plugin does nothing. On macOS, a form with the area compiles, starts normally, opens no other window and looks the same pixel for pixel, both without the plugin and without the plugin and component ([record]({repository}/blob/main/validation/missing-packages-development.json)). This has not been tested on Windows itself. The plugin bundle has no Windows code, so a kit copied to Windows should behave as in that check.

"""


def section(version):
    text = (ROOT / "RELEASE-NOTES.md").read_text()
    match = re.search(rf"^# {re.escape(version)}, .*?(?=^# |\Z)", text, re.M | re.S)
    if not match:
        raise SystemExit(f"RELEASE-NOTES.md has no section for {version}")
    return match.group(0).rstrip() + "\n"


def notes(version, tag):
    return (DOWNLOADS.format(version=version, tag=tag, repository=REPOSITORY) + section(version)
            + f"\nEarlier versions: [release notes]({REPOSITORY}/blob/{tag}/RELEASE-NOTES.md).\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, help="Release tag, such as v0.36.0")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    version = args.tag.removeprefix("v")
    if version != (ROOT / "VERSION").read_text().strip():
        raise SystemExit(f"{args.tag} does not match VERSION")
    args.output.write_text(notes(version, args.tag))


if __name__ == "__main__":
    main()
