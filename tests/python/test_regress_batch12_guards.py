"""Regression: Batch 12 — Dictionary-aware GameRoot guards + finite/clamp hardening.

Batch 12 introduced _safe_run/_safe_seed/_safe_arena_id in main.gd and
Dictionary-aware branches in achievements, meta_progression, run_summary,
upgrade_panel, wave_manager, plus finite/clamp validators across combat,
waves, player, weapons, core, arena, audio, visuals, status, ui.

Each test asserts the source contains the guard so future regressions are caught.
"""
from __future__ import annotations
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")

class MainSafeGuardsTests(unittest.TestCase):
    def test_main_has_safe_helpers(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("func _safe_run()", txt)
        self.assertIn("func _safe_seed(", txt)
        self.assertIn("func _safe_arena_id(", txt)
        self.assertIn("has_method(\"get_run\")", txt)
        self.assertIn("is Dictionary", txt)
        self.assertIn("\"seed\" in run", txt)
        self.assertIn("\"arena_id\" in run", txt)

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
    def test_achievements_has_safe_run(self):
        txt = read("scripts/meta/achievements.gd")
        self.assertIn("func _safe_run()", txt)
        self.assertIn("func _selected_upgrade_count()", txt)
        self.assertIn("is Dictionary", txt)
        self.assertIn("\"selected_upgrades\" in", txt)

    def test_achievements_uses_selected_count(self):
        txt = read("scripts/meta/achievements.gd")
        self.assertIn("_selected_upgrade_count() >= 5", txt)
        self.assertIn("unlock(&\"upgrader\")", txt)

class MetaProgressionGuardTests(unittest.TestCase):
    def test_meta_currency_guard(self):
        txt = read("scripts/meta/meta_progression.gd")
        self.assertIn("has_method(\"get_run\")", txt)
        # Dictionary-aware branch
        self.assertIn("run is Dictionary", txt)
        self.assertIn("\"currency\" in run", txt)
        self.assertIn("earned", txt)

class RunSummaryGuardTests(unittest.TestCase):
    def test_run_summary_guards_null(self):
        txt = read("scripts/ui/run_summary_panel.gd")
        self.assertIn("GameRoot == null", txt)
        self.assertIn("has_method(\"summary\")", txt)
        self.assertIn(".duplicate", txt)

class UpgradePanelGuardTests(unittest.TestCase):
    def test_upgrade_panel_guards_dictionary(self):
        txt = read("scripts/ui/upgrade_panel.gd")
        self.assertIn("run is Dictionary", txt)
        self.assertIn("\"selected_upgrades\" in run", txt)

class WaveManagerGuardTests(unittest.TestCase):
    def test_wave_manager_guards_elapsed(self):
        txt = read("scripts/waves/wave_manager.gd")
        self.assertIn("has_method(\"get_run\")", txt)
        self.assertIn("\"elapsed_seconds\" in run", txt)

class WeightedTableGuardTests(unittest.TestCase):
    def test_weighted_table_clamps_and_finite(self):
        txt = read("scripts/utilities/weighted_table.gd")
        self.assertIn("is_finite(weight)", txt)
        self.assertIn("clampf(weight", txt)
        self.assertIn("1e9", txt)

    def test_weighted_total_validated(self):
        txt = read("scripts/utilities/weighted_table.gd")
        self.assertIn("_validated_total", txt)

class CriticalSystemGuardTests(unittest.TestCase):
    def test_critical_finite_and_instance_valid(self):
        txt = read("scripts/combat/critical_system.gd")
        self.assertIn("is_finite(base_chance)", txt)
        self.assertIn("is_instance_valid(rng)", txt)
        self.assertIn("_validated_crit_chance", txt)

class ProgressionComponentGuardTests(unittest.TestCase):
    def test_progression_finite(self):
        txt = read("scripts/player/progression_component.gd")
        self.assertIn("is_finite(base)", txt)
        self.assertIn("is_finite(float(_modifiers", txt)
        self.assertIn("clampf(float(_modifiers", txt)

class HealthComponentGuardTests(unittest.TestCase):
    def test_health_finite_payload(self):
        txt = read("scripts/player/health_component.gd")
        self.assertIn("is_instance_valid(payload)", txt)
        self.assertIn("is_finite(float(payload.amount))", txt)
        self.assertIn("not is_finite(amount)", txt)

if __name__ == "__main__":
    unittest.main()
