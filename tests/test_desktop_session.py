"""A locked session must stop polling before any test input is attempted."""
import unittest
from unittest.mock import Mock, patch

import mac_ax as ax


class DesktopSessionTests(unittest.TestCase):
    def test_locked_session_stops_before_predicate(self):
        predicate = Mock()
        with patch.object(ax, "session_locked", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "Graphical session is locked"):
                ax.wait_for(predicate, "would otherwise wait", timeout=30)
        predicate.assert_not_called()

    def test_relock_stops_the_next_poll(self):
        predicate = Mock(return_value=False)
        with patch.object(ax, "session_locked", side_effect=[False, True]), patch.object(ax.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "Graphical session is locked"):
                ax.wait_for(predicate, "would otherwise wait", timeout=30)
        predicate.assert_called_once()

    def test_unlocked_session_returns_the_real_result(self):
        with patch.object(ax, "session_locked", return_value=False):
            self.assertEqual(ax.wait_for(lambda: "ready", "missing result"), "ready")

    def test_unavailable_session_is_not_treated_as_ready(self):
        predicate = Mock()
        with patch.object(ax, "session_locked", side_effect=RuntimeError("No graphical login session")):
            with self.assertRaisesRegex(RuntimeError, "No graphical login session"):
                ax.wait_for(predicate, "missing result")
        predicate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
