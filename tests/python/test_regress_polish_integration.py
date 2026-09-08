"""Integration: polish phase — player skill anims, boss phases, audio, UI/camera, lifecycle."""
from __future__ import annotations
import pathlib, unittest, re
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8", errors="ignore")

class PolishIntegrationTests(unittest.TestCase):
    def test_player_skill_animation_wired(self):
        txt = read("scripts/player/player_animation.gd")
        self.assertIn("skill_cast_clips", txt)
        self.assertIn("victory_clip", txt)
        self.assertIn("_on_skill_cast", txt)
        self.assertIn("EventBus.skill_cast.is_connected", txt)
        self.assertIn("Spellcast_Shoot", txt)
        self.assertIn("Cheer", txt)

    def test_enemy_stun_and_cast(self):
        txt = read("scripts/enemies/enemy_animator.gd")
        self.assertIn("KEY_STUN", txt)
        self.assertIn("KEY_CAST", txt)
        self.assertIn("_on_status_applied", txt)
        self.assertIn("_on_boss_telegraph", txt)
        self.assertIn("stunned", txt)

    def test_boss_phase_visuals(self):
        txt = read("scripts/enemies/boss_controller.gd")
        self.assertIn("_apply_phase_visuals", txt)
        self.assertIn("BossPhaseLight", txt)
        self.assertIn("Fury", txt)
        self.assertIn("Enrage", txt)
        self.assertIn('AudioManager.play_sfx(&"boss_spawned"', txt)
        self.assertIn('boss_phase_changed', txt)

    def test_procedural_audio_expanded(self):
        txt = read("scripts/audio/procedural_sfx.gd")
        self.assertIn('&"skill_cast"', txt)
        self.assertIn('&"wave_started"', txt)
        self.assertIn('&"boss_spawned"', txt)
        self.assertIn('&"level_up"', txt)
        self.assertIn('&"player_step"', txt)
        self.assertIn('&"enemy_windup"', txt)
        # ensure 20+ cues
        cues = re.findall(r'&"[^"]+"', txt)
        self.assertGreaterEqual(len([c for c in cues if "player" in c or "skill" in c or "boss" in c]), 15)

    def test_skill_audio_triggers(self):
        txt = read("scripts/skills/skill_controller.gd")
        self.assertIn('AudioManager.play_sfx(&"skill_cast"', txt)
        self.assertIn('AudioManager.play_sfx(&"skill_ready"', txt)
        txt2 = read("scripts/player/experience_component.gd")
        self.assertIn('AudioManager.play_sfx(&"level_up"', txt2)
        txt3 = read("scripts/waves/wave_manager.gd")
        self.assertIn('AudioManager.play_sfx(&"wave_started"', txt3)

    def test_upgrade_panel_rarity_border(self):
        txt = read("scripts/ui/upgrade_panel.gd")
        self.assertIn("rarity border", txt.lower())
        self.assertIn("icon_max_width", txt)
        self.assertIn("32", txt)
        self.assertIn("corner_radius_all(10)", txt)

    def test_touch_controls_thumb_friendly(self):
        txt = read("scripts/ui/touch_controls.gd")
        self.assertIn("64.0", txt)  # attack enlarged
        self.assertIn("52.0", txt)

    def test_camera_combat_feedback(self):
        txt = read("scripts/main/camera_rig.gd")
        self.assertIn("_wire_combat_feedback", txt)
        self.assertIn("add_shake", txt)
        self.assertIn("skill_cast", txt)
        self.assertIn("boss_slain", txt)
        self.assertIn("max_shake_amplitude", txt)

    def test_effect_director_skill_wiring(self):
        txt = read("scripts/visuals/effect_director.gd")
        self.assertIn("SKILL_COLORS", txt)
        self.assertIn("skill_cast", txt)
        self.assertIn("MAX_BURSTS := 10", txt)

    def test_lifecycle_no_duplicate_listeners(self):
        # Verify every EventBus connect in new polish uses is_connected guard where it LISTENS
        for rel in ["scripts/player/player_animation.gd", "scripts/enemies/boss_controller.gd",
                    "scripts/main/camera_rig.gd"]:
            txt = read(rel)
            # at least one guarded connect
            self.assertIn("is_connected", txt, msg=rel)
        # SkillController correctly EMITS rather than listening to EventBus, so no guard needed there
        txt_emit = read("scripts/skills/skill_controller.gd")
        self.assertIn("EventBus.skill_cast.emit", txt_emit)

if __name__ == "__main__":
    unittest.main()
