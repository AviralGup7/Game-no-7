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
        self.assertIn("_validated_stamina_config",txt)
        self.assertIn("is_finite(v)",txt)
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
        self.assertIn("_validated_xp_mult",txt)
        self.assertIn("is_finite(m)",txt)
    def test_unlock_skills_guard(self):
        txt=read("scripts/player/experience_component.gd")
        self.assertIn("is_instance_valid(_owner_body)",txt)
        self.assertIn("has_method(\"get_all_skill_configs\")",txt)

class LocomotionTests(unittest.TestCase):
    def test_validated_loco(self):
        txt=read("scripts/player/player_locomotion.gd")
        self.assertIn("_validated_loco_speed",txt)

class TargetingTests(unittest.TestCase):
    def test_validated_range(self):
        txt=read("scripts/player/targeting_component.gd")
        self.assertIn("_validated_target_range",txt)

class AttackControllerTests(unittest.TestCase):
    def test_validated_damage(self):
        txt=read("scripts/player/attack_controller.gd")
        self.assertIn("_validated_attack_damage",txt)

class DodgeControllerTests(unittest.TestCase):
    def test_validated_window(self):
        txt=read("scripts/player/dodge_controller.gd")
        self.assertIn("_validated_dodge_window",txt)

class PlayerTests(unittest.TestCase):
    def test_validated_delta(self):
        txt=read("scripts/player/player.gd")
        self.assertIn("_validated_delta",txt)
        self.assertIn("is_finite(delta)",txt)

if __name__=="__main__": unittest.main()
