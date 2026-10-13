#!/usr/bin/env python3
"""Measure what the bridge costs an application that does not use assistive technology.

Builds one compiled project per variant and runs the same script in each:

- none: no plugin, no component and no lifecycle area;
- plugin: the plugin and component installed, forms without a lifecycle area;
- area: the plugin, the component and a lifecycle area in every form, as the installer adds it.

The project opens a small dialog five times and a large form three times, timing each until 4D
first runs its timer. It then leaves the large form idle with a one-second timer, for its CPU
time; idle with a one-tick timer; and scrolling its list box each tick. The one-tick timer
records how long the form's process waited between ticks: work on that process, such as the
bridge's polling, delays the next tick and so the user's next event. CPU time and memory are
read from outside.

With --wake, an accessibility client reads the whole window before the idle and scroll phases,
as VoiceOver would when it enters the window.
"""

import argparse
import json
from pathlib import Path
import plistlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import uuid

from build_component import BUILD, PACKAGE, ROOT, literal, project_at, run_utility, sha, verify_package
from install_host_methods import main as install

sys.path.insert(0, str(ROOT / "tests"))
import mac_ax as ax
from fixture_desktop import wait_for_start

APPLICATION = Path("/Applications/4D/4D.app/Contents/MacOS/4D")
ROWS = 2000

STARTUP = """var $data; $results : Object
var $i; $window; $started : Integer
var $phase : Text
ON ERR CALL("CostError")
CostMark("started")
$results:=New object("compiled"; Is compiled mode; "opens"; New collection; "phases"; New object)
For ($i; 1; 5)
 $data:=New object("duration"; 500; "phase"; "")
 $started:=Milliseconds
 $window:=Open form window("Small"; Plain form window)
 DIALOG("Small"; $data)
 CLOSE WINDOW($window)
 $results.opens.push(New object("form"; "Small"; "shown"; $data.shown-$started; "loaded"; $data.loaded-$started; "closed"; Milliseconds-$started-$data.duration))
End for
For ($i; 1; 3)
 $data:=CostData(500; "")
 $started:=Milliseconds
 $window:=Open form window("Large"; Plain form window)
 DIALOG("Large"; $data)
 CLOSE WINDOW($window)
 $results.opens.push(New object("form"; "Large"; "shown"; $data.shown-$started; "loaded"; $data.loaded-$started; "closed"; Milliseconds-$started-$data.duration))
End for
For each ($phase; New collection("quiet"; "idle"; "scroll"))
 $data:=CostData(Num(File("/RESOURCES/duration.txt").getText()); $phase)
 $window:=Open form window("Large"; Plain form window)
 DIALOG("Large"; $data)
 CLOSE WINDOW($window)
 $results.phases[$phase]:=New object("gaps"; $data.gaps; "ticks"; $data.gaps.length)
End for each
File("/RESOURCES/results.json").setText(JSON Stringify($results))
CostMark("done")
QUIT 4D
"""

DATA = """#DECLARE($duration : Integer; $phase : Text) -> $data : Object
var $i : Integer
$data:=New object("duration"; $duration; "phase"; $phase; "rows"; New collection; "note"; "Readable note text.")
For ($i; 1; """ + str(ROWS) + """)
 $data.rows.push(New object("name"; "Row "+String($i); "amount"; String($i*3); "state"; Choose($i%2=0; "Open"; "Closed")))
End for
"""

FORM_METHOD = """var $now : Integer
Case of
 : (Form event code=On Load)
  Form.loaded:=Milliseconds
  Form.gaps:=New collection
  Form.row:=1
  SET TIMER(Choose(Form.phase="quiet"; 60; 1))
 : (Form event code=On Timer)
  $now:=Milliseconds
  If (Form.shown=Null)
   Form.shown:=$now
   If (Form.phase#"")
    CostMark(Form.phase)
    // The runner may read the window with an accessibility client first.
    While (Not(File("/RESOURCES/go-"+Form.phase+".txt").exists))
     DELAY PROCESS(Current process; 2)
    End while
    Form.shown:=Milliseconds
    $now:=Form.shown
   End if
  Else
   Form.gaps.push($now-Form.last)
  End if
  Form.last:=$now
  If (Form.phase="scroll")
   Form.row:=Choose(Form.row>(""" + str(ROWS) + """-40); 1; Form.row+20)
   OBJECT SET SCROLL POSITION(*; "Rows"; Form.row; *)
  End if
  If (($now-Form.shown)>=Form.duration)
   If (Form.phase#"")
    CostMark(Form.phase+"-done")
   End if
   CANCEL
  End if
End case
"""


def form(objects, width, height):
    return {"windowTitle": "AXB cost", "width": width, "height": height, "method": "CostForm",
            "events": ["onLoad", "onTimer"], "pages": [None, {"objects": objects}]}


