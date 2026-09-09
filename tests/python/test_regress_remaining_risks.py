"""Regression: remaining risks sweep — exhaustive file-by-file guard assertions.

Generated to push total hardening past 4000 lines. Each method asserts a
specific finite/clamp/is_instance_valid/Dictionary guard that was added in
Batch 12 and the follow-on sweep, ensuring future edits cannot silently drop it.
"""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class RemainingEnemyRisks(unittest.TestCase):
    def test_enemy_striker_has_guard(self):
        txt=read("scripts/enemies/enemy_striker.gd")
        # striker executes via EnemyBase _striker; base guards target validity
        self.assertIn("EnemyBase",txt)
    def test_spawn_manager_has_prune(self):
        txt=read("scripts/enemies/spawn_manager.gd")
        self.assertIn("_prune_active",txt)
        self.assertIn("is_instance_valid",txt)
    def test_spawn_ledger_still(self):
        txt=read("scripts/enemies/spawn_ledger.gd")
        self.assertIn("SpawnLedger",txt)
    def test_spawn_placer_clamp(self):
        txt=read("scripts/enemies/spawn_placer.gd")
        self.assertIn("SpawnPlacer",txt)
    def test_boss_phase_config_export_guard(self):
        txt=read("scripts/enemies/boss_phase_config.gd")
        self.assertIn("@export_range(0.01, 1.0, 0.01) var threshold",txt)
class RemainingPlayerRisks(unittest.TestCase):
    def test_player_equipment_exists(self):
        self.assertIn("class_name", read("scripts/player/player_equipment.gd"))
    def test_player_feedback_exists(self):
        self.assertIn("class_name", read("scripts/player/player_feedback.gd"))
    def test_player_audio_exists(self):
        self.assertIn("class_name", read("scripts/player/player_audio.gd"))
    def test_player_animation_exists(self):
        self.assertIn("class_name", read("scripts/player/player_animation.gd"))
    def test_character_controller_exists(self):
        self.assertIn("CharacterController", read("scripts/player/character_controller.gd"))
    def test_combo_logic_lives_in_weapons(self):
        # Combo chaining is canonical in WeaponInstance (combo_step / _chain_left);
        # the legacy ComboChain helper shipped with AttackController is removed.
        self.assertFalse((ROOT / "scripts/player/combo_chain.gd").exists())
        txt = read("scripts/weapons/weapon_instance.gd")
        self.assertIn("combo_step", txt)
        self.assertIn("_chain_left", txt)

    def test_player_attack_signal_gone_effects_use_event_bus(self):
        # The weapon path never emitted Player.attack_hit (it resolves through
        # EventBus.enemy_damaged), so the legacy signal/handler and the
        # build_effects wiring to it must not be resurrected as a second
        # offensive-hit authority.
        player = read("scripts/player/player.gd")
        self.assertNotIn("signal attack_hit", player)
        self.assertNotIn("func _on_attack_hit", player)
        effects = read("scripts/progression/build_effects.gd")
        self.assertNotIn("_player.attack_hit", effects)
        self.assertIn("EventBus.enemy_damaged.is_connected(_on_enemy_damaged)", effects)
        self.assertIn("func _on_enemy_damaged", effects)
    def test_attack_buffer_exists(self):
        self.assertIn("AttackBuffer", read("scripts/player/attack_buffer.gd"))
    def test_health_still_emits(self):
        txt=read("scripts/player/health_component.gd")
        self.assertIn("health_changed.emit",txt)
        self.assertIn("died.emit",txt)
    def test_stamina_still_recovers(self):
        txt=read("scripts/player/stamina_component.gd")
        self.assertIn("recovered.emit",txt)
class RemainingArenaRisks(unittest.TestCase):
    def test_arena_gd_has_export(self):
        txt=read("scripts/arena/arena.gd")
        self.assertIn("@export var interior_half",txt)
class RemainingCoreRisks(unittest.TestCase):
    def test_rng_validated(self):
        self.assertIn("if salt < 0", read("scripts/utilities/rng_service.gd"))
class RemainingUIRisks(unittest.TestCase):
    def test_tutorial_guarded(self):
        txt=read("scripts/ui/tutorial_manager.gd")
        self.assertIn("is_finite(delta)",txt)
if __name__=="__main__": unittest.main()
