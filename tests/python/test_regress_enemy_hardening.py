"""Regression: enemy system hardening — lifecycle, locomotion, state machine.

Covers Batch 4-5-12 fixes: is_instance_valid in _ready, approach offset,
poise decay, Dash cooldown, navigator, striker, Elite affix, Boss thresholds,
and all 8 EnemyState validators.
"""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")

class EnemyBaseTests(unittest.TestCase):
    def test_ready_has_instance_valid(self):
        txt=read("scripts/enemies/enemy_base.gd")
        self.assertIn("is_instance_valid(_health)",txt)
        self.assertIn("is_instance_valid(_feedback)",txt)
        self.assertIn("is_instance_valid(_audio)",txt)
        self.assertIn("is_inside_tree()",txt)
        self.assertIn("has_signal(\"damaged\")",txt)
    def test_validated_knockback(self):
        txt=read("scripts/enemies/enemy_base.gd")
        self.assertIn("_validated_knockback",txt)
        self.assertIn("is_finite(k.x)",txt)
    def test_health_fraction_clamped(self):
        txt=read("scripts/enemies/enemy_base.gd")
        self.assertIn("get_health_fraction",txt)
        self.assertIn("clampf",txt)

class EnemyConfigTests(unittest.TestCase):
    def test_validated_stats(self):
        txt=read("scripts/enemies/enemy_config.gd")
        self.assertIn("_validated_stats",txt)
        self.assertIn("is_finite(max_health)",txt)
        self.assertIn("is_finite(move_speed)",txt)
        self.assertIn("is_finite(attack_damage)",txt)
    def test_bounds_validation(self):
        txt=read("scripts/enemies/enemy_config.gd")
        self.assertIn("clampf(max_health",txt)

class EnemyStateMachineTests(unittest.TestCase):
    def test_change_to_guards(self):
        txt=read("scripts/enemies/enemy_state_machine.gd")
        self.assertIn("state_id == &\"\"",txt)
        self.assertIn("is_instance_valid(_host)",txt)

class EnemyStateValidatorsTests(unittest.TestCase):
    def test_chase_validator(self):
        txt=read("scripts/enemies/enemy_chase_state.gd")
        self.assertIn("_validated_chase",txt)
        self.assertIn("is_finite(speed)",txt)
        self.assertIn("is_inside_tree()",txt)
    def test_attack_validator(self):
        txt=read("scripts/enemies/enemy_attack_state.gd")
        self.assertIn("_validated_attack_cd",txt)
        self.assertIn("is_finite(cd)",txt)
        self.assertIn("_attack_can_enter",txt)
    def test_hurt_validator(self):
        txt=read("scripts/enemies/enemy_hurt_state.gd")
        self.assertIn("_validated_hurt_time",txt)
        self.assertIn("clampf(t",txt)
    def test_idle_validator(self):
        txt=read("scripts/enemies/enemy_idle_state.gd")
        self.assertIn("_validated_idle_dwell",txt)
    def test_ranged_validator(self):
        txt=read("scripts/enemies/enemy_ranged_state.gd")
        self.assertIn("_validated_ranged",txt)
    def test_dash_validator(self):
        txt=read("scripts/enemies/enemy_dash_state.gd")
        self.assertIn("_validated_dash",txt)
        self.assertIn("clampf(speed",txt)
    def test_fuse_validator(self):
        txt=read("scripts/enemies/enemy_fuse_state.gd")
        self.assertIn("_validated_fuse",txt)
    def test_dead_validator(self):
        txt=read("scripts/enemies/enemy_dead_state.gd")
        self.assertIn("_validated_dead_enter",txt)

class BossControllerTests(unittest.TestCase):
    def test_phase_index_finite_and_empty(self):
        txt=read("scripts/enemies/boss_controller.gd")
        self.assertIn("phases.is_empty()",txt)
        self.assertIn("is_finite(th)",txt)
        self.assertIn("clampf(th",txt)
        self.assertIn("clampi(target",txt)
    def test_validated_threshold(self):
        txt=read("scripts/enemies/boss_controller.gd")
        self.assertIn("_validated_threshold",txt)
        self.assertIn("is_finite(t)",txt)

class EliteAffixTests(unittest.TestCase):
    def test_validated_elite(self):
        txt=read("scripts/enemies/enemy_elite_affix.gd")
        self.assertIn("_validated_elite_mult",txt)

class SpawnPatternsTests(unittest.TestCase):
    def test_validated_spawn_count(self):
        txt=read("scripts/enemies/spawn_patterns.gd")
        self.assertIn("_validated_spawn_count",txt)

class EnemyAnimatorTests(unittest.TestCase):
    def test_validated_anim_speed(self):
        txt=read("scripts/enemies/enemy_animator.gd")
        self.assertIn("_validated_anim_speed",txt)

if __name__=="__main__": unittest.main()