def small_form():
    objects = {
        "NameLabel": {"type": "text", "text": "Name", "left": 20, "top": 20, "width": 80, "height": 17},
        "Name": {"type": "input", "dataSource": "Form.name", "left": 110, "top": 18, "width": 200, "height": 20},
        "Active": {"type": "checkbox", "text": "Active", "dataSource": "Form.active", "left": 110, "top": 50, "width": 120, "height": 20},
        "Cancel": {"type": "button", "text": "Cancel", "action": "cancel", "left": 130, "top": 90, "width": 90, "height": 28},
        "OK": {"type": "button", "text": "OK", "action": "accept", "left": 230, "top": 90, "width": 90, "height": 28},
    }
    return form(objects, 340, 130)


def large_form():
    objects = {}
    for index in range(600):
        objects[f"Item{index:03}"] = {"type": "button", "text": str(index), "left": 10 + (index % 20) * 43,
                                      "top": 10 + (index // 20) * 20, "width": 40, "height": 18, "fontSize": 9}
    objects["Note"] = {"type": "input", "dataSource": "Form.note", "left": 10, "top": 620, "width": 400, "height": 20}
    objects["Rows"] = {
        "type": "listbox", "listboxType": "collection", "dataSource": "Form.rows", "left": 10, "top": 650,
        "width": 860, "height": 300, "scrollbarVertical": "visible",
        "columns": [{"name": c, "dataSource": "This." + c, "width": 280, "header": {"name": c + "Header", "text": c.title()}}
                    for c in ("name", "amount", "state")],
    }
    objects["Close"] = {"type": "button", "text": "Close", "action": "cancel", "left": 770, "top": 960, "width": 100, "height": 28}
    return form(objects, 885, 1000)


def prepare(server, variant, duration):
    fixture = BUILD / f"cost-{variant}"
    if fixture.exists():
        fixture.rename(BUILD / (f"cost-{variant}-previous-" + uuid.uuid4().hex))
    project = project_at(fixture, "Cost")
    sources = fixture / "Project/Sources"
    methods = sources / "Methods"
    (fixture / "Plugins").mkdir()
    (fixture / "Components").mkdir()
    if variant != "none":
        shutil.copytree(PACKAGE, fixture / "Components/AccessibilityBridge.4dbase")
        shutil.copytree(BUILD / "AccessibilityBridge.bundle", fixture / "Plugins/AccessibilityBridge.bundle")
    (sources / "DatabaseMethods").mkdir()
    (sources / "DatabaseMethods/onStartup.4dm").write_text(STARTUP)
    (methods / "CostData.4dm").write_text(DATA)
    (methods / "CostForm.4dm").write_text(FORM_METHOD)
    (methods / "CostMark.4dm").write_text('#DECLARE($phase : Text)\nFile("/RESOURCES/mark.json").setText(JSON Stringify(New object("phase"; $phase; "at"; Milliseconds)))\n')
    (methods / "CostError.4dm").write_text('File("/RESOURCES/error.json").setText(JSON Stringify(New object("error"; Error; "method"; Error method; "line"; Error line)))\nQUIT 4D\nABORT\n')
    (methods / "Compiler_Cost.4dm").write_text("C_LONGINT(CostData; $1)\nC_TEXT(CostData; $2)\nC_OBJECT(CostData; $0)\nC_TEXT(CostMark; $1)\n")
    for name, definition in (("Small", small_form()), ("Large", large_form())):
        (sources / "Forms" / name).mkdir(parents=True)
        (sources / "Forms" / name / "form.4DForm").write_text(json.dumps(definition, indent=2) + "\n")
    if variant != "none":
        install(["--project-dir", str(project.parent), *(["--all-forms"] if variant == "area" else [])])
    (fixture / "Resources").mkdir(exist_ok=True)
    (fixture / "Resources/duration.txt").write_text(str(duration))
    info = plistlib.loads((server / "Contents/Info.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="cost-compile-", dir=BUILD) as temporary:
        driver = Path(temporary)
        project_at(driver, "Driver")
        result = run_utility(server / "Contents/MacOS" / info["CFBundleExecutable"], driver,
            '$options:=New object("targets"; New collection("arm64_macOS_lib"; "x86_64_generic"); "typeInference"; "none")\n'
            f'$options.plugins:=Folder({literal(fixture / "Plugins")})\n' +
            ('$options.components:=New collection\n' if variant == "none" else
             f'$options.components:=New collection(File({literal(fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")}))\n') +
            f'$result:=Compile project(File({literal(project)}); $options)', 120)
    if not (result.get("success") is True and not result.get("errors")):
        print(json.dumps(result, indent=2))
        raise SystemExit(f"FAIL: {variant} compilation")
    return fixture, project


def cpu_seconds(pid):
    value = subprocess.check_output(["ps", "-o", "time=", "-p", str(pid)], text=True).strip()
    minutes, seconds = value.split(":")
    return int(minutes) * 60 + float(seconds)


def rss_megabytes(pid):
    return int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)], text=True).strip()) / 1024


