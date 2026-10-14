#!/usr/bin/env python3
"""Check source boundaries, local documentation links and skill portability."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# SHA-256 of lowercase names that must never appear in this public repository, in any file's
# name or text: internal names of the applications and organizations that use the bridge. Only
# hashes are kept, so the check does not publish the names it guards. Ask a maintainer to add one.
PRIVATE_NAMES = {
    "d19152a059b51f9956fe12ff4b066d864375fd185000afafdd4c394d23ec577e",
    "0c873ecbd3c57a0116ca9190d67c9d72bc0154efc4f81cca5d11c62181846184",
    "d22c5ede4878800bd3efaa7a5ea5fa8de9c0c9624e09f6a76b5b2c0735523244",
    "909a1f1a1a01819301b64ea45fb8fde02d643649fdeaee0b40eb187b61da21e7",
    "7ab1c6bf63924419cfdc0c59f09fc32bde8436968c69144ea207251aae2c4b15",
    "66b7acc0a2e11024a45bb3c97b3038509cba91d38234bf85975d76b899279a88",
    "3968e5dcbf86dbf65a4d007895026ac958463bff80665f2b5da823a8d39b3975",
    "11e7b491f571141ee4ee1293347159b827f61d904dea5a6ca35acb3473a50133",
}


def private_names(text):
    return {word for word in re.findall(r"[a-z0-9]+(?:[_-][a-z0-9]+)*", text.lower())
            if hashlib.sha256(word.encode()).hexdigest() in PRIVATE_NAMES}


def main():
    # Check repository source, including new work, rather than ignored local
    # fixture licenses, vendor bundles and build artifacts.
    names = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT, text=True).split("\0")
    files = [ROOT / name for name in names if name and ((ROOT / name).is_file() or (ROOT / name).is_symlink())]
    failures = []
    headings = {}
    for p in files:
        rel = p.relative_to(ROOT)
        if p.is_symlink():
            failures.append(f"Source symlink: {rel}")
        if p.suffix in {".license", ".p12", ".key", ".4dd", ".4DIndx", ".dylib"}:
            failures.append(f"Private or generated artifact in source: {rel}")
        if p.suffix == ".py":
            ast.parse(p.read_text(), filename=str(rel))
        content = p.read_bytes()
        if private_names(str(rel)) or (b"\0" not in content[:8000] and private_names(content.decode("utf-8", "replace"))):
            failures.append(f"Private name in public source: {rel}")
        if p.suffix == ".md":
            headings[p] = {re.sub(r"[^\w\- ]", "", line.lstrip("# ").strip().lower()).replace(" ", "-") for line in p.read_text().splitlines() if line.startswith("#")}
    for p in headings:
        for link in re.findall(r"\]\(([^)]+)\)", p.read_text()):
            if re.match(r"\w+://", link) or link.startswith("mailto:"):
                continue
            target, _, anchor = link.partition("#")
            resolved = (p.parent / target).resolve() if target else p
            if not resolved.is_relative_to(ROOT) or not resolved.exists():
                failures.append(f"Broken local link: {p.relative_to(ROOT)} -> {link}")
            elif anchor and resolved in headings and anchor not in headings[resolved]:
                failures.append(f"Missing heading: {p.relative_to(ROOT)} -> {link}")
    skill = ROOT / "skills/4d-accessibility/SKILL.md"
    if not skill.read_text().startswith("---\nname: 4d-accessibility\ndescription: "):
        failures.append("Skill metadata is missing")
    plugin_id = json.loads((ROOT / "manifest.json").read_text()).get("id")
    host = (ROOT / "host/OptionalMethods/AXB_Host.4dm").read_text()
    if not isinstance(plugin_id, int) or plugin_id <= 0 or f"Find in array($numbers; {plugin_id})" not in host:
        failures.append("Plugin manifest ID and optional host lookup differ")
    for failure in failures:
        print(failure)
    if failures:
        raise SystemExit(1)
    print(f"PASS: {len(files)} source files; local links, skill metadata and no private names")


if __name__ == "__main__":
    main()
