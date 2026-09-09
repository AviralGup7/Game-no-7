"""Regression guards for the audio playback-engine rebuild (v2).

v1 shipped a fully data-driven AudioConfig schema the playback engine never
honored: per-cue cooldown, per-cue max_voices, per-play volume/pitch rolls,
bus routing (the "UI" bus was declared valid but never even created) and the
music_layer tag were all dead fields. SFX voices started at full volume
instantly (click) and were hard-stopped when stolen (pop). MusicManager's
"4-layer intensity mixer" was a volume nudge on a single bed, and AudioManager
carried a second, dead, hard-switching music path.

Static-source guards on purpose: the Python suite runs without a Godot
binary, so each check asserts the shape of the fix. The deterministic
behavioural contract lives in tests/unit/test_audio_policy.gd.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code_lines(text: str) -> str:
    """Executable lines only (full-line comments stripped)."""
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
MUSIC = "scripts/audio/music_manager.gd"
CONFIG = "scripts/audio/audio_config.gd"
POLICY = "scripts/audio/sfx_policy.gd"


class TestSfxGovernance(unittest.TestCase):
    def test_policy_core_exists(self) -> None:
        text = read(POLICY)
        self.assertIn("class_name SfxPolicy", text)
        self.assertIn('const REJECT := &"reject"', text)
        self.assertIn('const FRESH := &"fresh"', text)
        self.assertIn('const STEAL := &"steal"', text)
        self.assertIn("func try_play(", text)
        self.assertIn("func voice_started(", text)
        self.assertIn("func voice_ended(", text)

    def test_play_sfx_honors_the_contract(self) -> None:
        body = code_lines(func_body(read(MANAGER), "play_sfx"))
        # Cooldown + cap gate the play (silent on reject, no warning spam).
        self.assertIn("_policy.try_play(", body)
        self.assertIn("SfxPolicy.REJECT", body)
        # Per-play rolls come from the config, not hard-coded constancy.
        self.assertIn("cfg.roll_volume_db(", body)
        self.assertIn("cfg.roll_pitch(", body)
        # Bus routing from config (single start point: _start_voice).
        start = code_lines(func_body(read(MANAGER), "_start_voice"))
        self.assertIn("_safe_bus(cfg.bus)", start)
        # Rejects stay silent (the guard must not just move the spam into
        # the report channel).
        i = body.index("SfxPolicy.REJECT")
        j = body.index("return false", i)
        self.assertNotIn("report_warning", body[i:j])

    def test_voices_are_click_safe(self) -> None:
        text = read(MANAGER)
        body = code_lines(text)
        # Short onset ramp for every start.
        fade_in = float(re.search(r"FADE_IN_SECONDS := ([\d.]+)", text).group(1))
        self.assertGreaterEqual(fade_in, 0.005)
        self.assertLessEqual(fade_in, 0.025)
        # ~30 ms release with a non-linear (1-t^2 family) shape.
        m = re.search(r"FADE_OUT_SECONDS := ([\d.]+)", text)
        self.assertIsNotNone(m)
        self.assertGreaterEqual(float(m.group(1)), 0.02)
        self.assertLessEqual(float(m.group(1)), 0.06)
        self.assertIn("1.0 - k * k", body)
        # No hard stop on the steal path: stealing defers through a fade.
        self.assertIn("func _defer_on_fade(", text)
        self.assertIn("_pending", body)
        # Starts always ramp from silence.
        self.assertIn("player.volume_db = -80.0", body)

    def test_stealing_is_per_cue_oldest_then_global(self) -> None:
        body = code_lines(func_body(read(MANAGER), "play_sfx"))
        self.assertIn("SfxPolicy.STEAL", body)
        self.assertIn("_defer_on_fade", body)
        # Global ceiling fallback (v1 behavior, now fade-protected).
        self.assertIn("oldest_pos", body)
        self.assertIn("MAX_SFX_VOICES", read(MANAGER))

    def test_ui_bus_exists_and_routes(self) -> None:
        body = code_lines(func_body(read(MANAGER), "_ensure_buses"))
        self.assertIn('"Music", "SFX", "UI"', body)
        preview = code_lines(func_body(read(MANAGER), "preview_bus_volume"))
        self.assertIn('"ui":', preview)


class TestAudioConfigContract(unittest.TestCase):
    def test_for_cue_is_the_live_default(self) -> None:
        text = code_lines(read(CONFIG))
        self.assertIn("static func for_cue(", text)
        # Tuned spam sources + UI bus routing + music ids all present.
        self.assertIn('"player_step"', text)
        self.assertIn('"ui_confirm"', text)
        self.assertIn('&"UI"', text)
        self.assertIn('"music_battle"', text)

    def test_manager_uses_registered_or_default_config(self) -> None:
        manager = read(MANAGER)
        self.assertIn("func register_cue(cue_id: StringName, stream: AudioStream, config: AudioConfig = null)", manager)
        self.assertIn("AudioConfig.for_cue(cue_id)", code_lines(manager))


class TestMusicLayering(unittest.TestCase):
    def test_dead_manager_music_path_removed(self) -> None:
        text = code_lines(read(MANAGER))
        self.assertNotIn("func play_music(", text)
        self.assertNotIn("func stop_music(", text)
        self.assertNotIn("_music_player", text)
        self.assertNotIn("func get_current_music(", text)

    def test_fake_volume_nudge_layer_removed(self) -> None:
        text = code_lines(read(MUSIC))
        self.assertNotIn("_layer_volume_db", text)

    def test_real_stem_layering(self) -> None:
        text = code_lines(read(MUSIC))
        # Stem convention + players.
        self.assertIn('"%s_l%d"', text)
        self.assertIn("STEM_COUNT := 2", text)
        # Asymmetric fades + dwell suppression.
        self.assertIn("STEM_FADE_UP_SECONDS := 0.6", text)
        self.assertIn("STEM_FADE_DOWN_SECONDS := 2.0", text)
        self.assertIn("LAYER_DWELL_SECONDS := 0.4", text)
        self.assertIn("func stem_fade_seconds(rising: bool)", text)
        # Phase sync on join.
        self.assertIn("func _phase_sync(", text)
        self.assertIn("stem.seek(pos)", text)
        # No hard cuts: stream swaps ride a pending fade-out.
        self.assertIn('"pending"', text)
        self.assertIn("func _stem_fade_done(", text)

    def test_v1_api_preserved(self) -> None:
        text = read(MUSIC)
        for name in [
            "class_name MusicManager",
            "func get_state()",
            "func get_heat()",
            "func get_layer()",
            "func request_state(state: StringName)",
            "func begin_tracking()",
            "func add_heat(amount: float)",
            "func get_debug_snapshot()",
            "signal music_state_changed(old_state: StringName, new_state: StringName)",
            "const CROSSFADE_SECONDS := 1.5",
            "const HEAT_DECAY_PER_SECOND := 0.25",
        ]:
            self.assertIn(name, text)


class TestRuntimePinsPreserved(unittest.TestCase):
    def test_soak_and_stress_seams_intact(self) -> None:
        # Soak/stress scripts iterate these directly; names must survive.
        text = code_lines(read(MANAGER))
        self.assertIn("var _sfx_pool: Array[AudioStreamPlayer]", text)
        self.assertIn("var _cues: Dictionary", text)
        self.assertIn("func get_cue_stream(", text)
        self.assertIn("func is_background_muted(", text)

    def test_unit_suite_registered(self) -> None:
        run_tests = read("tests/run_tests.gd")
        self.assertIn("res://tests/unit/test_audio_policy.gd", run_tests)
        unit = read("tests/unit/test_audio_policy.gd")
        self.assertIn("static func suite() -> Array", unit)
        self.assertIn("SfxPolicy", unit)
        self.assertIn("for_cue", unit)
        self.assertIn("target_layer_for", unit)
        self.assertIn("stem_targets", unit)
        self.assertIn("stem_fade_seconds", unit)


if __name__ == "__main__":
    unittest.main()
