"""Regression: Batch 12 — the real guards that survived the typed refactor.

The original Batch 12 file asserted the _validated_*/Dictionary-branch theater;
those helpers were removed in the typed-architecture refactor (see
docs/REFACTOR_PLAN.md). What remains here are the guards that are real
behavior: safe run/seed accessors, finite/clamp checks in combat math, and
the progression/health invariants.
"""
from __future__ import annotations
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class MainSafeGuardsTests(unittest.TestCase):
    def test_main_has_safe_helpers(self):
        txt = read("scripts/main/main.gd")
        # Typed accessors over GameRoot.get_run() -> RunState (no Dictionary probing).
        self.assertIn("func _safe_run()", txt)
        self.assertIn("func _safe_seed(", txt)
        self.assertIn("func _safe_arena_id(", txt)
    def test_main_uses_safe_seed_for_wave_manager(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("_wave_manager.start_run(_safe_seed())", txt)
    def test_main_uses_safe_arena_id_for_camera(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("ContentRegistry.get_arena(_safe_arena_id())", txt)
    def test_main_create_systems_uses_safe_seed(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("_spawn_manager.configure(", txt)
        # should be _safe_seed not GameRoot.get_run().seed
        self.assertNotIn("SpawnManager.configure(Vector3.ZERO, GameRoot.get_run().seed", txt)


class AchievementsGuardTests(unittest.TestCase):
    def test_achievements_uses_selected_count(self):
        txt = read("scripts/meta/achievements.gd")
        self.assertIn("func _selected_upgrade_count()", txt)
        self.assertIn("_selected_upgrade_count() >= 5", txt)
        self.assertIn('unlock(&"upgrader")', txt)


class WeightedTableGuardTests(unittest.TestCase):
    def test_weighted_table_clamps_and_finite(self):
        txt = read("scripts/utilities/weighted_table.gd")
        self.assertIn("is_finite(weight)", txt)
        self.assertIn("clampf(weight", txt)
        self.assertIn("1e9", txt)


class CriticalSystemGuardTests(unittest.TestCase):
    def test_critical_finite_and_instance_valid(self):
        txt = read("scripts/combat/critical_system.gd")
        self.assertIn("is_finite(base_chance)", txt)
        self.assertIn("is_instance_valid(rng)", txt)


class ProgressionComponentGuardTests(unittest.TestCase):
    def test_progression_finite(self):
        txt = read("scripts/player/progression_component.gd")
        self.assertIn("is_finite(base)", txt)
        self.assertIn("is_finite(float(_modifiers", txt)
        # The accumulated total must still be clamped. This used to pin the exact
        # text "clampf(float(_modifiers[k]) + v", but that spelling WAS the bug:
        # indexing _modifiers[k] before the key exists dropped the first stack of
        # every upgrade. Assert the clamp, not the buggy expression.
        self.assertRegex(txt, r"_modifiers\[k\] = clampf\(")


class HealthComponentGuardTests(unittest.TestCase):
    def test_health_finite_payload(self):
        txt = read("scripts/player/health_component.gd")
        self.assertIn("is_instance_valid(payload)", txt)
        self.assertIn("not payload.is_valid()", txt)
        self.assertNotIn("payload.amount =", txt)
        self.assertIn("not is_finite(amount)", txt)


if __name__ == "__main__":
    unittest.main()
