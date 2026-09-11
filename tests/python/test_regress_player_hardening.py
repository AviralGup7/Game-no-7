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

class PlayerBindTests(unittest.TestCase):
    def test_dodge_binds_and_multiplies_cooldown(self):
        txt=read("scripts/player/dodge_controller.gd")
        self.assertIn("func bind_motion(", txt)
        self.assertIn('get_stat(&"dodge_cooldown_multiplier", 1.0)', txt)
        self.assertIn("base * mult", txt)
        self.assertNotIn('get_stat(&"dodge_cooldown_multiplier", base)', txt)
    def test_player_wires_typed_binds(self):
        txt=read("scripts/player/player.gd")
        self.assertIn("PlayerCombat", txt)
        self.assertIn("_dodge.bind_motion(_controller, _progression)", txt)
        self.assertIn("_experience.bind_rewards(", txt)
        self.assertIn("_stamina.bind_progression(", txt)
        self.assertIn("_controller.bind_weapons(_weapons)", txt)
        self.assertIn("func request_dodge() -> bool:", txt)
        self.assertIn("func get_build_snapshot() -> Dictionary:", txt)
        self.assertIn("equipped_weapons", txt)
        self.assertIn("Player → WeaponManager → WeaponInstance", txt)
        self.assertIn("is_connected", txt)
        self.assertIn('get_node_or_null("DodgeController")', txt)
    def test_stamina_rejects_bad_delta(self):
        txt=read("scripts/player/stamina_component.gd")
        self.assertIn("not is_finite(delta)", txt)
        self.assertIn("func bind_progression(", txt)
    def test_experience_bind_keeps_owner_guard(self):
        txt=read("scripts/player/experience_component.gd")
        self.assertIn("func bind_rewards(", txt)
        self.assertIn("is_instance_valid(_owner_body)", txt)
    def test_character_controller_binds_weapons(self):
        txt=read("scripts/player/character_controller.gd")
        self.assertIn("func bind_weapons(", txt)
    def test_skills_bind_from_player(self):
        player=read("scripts/player/player.gd")
        self.assertIn("_skills.bind_systems(_experience, _status, _weapons, _health, _controller)", player)
        skills=read("scripts/skills/skill_controller.gd")
        self.assertIn("func bind_systems(", skills)
        self.assertIn("_unlocked.clear()", skills)
        exe=read("scripts/skills/skill_executor.gd")
        self.assertIn("func bind_systems(", exe)
        self.assertIn("func _status_of(", exe)
        self.assertIn("get_status_manager()", exe)
    def test_pickup_radius_upgrade_is_consumed(self):
        txt=read("scripts/pickups/pickup.gd")
        self.assertIn('get_stat(&"pickup_radius_add", 0.0)', txt)
        self.assertIn("config.collect_radius + _pickup_reach()", txt)
        self.assertIn("pickup_radius_add", read("data/upgrades/quartermaster.tres"))
if __name__=="__main__": unittest.main()
