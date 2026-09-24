#!/usr/bin/env python3
"""Read a bounded AX tree from an explicitly selected application window.

This sends no actions or input. Labels and values can contain application data;
the report is written to a new mode-0600 file and is never printed to stdout.
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax


def inspect(window, max_nodes, max_children, row_start, include_values):
    queue = deque([(window, None, "window", 0)])
    seen = []
    nodes = []
    truncated = False
    while queue and len(nodes) < max_nodes:
        element, parent, relation, depth = queue.popleft()
        previous = next((i for i, other in enumerate(seen) if element.same_as(other)), None)
        if previous is not None:
            continue
        seen.append(element)
        index = len(nodes)
        fields = ["AXRole", "AXSubrole", "AXIdentifier", "AXTitle", "AXDescription", "AXEnabled", "AXFocused", "AXSelected", "AXPosition", "AXSize", "AXSortDirection"]
        node = {"index": index, "parent": parent, "relation": relation,
                "attributes": {name: element.read(name) for name in fields}, "actions": element.actions(), "counts": {}}
        if include_values and node["attributes"]["AXSubrole"] != "AXSecureTextField":
            value = element.read("AXValue")
            if isinstance(value, (str, int, float, bool)) or value is None:
                node["attributes"]["AXValue"] = value
        if str(node["attributes"].get("AXIdentifier") or "").startswith("axb.window."):
            node["attributes"]["AXHelp"] = element.read("AXHelp")
        nodes.append(node)
        if depth >= 24:
            node["depthLimitReached"] = True
            truncated = True
            continue
        relations = ["AXChildren"]
        if node["attributes"]["AXRole"] in {"AXTable", "AXOutline"}:
            relations += ["AXRows", "AXColumns", "AXVisibleRows"]
        for attribute in relations:
            try:
                count = element.count(attribute)
                node["counts"][attribute] = count
                start = row_start if attribute == "AXRows" else 0
                maximum = min(max_children, max_nodes - len(nodes), max(0, count - start))
                if count > maximum:
                    node.setdefault("sampled", {})[attribute] = {"start": start, "count": maximum}
                    truncated = True
                if maximum:
                    queue.extend((child, index, attribute, depth + 1) for child in element.slice(attribute, start, maximum) if isinstance(child, ax.Element))
            except RuntimeError as error:
                node.setdefault("readErrors", {})[attribute] = str(error)
        header = element.read("AXHeader")
        if isinstance(header, ax.Element):
            queue.append((header, index, "AXHeader", depth + 1))
    return {"nodes": nodes, "truncated": truncated or bool(queue), "nodeLimit": max_nodes,
            "childrenPerRelationLimit": max_children, "rowStart": row_start, "valuesIncluded": include_values,
            "scope": "Read-only AX sample, not a coverage audit or proof of action/VoiceOver behavior"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--window-title", required=True, help="Exact title; ambiguous matches are rejected")
    parser.add_argument("--output", type=Path, required=True, help="New private JSON file; existing paths are rejected")
    parser.add_argument("--max-nodes", type=int, default=500)
    parser.add_argument("--max-children", type=int, default=50)
    parser.add_argument("--row-start", type=int, default=0, help="Zero-based start of each table's logical AXRows sample")
    parser.add_argument("--include-values", action="store_true")
    args = parser.parse_args()
    if args.pid <= 0 or not 1 <= args.max_nodes <= 5000 or not 1 <= args.max_children <= 2000 or args.row_start < 0:
        parser.error("Use a positive PID, 1..5000 nodes, 1..2000 children and a nonnegative row start")
    if not ax.trusted():
        parser.error("The invoking application needs its normal macOS Accessibility permission")
    app = ax.application(args.pid)
    windows = app.slice("AXWindows", 0, min(app.count("AXWindows"), 100))
    matches = [window for window in windows if window.read("AXTitle") == args.window_title]
    if len(matches) != 1:
        parser.error("The selected process must have exactly one window with that title")
    # Reserve a new file before reading values; O_EXCL also rejects symlinks.
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        result = inspect(matches[0], args.max_nodes, args.max_children, args.row_start, args.include_values)
        result.update(pid=args.pid, windowTitle=args.window_title)
        json.dump(result, stream, indent=2)
        stream.write("\n")
    print(f"Read {len(result['nodes'])} nodes; truncated={result['truncated']}; report: {args.output}")


if __name__ == "__main__":
    main()
