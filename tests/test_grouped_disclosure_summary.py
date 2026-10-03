"""Exercise the disclosure evidence guards without running 4D."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))
import summarize_grouped_disclosure as summary
from test_grouped_outline_summary import prepare, write


def action():
    group = {"kind": "group", "level": 1, "label": "A", "expanded": True}
    before = {"runId": "one", "compiled": True, "rootTick": 1, "disclosureCalls": [], "beforeGroup": {}, "events": [],
              "outline": {"rows": ["group"], "outline": {"group": group}, "positions": {"group": 7}}}
    after = copy.deepcopy(before)
    call = {"objectName": "Grouped", "backingRow": 7, "breakLevel": 2, "expanded": False, "actionID": "one"}
    after["disclosureCalls"] = [call]
    after["outline"]["outline"]["group"]["expanded"] = False
    return {"before": before, "after": after, "calls": [call], "rowKey": "group", "expanded": False, "receipt": summary.CONFIRMED}


class DisclosureEvidence(unittest.TestCase):
    def test_completion_requires_independent_state_and_resolved_packet(self):
        summary.validate_action(action())
        for mutation in ("state", "coordinates", "fields", "duplicate", "idempotent"):
            with self.subTest(mutation=mutation):
                item = action()
                if mutation == "state":
                    item["after"]["outline"]["outline"]["group"]["expanded"] = True
                elif mutation == "coordinates":
                    item["calls"][0]["backingRow"] = 99
                elif mutation == "fields":
                    item["calls"][0]["callback"] = "untrusted"
                elif mutation == "duplicate":
                    item["calls"].append(copy.deepcopy(item["calls"][0]))
                else:
                    item["receipt"] = summary.IDEMPOTENT
                with self.assertRaises(AssertionError):
                    summary.validate_action(item)

    def test_nominal_rejections_pending_receipts_and_spliced_states_reject(self):
        for mutation in ("rejected", "pending", "blank", "run", "mode", "prefix"):
            with self.subTest(mutation=mutation):
                item = action()
                if mutation in ("rejected", "pending", "blank"):
                    item["receipt"] = {"rejected": "Rejected", "pending": "Action queued", "blank": " "}[mutation]
                elif mutation == "run":
                    item["after"]["runId"] = "another-run"
                elif mutation == "mode":
                    item["before"]["compiled"] = False
                else:
                    item["before"]["disclosureCalls"] = [{"old": True}]
                    item["after"]["disclosureCalls"].insert(0, {"replacement": True})
                with self.assertRaises(AssertionError):
                    summary.validate_action(item, run_id="one", compiled=True, outcome=summary.CONFIRMED, call_count=1)
        for receipt in ("", "Action queued", "Waiting for the application to complete the action"):
            item = action()
            item["receipt"] = receipt
            with self.assertRaises(AssertionError):
                summary.validate_action(item, outcome="rejected")

    def test_nested_sibling_scroll_and_coherent_tick_guards(self):
        ordinary = action()
        root = {"runId": "one", "compiled": True, "rootTick": 1, "outerScroll": {"Wrapper": [40, 15], "PeerWrapper": [30, 12]},
                "main": {"innerScroll": [20, 10]}, "peer": {"innerScroll": [10, 5]}}
        peer = copy.deepcopy(ordinary["before"])
        item = {"instance": "main", "before": {"root": root, "main": ordinary["before"], "peer": peer},
                "after": {"root": copy.deepcopy(root), "main": ordinary["after"], "peer": copy.deepcopy(peer)}}
        summary.validate_nested_preservation(item, "one", True)
        for mutation in ("callback", "data", "events", "outer", "inner", "tick", "run", "mode"):
            with self.subTest(mutation=mutation):
                candidate = copy.deepcopy(item)
                after = candidate["after"]
                if mutation in ("callback", "data", "events"):
                    field = {"callback": "disclosureCalls", "data": "beforeGroup", "events": "events"}[mutation]
                    after["peer"][field] = ["changed"]
                elif mutation == "outer":
                    after["root"]["outerScroll"]["Wrapper"][0] = 41
                elif mutation == "inner":
                    after["root"]["peer"]["innerScroll"][0] = 11
                elif mutation == "tick":
                    after["peer"]["rootTick"] = 2
                elif mutation == "run":
                    after["peer"]["runId"] = "another-run"
                else:
                    after["peer"]["compiled"] = False
                with self.assertRaises(AssertionError):
                    summary.validate_nested_preservation(candidate, "one", True)

    def test_voiceover_requires_each_intent_state_and_caption(self):
        items = []
        for expanded in (False, True, False, True):
            item = action()
            item["expanded"] = expanded
            item["before"]["outline"]["outline"]["group"]["expanded"] = not expanded
            item["after"]["outline"]["outline"]["group"]["expanded"] = expanded
            item["calls"][0]["expanded"] = expanded
            item["caption"] = "A: " + ("expanded" if expanded else "collapsed")
            items.append(item)
        report = {"runId": "one", "voiceoverCollapse": items[0], "voiceoverExpand": items[1], "voiceoverRowActions": items[2:],
                  "collapsedCaption": items[0]["caption"], "expandedCaption": items[1]["caption"], "groupActivationTarget": "disclosure",
                  "disclosureNavigationIndex": 2, "rowNavigationIndex": 7,
                  "voiceover": [{"key": "space"}, {"key": "space"}, {"key": "up", "shift": True, "caption": "A"},
                                {"key": "right", "caption": "shared level 1"}, {"key": "home"},
                                {"key": "space"}, {"key": "space"}, {"key": "right", "caption": "shared level 1"}]}
        summary.validate_voiceover(report)
        for mutation in ("caption", "intent", "state", "navigation", "earlier-navigation"):
            with self.subTest(mutation=mutation):
                candidate = copy.deepcopy(report)
                row = candidate["voiceoverRowActions"][0]
                if mutation == "caption":
                    row["caption"] = "A: expanded"
                elif mutation == "intent":
                    row["calls"][0]["expanded"] = True
                elif mutation == "state":
                    row["after"]["outline"]["outline"]["group"]["expanded"] = True
                elif mutation == "navigation":
                    candidate["voiceover"][7]["caption"] = "another row"
                else:
                    candidate["rowNavigationIndex"] = 3
                with self.assertRaises(AssertionError):
                    summary.validate_voiceover(candidate)

    def test_faults_require_the_observed_mutation(self):
        for fault in summary.FAULTS[1:]:
            with self.subTest(fault=fault):
                item = action()
                before = item["before"]
                before.update({"disclosureMode": fault, "scope": "A", "ready": True, "runtimeGeneration": "first", "runtimeDisclosure": True,
                               "beforeGroup": {"keys": [1], "levels": [{"values": ["A"]}]}})
                before["outline"]["positions"]["group"] = 1
                after = copy.deepcopy(before)
                if fault == "membership":
                    after["beforeGroup"]["keys"] = [1001]
                elif fault in ("caption", "reparent"):
                    after["beforeGroup"]["levels"][0]["values"] = ["Changed caption" if fault == "caption" else "Moved parent"]
                elif fault == "scope":
                    after["scope"] = "B"
                elif fault == "loading":
                    after["ready"] = False
                if fault in ("loading", "replace", "remove"):
                    after["runtimeGeneration"] = "second"
                if fault == "remove":
                    after["runtimeDisclosure"] = False
                item["after"] = after
                summary.validate_fault(item)
                item["after"] = copy.deepcopy(before)
                with self.assertRaises(AssertionError):
                    summary.validate_fault(item)

    def test_editor_rejection_cannot_be_blank_pending_or_completed(self):
        summary.terminal_rejection("Finish native editing before changing this group")
        for receipt in ("", " ", summary.CONFIRMED, summary.IDEMPOTENT, "Action queued", "Waiting for the application to complete the action"):
            with self.subTest(receipt=receipt), self.assertRaises(AssertionError):
                summary.terminal_rejection(receipt)

    def test_narrow_voiceover_run_cannot_accept_full_actions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare(root)
            for name in set(summary.ACTION_SOURCES) | set(summary.NESTED_SOURCES):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, path)
            prepared_path, prepared = summary.validate_prepared(root)
            report = {"passed": True, "compiled": True, "actionGate": False, "exitCode": 0, "runId": "one", "closed": {"runId": "one"},
                "compileReportSHA256": summary.sha(prepared_path), "preparedSourceSHA256": prepared["sources_sha256"],
                "driverSourceSHA256": {name: summary.sha(root / name) for name in summary.ACTION_SOURCES},
                "window": {"title": "AX native hierarchy probe"}, "finalState": {"runId": "one", "compiled": True},
                "actions": [action()] * 25}
            for field in ("canonicalSourceSHA256", "nativeSourceSHA256", "componentSourceSHA256", "nativeSHA256", "componentPackageSHA256", "compiledHostSHA256"):
                report[field] = prepared[field]
            path = root / "narrow.json"
            write(path, report)
            with self.assertRaises(AssertionError):
                summary.validate_run(root, path, prepared_path, prepared, True)

    def test_failed_publication_erases_old_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "summary.json"
            write(output, {"passed": True})
            with self.assertRaises(OSError):
                summary.publish(root, output)
            self.assertIs(json.loads(output.read_text())["passed"], False)


if __name__ == "__main__":
    unittest.main()
