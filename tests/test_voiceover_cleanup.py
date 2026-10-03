"""Owned VoiceOver shutdown must work after the tested window disappears."""
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch

from voiceover import VoiceOver
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_voiceover_cleanup_fixture import cleanup_owned_fixtures


class OwnedApp:
    def __init__(self):
        self.running = True
        self.stops = 0

    def alive(self):
        return self.running

    def stop(self):
        self.stops += 1
        self.running = False


class Cleanup(unittest.TestCase):
    def setUp(self):
        blocked = patch("voiceover.c.CDLL", side_effect=AssertionError("Unit tests cannot send system input"))
        blocked.start()
        self.addCleanup(blocked.stop)
        unlocked = patch("voiceover.ax.require_unlocked")
        unlocked.start()
        self.addCleanup(unlocked.stop)

    def session(self, directory):
        vo = VoiceOver(SimpleNamespace(args=["/owned/fixture"], pid=12), None, "owned", directory, "/owned/ocr")
        vo.owned = True
        vo.voiceover_pid = 45
        vo.owned_applications = {45: OwnedApp()}
        return vo

    def test_missing_window_stops_only_the_retained_owned_app_and_preserves_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            original = AssertionError("Owned fixture window missing")
            with patch.object(vo, "key", side_effect=original), patch.object(vo, "pids", return_value=[45]):
                with self.assertRaises(AssertionError) as failure:
                    vo.stop()
            self.assertIs(failure.exception, original)
            self.assertEqual(vo.owned_applications[45].stops, 1)
            self.assertFalse(vo.owned)
            self.assertFalse(vo.changed_caption)

    def test_caption_restoration_failure_still_quits_the_owned_session(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.changed_caption = True
            with patch.object(vo, "key", side_effect=AssertionError("Owned fixture window missing")), patch.object(vo, "pids", return_value=[45]), patch("voiceover.ax.capture_window"):
                with self.assertRaisesRegex(AssertionError, "Owned fixture window missing"):
                    vo.stop()
            self.assertEqual(vo.owned_applications[45].stops, 1)

    def test_a_quit_failure_does_not_skip_other_owned_apps(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            refused = OwnedApp()
            original = AssertionError("Owned fixture lost foreground")
            vo.owned_applications = {44: refused, 45: OwnedApp()}
            with patch.object(vo, "key", side_effect=original), patch.object(vo, "pids", return_value=[45]), patch.object(refused, "stop", side_effect=RuntimeError("quit refused")), patch("voiceover.ax.wait_for", side_effect=AssertionError("quit remains pending")):
                with self.assertRaises(AssertionError) as failure:
                    vo.stop()
            self.assertIs(failure.exception, original)
            self.assertEqual(vo.owned_applications[45].stops, 1)
            self.assertTrue(any("quit refused" in note for note in original.__notes__))

    def test_normal_stop_verifies_the_welcome_helper_too(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.owned = False
            vo.owned_applications[45].running = False
            welcome = OwnedApp()
            vo.owned_applications[44] = welcome
            vo.stop()
            self.assertEqual(welcome.stops, 1)
            self.assertFalse(welcome.alive())

    def test_exited_voiceover_cannot_hide_an_unrestored_caption_setting(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.changed_caption = True
            vo.owned_applications[45].running = False
            with patch.object(vo, "pids", return_value=[]):
                with self.assertRaisesRegex(AssertionError, "caption setting was not restored"):
                    vo.stop()

    def test_another_voiceover_process_cannot_receive_test_input(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            with patch.object(vo, "pids", return_value=[99]):
                with self.assertRaisesRegex(AssertionError, "session changed"):
                    vo.guard_owned_voiceover()
            self.assertEqual(vo.owned_applications[45].stops, 0)

    def test_reused_pid_cannot_receive_test_input(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.owned_applications[45].running = False
            with patch.object(vo, "pids", return_value=[45]):
                with self.assertRaisesRegex(AssertionError, "process has exited"):
                    vo.guard_owned_voiceover()

    def test_startup_replacement_is_captured_before_the_session_is_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.owned = False
            vo.owned_applications = {}
            vo.accepted_quickstart = True
            snapshots = iter([[], [44], [45], [45], [45]])

            def pids(name):
                return [] if name == "VoiceOver Quickstart" else next(snapshots)

            def wait_for(predicate, message, **kwargs):
                if message == "VoiceOver did not start":
                    self.assertFalse(predicate(), "A replacement cannot be ready before ownership is captured")
                    self.assertTrue(predicate())
                    self.assertIn(vo.voiceover_pid, vo.owned_applications)
                else:
                    self.assertTrue(predicate())

            app = SimpleNamespace(read=lambda _: True)
            with patch.object(vo, "guard"), patch.object(vo, "guard_owned_voiceover"), patch.object(vo, "pids", side_effect=pids), patch("voiceover.OwnedApplication", side_effect=lambda _: OwnedApp()), patch("voiceover.subprocess.run"), patch("voiceover.ax.wait_for", side_effect=wait_for), patch("voiceover.ax.application", return_value=app), patch("voiceover.ax.capture_window"), patch("voiceover.time.sleep"):
                vo.start()
            self.assertEqual(vo.voiceover_pid, 45)
            self.assertEqual(set(vo.owned_applications), {44, 45})

    def test_caption_restoration_retry_does_not_show_an_already_hidden_panel(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.changed_caption = True
            hidden = RuntimeError("The fixture has no onscreen window to capture")
            with patch.object(vo, "key") as key, patch.object(vo, "guard_owned_voiceover"), patch("voiceover.ax.capture_window", side_effect=[None, RuntimeError("Capture failed"), hidden]):
                with self.assertRaisesRegex(RuntimeError, "Capture failed"):
                    vo.restore_caption()
                vo.restore_caption(cleanup=True)
            self.assertEqual(key.call_count, 1)
            self.assertTrue(vo.caption_restoration_verified)
            self.assertFalse(vo.changed_caption)

    def test_hidden_caption_baseline_needs_no_toggle(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            vo.changed_caption = True
            with patch.object(vo, "key") as key, patch.object(vo, "guard_owned_voiceover"), patch("voiceover.ax.capture_window", side_effect=RuntimeError("The fixture has no onscreen window to capture")):
                vo.restore_caption(cleanup=True)
            key.assert_not_called()
            self.assertTrue(vo.caption_restoration_verified)

    def test_caption_capture_uses_the_validated_owned_pid(self):
        with tempfile.TemporaryDirectory() as directory:
            vo = self.session(directory)
            with patch.object(vo, "guard"), patch.object(vo, "guard_owned_voiceover"), patch.object(vo, "pids", side_effect=AssertionError("Do not select another process after ownership validation")), patch("voiceover.ax.capture_window") as capture, patch("voiceover.subprocess.check_output", return_value="owned caption"):
                self.assertEqual(vo.read_caption(), "owned caption")
            self.assertEqual(capture.call_args.args[0], 45)

    def test_fixture_cleanup_attempts_every_process_after_a_failure(self):
        from unittest.mock import Mock
        first, second = Mock(), Mock()
        first.poll.return_value = second.poll.return_value = None
        refusal = RuntimeError("Owned fixture refused termination")
        first.terminate.side_effect = refusal
        errors = cleanup_owned_fixtures([first, second])
        self.assertEqual(errors, [refusal])
        first.wait.assert_called_once_with(timeout=15)
        second.terminate.assert_called_once_with()
        second.wait.assert_called_once_with(timeout=15)


if __name__ == "__main__":
    unittest.main()
