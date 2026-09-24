#!/usr/bin/env python3
"""Check source boundaries, local documentation links and skill portability."""
import ast
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    files = [p for p in ROOT.rglob("*") if p.is_file() and not any(part in {".git", "build", "dist", "__pycache__", ".venv", ".ruff_cache"} for part in p.relative_to(ROOT).parts)]
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
    for failure in failures:
        print(failure)
    if failures:
        raise SystemExit(1)
    print(f"PASS: {len(files)} source files; local links and skill metadata")


if __name__ == "__main__":
    main()
