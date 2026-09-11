"""Regression guards for audio v3: isolated UI bank, spatial world Foley, mix snapshots.

v2 honoured AudioConfig (cooldown/cap/bus/rolls) and click-safe 2D voices, but
every cue still shared one 16-voice AudioStreamPlayer pool. A full combat bed
could steal a menu click, and a pack of enemies across the arena all played at
listener volume. MusicManager remains the only music owner — snapshots offset
SFX/UI only.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code_lines(text: str) -> str:
    out: list[str] = []
    for line in text.splitlines():
        if line.strip().startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def func_body(text: str, name: str) -> str:
    m = re.search(
        r"^(?:static )?func %s\((.*?)\n(.*?)(?=^func |^static func |\Z)" % re.escape(name),
        text,
        re.S | re.M,
    )
    assert m, "func %s not found" % name
    return m.group(2)


MANAGER = "scripts/audio/audio_manager.gd"
CONFIG = "scripts/audio/audio_config.gd"
BANK = "scripts/audio/voice_bank.gd"
SPATIAL = "scripts/audio/spatial_voice_pool.gd"
ATTEN = "scripts/audio/spatial_attenuation.gd"
MIX = "scripts/audio/mix_snapshot.gd"
ENEMY_AUDIO = "scripts/enemies/enemy_audio.gd"
PROCEDURAL = "scripts/audio/procedural_sfx.gd"
MUSIC = "scripts/audio/music_manager.gd"


class TestUiBankIsolation(unittest.TestCase):
    def test_ui_bank_is_a_separate_pool(self) -> None:
        text = read(MANAGER)
        self.assertIn("MAX_UI_VOICES := 4", text)
        self.assertIn("UI_TOKEN_BASE := 100", text)
        self.assertIn("var _ui_bank := VoiceBank.new()", text)
        self.assertIn('p.bus = "UI"', text)
        # Combat 2D pool size / type preserved for soak/stress.
        self.assertIn("var _sfx_pool: Array[AudioStreamPlayer]", text)
        self.assertIn("MAX_SFX_VOICES := 16", text)

    def test_play_sfx_routes_ui_bus_to_the_ui_bank(self) -> None:
        body = code_lines(func_body(read(MANAGER), "play_sfx"))
        self.assertIn("AudioConfig.is_ui_bus(cfg.bus)", body)
        self.assertIn("_ui_bank.claim(", body)
        # v2 contract still lives in the same function (SFX path after the UI branch).
        self.assertIn("_policy.try_play(", body)
        self.assertIn("SfxPolicy.REJECT", body)
        self.assertIn("oldest_pos", body)

    def test_ui_tokens_do_not_overlap_sfx_indices(self) -> None:
        text = read(MANAGER)
        self.assertIn("UI_TOKEN_BASE := 100", text)
        spatial = read(SPATIAL)
        self.assertIn("TOKEN_BASE := 200", spatial)
        self.assertGreater(100, 16)
        self.assertGreater(200, 100 + 4)


class TestSpatialWorldFoley(unittest.TestCase):
    def test_play_sfx_at_and_on_exist(self) -> None:
        text = read(MANAGER)
        self.assertIn(
            "func play_sfx_at(cue_id: StringName, at: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:",
            text,
        )
        self.assertIn(
            "func play_sfx_on(cue_id: StringName, emitter: Node3D, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:",
            text,
        )
        self.assertIn("func bind_listener(anchor: Node3D) -> void:", text)

    def test_world_path_culls_then_policies(self) -> None:
        body = code_lines(func_body(read(MANAGER), "_play_world"))
        # Cull BEFORE claiming a voice.
        cull_at = body.index("SpatialAttenuation.is_hearable")
        policy_at = body.index("_policy.try_play(")
        self.assertLess(cull_at, policy_at)
        # UI never spatializes; music never goes through this path.
        self.assertIn("AudioConfig.is_ui_bus(cfg.bus)", body)
        self.assertIn("play_sfx(cue_id, volume_db, pitch_scale)", body)
        self.assertIn("AudioConfig.is_music_bus(cfg.bus)", body)
        self.assertIn("_spatial.play_on(", body)
        self.assertIn("_spatial.play_at(", body)

    def test_spatial_pool_is_3d_and_sfx_bus(self) -> None:
        text = read(SPATIAL)
        self.assertIn("class_name SpatialVoicePool", text)
        self.assertIn("AudioStreamPlayer3D.new()", text)
        self.assertIn('p.bus = "SFX"', text)
        self.assertIn("ATTENUATION_INVERSE_DISTANCE", text)
        self.assertIn("SpatialAttenuation.is_hearable", text)
        self.assertIn("func play_on(", text)
        self.assertIn("func play_at(", text)

    def test_enemy_audio_follows_the_host(self) -> None:
        body = code_lines(func_body(read(ENEMY_AUDIO), "_play"))
        self.assertIn("play_sfx_on(", body)
        # 2D fallback when the host is not a Node3D (headless fixtures).
        self.assertIn("play_sfx(", body)

    def test_world_cue_table_covers_enemy_foley(self) -> None:
        text = read(CONFIG)
        for cue in [
            "enemy_hit",
            "enemy_death",
            "enemy_attack",
            "enemy_spawn",
            "enemy_windup",
            "enemy_dash",
            "enemy_explosion",
        ]:
            self.assertIn('&"%s"' % cue, text)
        self.assertIn("static func is_world_cue(", text)
        self.assertNotIn('&"ui_confirm"', code_lines(func_body(read(CONFIG), "is_world_cue")))


class TestMixSnapshots(unittest.TestCase):
    def test_snapshot_ids_and_music_offset_zero(self) -> None:
        text = read(MIX)
        self.assertIn("class_name MixSnapshot", text)
        for ident in [
            "ID_MENU",
            "ID_COMBAT",
            "ID_BOSS",
            "ID_PAUSED",
            "ID_SILENT",
            "ID_UPGRADE",
            "ID_GAME_OVER",
        ]:
            self.assertIn(ident, text)
        paused = code_lines(func_body(text, "offsets_for"))
        # Pause ducks SFX; UI stays at 0; music stays at 0.
        self.assertIn("ID_PAUSED", paused)
        self.assertIn("KEY_MUSIC: 0.0", paused)

    def test_manager_applies_snapshots_without_owning_music(self) -> None:
        text = code_lines(read(MANAGER))
        self.assertIn("MixSnapshot.compose_bus_db", text)
        self.assertIn("func _apply_mix(", text)
        self.assertNotIn("func play_music(", text)
        self.assertNotIn("func stop_music(", text)
        self.assertNotIn("_music_player", text)
        music = code_lines(read(MUSIC))
        self.assertIn("class_name MusicManager", music)

    def test_pause_and_state_hooks(self) -> None:
        text = read(MANAGER)
        self.assertIn("EventBus.pause_changed.connect(_on_pause_changed)", text)
        self.assertIn("EventBus.game_state_changed.connect(_on_game_state_changed)", text)
        self.assertIn("MixSnapshot.id_for_run", text)


class TestStemsRegistered(unittest.TestCase):
    def test_procedural_stems_exist(self) -> None:
        text = read(PROCEDURAL)
        self.assertIn("&\"music_battle_l2\"", text)
        self.assertIn("&\"music_battle_l3\"", text)
        self.assertIn("&\"music_boss_l2\"", text)
        self.assertIn("STEM_CUES", text)
        body = code_lines(func_body(text, "ensure_registered"))
        self.assertIn("STEM_CUES", body)

    def test_click_safe_bank_matches_manager(self) -> None:
        bank = read(BANK)
        manager = read(MANAGER)
        self.assertIn("FADE_IN_SECONDS := 0.012", bank)
        self.assertIn("FADE_OUT_SECONDS := 0.030", bank)
        self.assertIn("1.0 - k * k", bank)
        self.assertIn("FADE_IN_SECONDS := 0.012", manager)
        self.assertIn("FADE_OUT_SECONDS := 0.030", manager)


class TestListenerBind(unittest.TestCase):
    def test_game_root_binds_the_player(self) -> None:
        text = read("scripts/core/game_root.gd")
        body = code_lines(func_body(text, "set_active_player"))
        self.assertIn("AudioManager.bind_listener(player)", body)

    def test_listener_is_not_parented_onto_the_player(self) -> None:
        body = code_lines(func_body(read(MANAGER), "bind_listener"))
        self.assertNotIn("add_child", body)
        self.assertIn("_spatial.set_listener", body)


class TestUnitSuiteRegistered(unittest.TestCase):
    def test_spatial_suite_is_in_run_tests(self) -> None:
        run = read("tests/run_tests.gd")
        self.assertIn("res://tests/unit/test_spatial_audio.gd", run)
        unit = read("tests/unit/test_spatial_audio.gd")
        self.assertIn("static func suite() -> Array", unit)
        self.assertIn("SpatialAttenuation", unit)
        self.assertIn("MixSnapshot", unit)
        self.assertIn("EnemyClipCatalog", unit)


if __name__ == "__main__":
    unittest.main()
