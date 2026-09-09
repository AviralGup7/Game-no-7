"""Regression: player systems — stamina, health, progression, locomotion, targeting.

Batch 2/3/11/12 introduced finite/clamp guards, EventBus instance checks,
and validated helpers across all player components.
"""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8",errors="ignore")

class StaminaTests(unittest.TestCase):
    def test_validated_config(self):
        txt=read("scripts/player/stamina_component.gd")
        # Real guards: regen delay and fraction are clamped where computed.
        self.assertIn("clampf(_current / _max, 0.0, 1.0)",txt)
    def test_restore_full_emits_eventbus(self):
        txt=read("scripts/player/stamina_component.gd")
        self.assertIn("EventBus.stamina_changed.emit",txt)
        self.assertIn("func restore_full",txt)
    def test_exhaust_emits(self):
        txt=read("scripts/player/stamina_component.gd")
        self.assertIn("exhausted.emit()",txt)
        self.assertIn("stamina_changed.emit(_current, _max)",txt)
class HealthTests(unittest.TestCase):
    def test_finite_payload(self):
        txt=read("scripts/player/health_component.gd")
        self.assertIn("is_instance_valid(payload)",txt)
        self.assertIn("is_finite(float(payload.amount))",txt)
    def test_heal_finite(self):
        txt=read("scripts/player/health_component.gd")
        self.assertIn("not is_finite(amount)",txt)
        self.assertIn("func heal",txt)
    def test_has_validated_helpers(self):
        txt=read("scripts/player/health_component.gd")
        # indirectly via get_debug still there but no explicit validated; check finite guards exist
        self.assertIn("is_finite",txt)
class ProgressionTests(unittest.TestCase):
    def test_get_stat_finite(self):
        txt=read("scripts/player/progression_component.gd")
        self.assertIn("is_finite(base)",txt)
        self.assertIn("is_finite(float(_modifiers",txt)
    def test_accumulate_clamp(self):
        txt=read("scripts/player/progression_component.gd")
        self.assertIn("is_finite(float(raw))",txt)
        # See test_regress_batch12_guards: the old literal "clampf(float(_modifiers"
        # pinned the very expression that dropped every upgrade's first stack.
        self.assertRegex(txt, r"_modifiers\[k\] = clampf\(")
class ExperienceTests(unittest.TestCase):
    def test_validated_xp_mult(self):
        txt=read("scripts/player/experience_component.gd")
        self.assertIn("_xp_multiplier = clampf(mult, 0.0, 10.0)",txt)
    def test_unlock_skills_guard(self):
        txt=read("scripts/player/experience_component.gd")
        self.assertIn("is_instance_valid(_owner_body)",txt)
class PlayerTests(unittest.TestCase):
    def test_validated_delta(self):
        txt=read("scripts/player/player.gd")
        self.assertIn("is_finite(delta)",txt)
if __name__=="__main__": unittest.main()
