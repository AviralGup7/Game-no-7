"""Static regression guards for enemy AI lifecycle and numeric boundaries."""
from __future__ import annotations
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class EnemyAiHardeningTests(unittest.TestCase):
    def test_state_machine_serializes_reentrant_transitions(self):
        text = read("scripts/enemies/enemy_state_machine.gd")
        self.assertIn("var _transitioning := false", text)
        self.assertIn("var _queued_state: StringName", text)
        self.assertIn("func _commit_state", text)
        self.assertIn("_commit_state(queued)", text)
        self.assertIn("forced or _queued_state ==", text)

    def test_perception_rejects_invalid_spatial_and_time_values(self):
        text = read("scripts/enemies/enemy_perception.gd")
        self.assertIn("func _finite_vector", text)
        self.assertIn("not is_finite(delta)", text)
        self.assertIn("not is_finite(intensity)", text)
        self.assertIn("_finite_nonnegative", text)
        self.assertIn("not _finite_vector(target_pos)", text)

    def test_navigator_does_not_propagate_nan(self):
        text = read("scripts/enemies/enemy_navigator.gd")
        self.assertIn("func _finite_vector", text)
        self.assertIn("not _finite_vector(body_position)", text)
        self.assertIn("update_interval = update_interval if is_finite", text)
        self.assertIn("not is_finite(delta)", text)

    def test_research_document_exists(self):
        text = read("docs/ENEMY_AI_ROBUSTNESS_RESEARCH.md")
        self.assertIn("EnemyStateMachine", text)
        self.assertIn("EnemyPerception", text)
        self.assertIn("EnemyNavigator", text)


if __name__ == "__main__":
    unittest.main()
