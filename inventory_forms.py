#!/usr/bin/env python3
"""Inventory form definitions without opening a host application or reading runtime data.

Counts include print and legacy definitions. They do not establish active use,
runtime-generated objects, subform reachability, or accessibility coverage.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
COMPLEX_TYPES = {"plugin", "subform", "listbox", "webArea", "tab", "list", "view"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/form-inventory.json")
    parser.add_argument("--project-dir", type=Path, required=True, help="Directory containing Sources")
    args = parser.parse_args()
    if not (args.project_dir / "Sources").is_dir():
        parser.error("--project-dir must contain Sources")
    counts = Counter()
    plugins = Counter()
    listboxes = Counter()
    destinations = Counter()
    forms = []
    errors = []
    for path in sorted((args.project_dir / "Sources").rglob("form.4DForm")):
        relative = path.relative_to(args.project_dir).as_posix()
        try:
            raw = path.read_bytes()
            form = json.loads(raw)
            pages = form.get("pages") or []
            objects = []
            content_pages = 0
            destinations[form.get("destination", "unspecified")] += 1
            for page_number, page in enumerate(pages):
                if page is None:
                    continue
                if page_number > 0:
                    content_pages += 1
                for name, obj in (page.get("objects") or {}).items():
                    kind = obj.get("type", "unspecified")
                    counts[kind] += 1
                    if kind == "plugin":
                        plugins[obj.get("pluginAreaKind", "unspecified")] += 1
                    if kind == "listbox":
                        listboxes[obj.get("listboxType", "unspecified")] += 1
                    if kind in COMPLEX_TYPES:
                        objects.append({
                            "name": name, "type": kind, "page": page_number,
                            **{key: obj[key] for key in (
                                "pluginAreaKind", "listboxType", "detailForm", "listForm",
                                "table", "dataSource", "method", "events",
                            ) if key in obj},
                        })
            forms.append({
                "path": relative, "sha256": hashlib.sha256(raw).hexdigest(),
                "destination": form.get("destination", "unspecified"),
                "inheritedForm": form.get("inheritedForm"),
                "inheritedFormTable": form.get("inheritedFormTable"),
                "contentPages": content_pages, "complexObjects": objects,
            })
        except (OSError, ValueError, AttributeError, TypeError) as error:
            errors.append({"path": relative, "error": type(error).__name__})
    summary = {
        "formDefinitions": len(forms),
        "parseErrorCount": len(errors),
        "controlCounts": dict(sorted(counts.items())),
        "pluginKinds": dict(sorted(plugins.items())),
        "listboxSourceTypes": dict(sorted(listboxes.items())),
        "formDestinations": dict(sorted(destinations.items())),
        "multipleContentPageForms": sum(form["contentPages"] > 1 for form in forms),
    }
    report = {
        "scope": "Static definitions, including legacy and print forms; not runtime coverage",
        "summary": summary, "errors": errors, "forms": forms,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(summary, indent=2))
    print(f"Report: {args.output}")
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
