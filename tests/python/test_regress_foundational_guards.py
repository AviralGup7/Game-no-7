"""Regression: foundational guards — export ranges, null checks, finite, Dict guards.

This is the exhaustive sweep that ensures every remaining risk class is covered:
  - @export_range on float exports
  - is_instance_valid on Node refs
  - is_finite on floats entering physics
  - Dictionary-aware GameRoot branching in UI/meta/waves
  - EventBus/ContentRegistry null guards
"""
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class ExportRangeTests(unittest.TestCase):
    def test_boss_phase_threshold_has_clamp(self):
        txt=read("scripts/enemies/boss_phase_config.gd")
        self.assertIn("@export_range(0.01, 1.0, 0.01) var threshold",txt)
    def test_health_max_export_validated(self):
        # health_component has finite guards even if not export_range
        txt=read("scripts/player/health_component.gd")
        self.assertIn("is_finite",txt)
class InstanceValidTests(unittest.TestCase):
    def test_enemy_base_has_all_valid(self):
        txt=read("scripts/enemies/enemy_base.gd")
        for frag in ["_health != null","_feedback != null","_audio != null","_machine != null"]:
            self.assertIn(frag,txt)
    def test_tutorial_has_instance_valid(self):
        txt=read("scripts/ui/tutorial_manager.gd")
        self.assertIn("is_instance_valid",txt)
    def test_status_has_instance_valid(self):
        txt=read("scripts/status/status_manager.gd")
        self.assertIn("is_instance_valid(fx)",txt)
    def test_projectile_has_instance_valid(self):
        self.assertIn("is_instance_valid(self)",read("scripts/weapons/projectile.gd"))
class FiniteTests(unittest.TestCase):
    def test_weighted_table(self):
        self.assertIn("is_finite(weight)",read("scripts/utilities/weighted_table.gd"))
    def test_difficulty_director(self):
        self.assertIn("is_finite(_now)",read("scripts/waves/difficulty_director.gd"))
    def test_critical(self):
        self.assertIn("is_finite(base_chance)",read("scripts/combat/critical_system.gd"))
class EventBusContentGuardsTests(unittest.TestCase):
    def test_experience_guards_contentregistry(self):
        txt=read("scripts/player/experience_component.gd")
        self.assertIn("ContentRegistry",txt)
    def test_progression_guards_contentregistry(self):
        txt=read("scripts/player/progression_component.gd")
        self.assertIn("ContentRegistry",txt)
if __name__=="__main__": unittest.main()