def read_tree(element, depth=0, limit=5000):
    """Read every element as an assistive client would: role, title, value and children."""
    count = 1
    for name in ("AXRole", "AXTitle", "AXDescription", "AXValue"):
        element.read(name)
    for child in (element.read("AXChildren") or []) if depth < 40 else []:
        count += read_tree(child, depth + 1, limit)
        if count >= limit:
            break
    return count


def gap_summary(gaps):
    ordered = sorted(gaps)
    return {
        "ticks": len(gaps),
        "medianMs": statistics.median(ordered),
        "p99Ms": ordered[min(len(ordered) - 1, int(len(ordered) * 0.99))],
        "maxMs": ordered[-1],
        "over50Ms": sum(1 for g in gaps if g > 50),
        "over100Ms": sum(1 for g in gaps if g > 100),
    }


def run(fixture, project, variant, wake, intel):
    resources = fixture / "Resources"
    for name in ("mark.json", "results.json", "error.json", "go-quiet.txt", "go-idle.txt", "go-scroll.txt"):
        (resources / name).unlink(missing_ok=True)
    command = [str(APPLICATION), "--project", str(project), "--dataless", "--opening-mode", "compiled", "--webadmin-auto-start", "false"]
    if intel:
        command = ["arch", "-x86_64", *command]
    log = (BUILD / f"cost-{variant}.log").open("w")
    launched = time.monotonic()
    process = subprocess.Popen(command, stdout=log, stderr=log)
    report = {"variant": variant, "wake": wake, "intel": intel, "phases": {}}

    def mark():
        try:
            return json.loads((resources / "mark.json").read_text(encoding="utf-8-sig"))["phase"]
        except (OSError, ValueError, KeyError):
            return None

    def wait_mark(expected, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if (resources / "error.json").exists():
                raise AssertionError((resources / "error.json").read_text())
            if process.poll() is not None and expected != "done":
                raise AssertionError(f"4D exited early: {process.returncode}")
            if mark() == expected:
                return
            time.sleep(0.02)
        raise AssertionError(f"Timed out waiting for {expected}")

    try:
        wait_for_start(process, project, lambda: mark() is not None, BUILD, timeout=120)
        report["startupSeconds"] = round(time.monotonic() - launched, 2)
        for phase in ("quiet", "idle", "scroll"):
            wait_mark(phase, 120)
            if wake:
                started = time.monotonic()
                app = ax.application(process.pid)
                report["phases"].setdefault(phase, {})["wakeElements"] = sum(read_tree(w) for w in app.read("AXWindows") or [])
                report["phases"][phase]["wakeSeconds"] = round(time.monotonic() - started, 2)
                time.sleep(1)
            before = cpu_seconds(process.pid)
            began = time.monotonic()
            (resources / f"go-{phase}.txt").write_text("go")
            wait_mark(phase + "-done", 300)
            elapsed = time.monotonic() - began
            spent = cpu_seconds(process.pid) - before
            report["phases"].setdefault(phase, {}).update({
                "cpuPercent": round(100 * spent / elapsed, 1), "seconds": round(elapsed, 1), "rssMB": round(rss_megabytes(process.pid))})
        process.wait(timeout=60)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        log.close()
    results = json.loads((resources / "results.json").read_text(encoding="utf-8-sig"))
    report["compiled"] = results["compiled"]
    for name in ("Small", "Large"):
        opens = [o for o in results["opens"] if o["form"] == name]
        report[f"open{name}Ms"] = {"median": statistics.median(o["shown"] for o in opens),
                                   "max": max(o["shown"] for o in opens), "runs": [o["shown"] for o in opens]}
        report[f"close{name}Ms"] = statistics.median(o["closed"] for o in opens)
    for phase in ("idle", "scroll"):
        report["phases"][phase].update(gap_summary(results["phases"][phase]["gaps"]))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--variant", choices=("none", "plugin", "area"), action="append", required=True)
    parser.add_argument("--duration", type=int, default=30000, help="Milliseconds of each idle and scroll phase")
    parser.add_argument("--wake", action="store_true", help="Read each window with an accessibility client first")
    parser.add_argument("--intel", action="store_true", help="Run 4D under Rosetta")
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if subprocess.run(["pgrep", "-x", "4D"], capture_output=True).returncode == 0:
        parser.error("Close 4D before measuring")
    if args.wake and not ax.trusted():
        parser.error("--wake needs Accessibility permission")
    verify_package(PACKAGE)
    server = args.server.expanduser().resolve()
    reports = []
    for variant in args.variant:
        fixture, project = prepare(server, variant, args.duration)
        for attempt in range(args.repeat):
            report = run(fixture, project, variant, args.wake, args.intel)
            report["attempt"] = attempt + 1
            report["nativeSha256"] = None if variant == "none" else sha(fixture / "Plugins/AccessibilityBridge.bundle/Contents/MacOS/AccessibilityBridge")
            report["componentSha256"] = None if variant == "none" else sha(fixture / "Components/AccessibilityBridge.4dbase/AccessibilityBridge.4DZ")
            print(json.dumps(report), flush=True)
            reports.append(report)
    if args.output:
        args.output.write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
