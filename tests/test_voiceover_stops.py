"""Regression cases for summaries that used to count as individual VO stops."""
import unittest

from voiceover import reading_stop, reading_stop_index


def step(caption, key="right", shift=False):
    return {"key": key, "shift": shift, "command": False, "caption": caption}


class ReadingStops(unittest.TestCase):
    def test_actual_leaves(self):
        self.assertTrue(reading_stop(step("× Native field, Insertion at beginning of text., Native field, edit text"), "edit text", "native field"))
        self.assertTrue(reading_stop(step("× Close fixture, button."), "button", "close fixture"))
        self.assertTrue(reading_stop(step("X link, Next page"), "link", "next page"))

    def test_parent_summary(self):
        summary = step("X Native field, edit text, Count, button, Native web fixture, web content, Close fixture, button, group")
        self.assertFalse(reading_stop(summary, "edit text", "native field"))
        self.assertFalse(reading_stop(summary, "button", "close fixture"))

    def test_summary_ending_with_button(self):
        self.assertFalse(reading_stop(step("group, Native field, edit text, Close fixture, button"), "button", "close fixture"))

    def test_interaction_is_not_a_leaf(self):
        self.assertFalse(reading_stop(step("Native field, edit text", key="down", shift=True), "edit text", "native field"))
        self.assertFalse(reading_stop(step("Out of group, Close fixture, button", key="up", shift=True), "button", "close fixture"))

    def test_plain_arrow_is_not_voiceover(self):
        plain = step("Close fixture, button")
        plain["voiceoverModifier"] = False
        self.assertFalse(reading_stop(plain, "button", "close fixture"))

    def test_heading_prefix_and_parent_context(self):
        self.assertTrue(reading_stop(step("Heading level 1, Native web fixture", key="left"), "heading level 1", "native web fixture"))
        self.assertFalse(reading_stop(step("In Native web fixture, web content, heading level 1, Native web fixture", key="down", shift=True), "heading level 1", "native web fixture"))

    def test_index_uses_captured_steps(self):
        steps = [step("Native field, edit text", key="down", shift=True), step("Native field, edit text"), step("Count, button")]
        self.assertEqual(reading_stop_index(steps, "edit text", "native field"), 1)
        self.assertEqual(reading_stop_index(steps, "button", "count", after=1), 2)
        self.assertIsNone(reading_stop_index(steps, "button", "close fixture"))


if __name__ == "__main__":
    unittest.main()
