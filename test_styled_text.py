#!/usr/bin/env python3
"""Test styled-text reading with real 4D commands, without a desktop window."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_component import BUILD, ROOT, literal, project_at, run_utility, sha


CASES = [
    ("style spans", 'Hello <span style="font-weight:bold">world</span>', "Hello world", False),
    ("Unicode", '<span style="font-style:italic">Zoë 🎸 &amp; 🎹</span>', "Zoë 🎸 & 🎹", False),
    ("plain text", "ordinary text", "ordinary text", False),
    ("empty", "", "", False),
    ("link label", '<span>Read <a href="https://example.com/">the help</a></span>', "Read the help", True),
]

REFERENCE_ENCODINGS = [
    ("original", "-d4-ref"),
    ("uppercase", "-D4-REF"),
    ("decimal hyphen", "&#45;d4-ref"),
    ("hexadecimal hyphen", "&#x2d;d4-ref"),
    ("decimal identifier", "".join(f"&#{ord(char)};" for char in "-d4-ref")),
    ("hexadecimal identifier", "".join(f"&#x{ord(char):x};" for char in "-d4-ref")),
    ("padded uppercase identifier", "".join(f"&#x00{ord(char):X};" for char in "-D4-REF")),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    compiler = parser.add_mutually_exclusive_group(required=True)
    compiler.add_argument("--server", type=Path)
    compiler.add_argument("--tool4d", type=Path)
    args = parser.parse_args()
    for process in ("4D", "4D Server"):
        if subprocess.run(["pgrep", "-x", process], capture_output=True).returncode == 0:
            parser.error("Close 4D before this sequential utility test")
    app = (args.server or args.tool4d).expanduser().resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != ("com.4D.4DServer" if args.server else "com.4D.tool"):
        parser.error("The application does not match --server/--tool4d")
    helper = ROOT / "host/OptionalMethods/AXB_StyledText.4dm"
    cases = [{"label": label, "raw": raw, "expected": expected, "references": refs}
             for label, raw, expected, refs in CASES]
    BUILD.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="styled-text-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        shutil.copy2(helper, driver / "Project/Sources/Methods/AXB_StyledText.4dm")
        (driver / "Project/Sources/Methods/AXBT_StyledExpression.4dm").write_text(
            '#DECLARE() -> $text : Text\nAXBT_StyledExpressionCalls:=AXBT_StyledExpressionCalls+1\n$text:="Rendered value"\n')
        body = '''$result:=New object("cases"; New collection; "compiled"; Is compiled mode)
var $case; $read : Object
var $raw; $before; $expression : Text
var $calls : Integer
AXBT_StyledExpressionCalls:=0
For each ($case; JSON Parse(''' + literal(json.dumps(cases, ensure_ascii=False)) + '''))
 $raw:=$case.raw
 OK:=0
 $read:=AXB_StyledText($raw)
 $read.okPreserved:=OK=0
 $read.sourcePreserved:=$raw=$case.raw
 $read.label:=$case.label
 $result.cases.push($read)
End for each
$raw:=""
ST INSERT EXPRESSION($raw; "AXBT_StyledExpression"; ST Start text; ST End text)
$expression:=$raw
$result.expressions:=New collection
For each ($case; JSON Parse(''' + literal(json.dumps([{"label": name, "marker": marker} for name, marker in REFERENCE_ENCODINGS])) + '''))
 $raw:=Replace string($expression; "-d4-ref"; $case.marker)
 $before:=$raw
 $calls:=AXBT_StyledExpressionCalls
 OK:=0
 $read:=AXB_StyledText($raw)
 $result.expressions.push(New object("label"; $case.label; "read"; $read; "sourcePreserved"; $raw=$before; "okPreserved"; OK=0; "callsBefore"; $calls; "callsAfter"; AXBT_StyledExpressionCalls))
End for each'''
        result = run_utility(app / "Contents/MacOS" / info["CFBundleExecutable"], driver, body, 90)
    checks = []
    checks.append({"name": "all plain cases returned", "passed": len(result.get("cases", [])) == len(cases)})
    for expected, actual in zip(cases, result.get("cases", [])):
        for name, passed in (
            ("valid text", actual.get("ok") is True),
            ("visible text", actual.get("text") == expected["expected"]),
            ("reference classification", actual.get("references") is expected["references"]),
            ("original text preserved", actual.get("sourcePreserved") is True),
            ("application OK preserved", actual.get("okPreserved") is True),
        ):
            checks.append({"name": expected["label"] + ": " + name, "passed": passed})
    expressions = result.get("expressions", [])
    checks.append({"name": "all reference cases returned", "passed": len(expressions) == len(REFERENCE_ENCODINGS)})
    for expression in expressions:
        read = expression.get("read", {})
        for name, passed in (
            ("classified as a reference", read.get("ok") is True and read.get("references") is True),
            ("original source preserved", expression.get("sourcePreserved") is True),
            ("original rendered value required", read.get("requiresRenderedValue") is True and read.get("text") == ""),
            ("inspection does not evaluate the expression", expression.get("callsAfter") == expression.get("callsBefore")),
            ("application OK preserved", expression.get("okPreserved") is True),
        ):
            checks.append({"name": expression["label"] + ": " + name, "passed": passed})
    passed = all(check["passed"] for check in checks)
    report = {"passed": passed, "checks": checks, "result": result,
              "helper_sha256": sha(helper), "scope": "Headless text commands; no desktop editing or VoiceOver claim"}
    (BUILD / "styled-text-commands.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: {len(checks)} styled-text command checks")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
