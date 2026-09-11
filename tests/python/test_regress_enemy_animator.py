"""Regression guards for enemy animator clip lock / private libraries / catalog.

v1 mutated imported Animation.loop_mode (leaking across every enemy of that
archetype), never unlocked after a one-shot (chase froze on the last attack
frame), and did not share the player's directional-dodge facing rule.
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


ANIM = "scripts/enemies/enemy_animator.gd"
CATALOG = "scripts/enemies/enemy_clip_catalog.gd"
SCENES = [
    "scenes/enemies/basic_enemy.tscn",
    "scenes/enemies/fast_enemy.tscn",
    "scenes/enemies/heavy_enemy.tscn",
    "scenes/enemies/ranged_enemy.tscn",
    "scenes/enemies/warlord_enemy.tscn",
    "scenes/enemies/exploder_enemy.tscn",
    "scenes/enemies/dasher_enemy.tscn",
    "scenes/enemies/splitter_enemy.tscn",
]


class TestPrivateClipLibraries(unittest.TestCase):
    def test_does_not_mutate_shared_loop_mode(self) -> None:
        text = code_lines(read(ANIM))
        # Duplicate + local flag; the imported resource is never written.
        self.assertIn("src.duplicate()", text)
        self.assertIn("resource_local_to_scene = true", text)
        self.assertNotIn("anim.loop_mode = Animation.LOOP_NONE", text)
        self.assertNotIn("anim.loop_mode = Animation.LOOP_LINEAR", text)

    def test_hip_lock_only_on_private_copies(self) -> None:
        body = code_lines(func_body(read(ANIM), "_lock_hip_xz"))
        self.assertIn("TYPE_POSITION_3D", body)
        self.assertIn("v.x = 0.0", body)
        self.assertIn("v.z = 0.0", body)


class TestLockAndResume(unittest.TestCase):
    def test_one_shots_lock_until_finished(self) -> None:
        text = read(ANIM)
        self.assertIn("var _locked := false", text)
        self.assertIn("animation_finished.connect(_on_finished)", text)
        body = code_lines(func_body(text, "_on_finished"))
        self.assertIn("_locked = false", body)
        self.assertIn("_resume_locomotion()", body)
        play = code_lines(func_body(text, "_play_named"))
        self.assertIn("EnemyClipCatalog.is_one_shot(key)", play)

    def test_process_skips_while_locked_and_pauses_when_ai_disabled(self) -> None:
        body = code_lines(func_body(read(ANIM), "_process"))
        self.assertIn("is_ai_enabled()", body)
        self.assertIn("_paused_for_ai", body)
        self.assertIn("if _locked:", body)

    def test_ai_enabled_getter_exists(self) -> None:
        text = read("scripts/enemies/enemy_base.gd")
        self.assertIn("func is_ai_enabled() -> bool:", text)
        self.assertIn("func set_ai_enabled(enabled: bool) -> void:", text)


class TestClipCatalogWiring(unittest.TestCase):
    def test_keys_include_telegraph_dash_spawn(self) -> None:
        text = read(ANIM)
        for key in [
            "KEY_STUN",
            "KEY_CAST",
            "KEY_TELEGRAPH",
            "KEY_DASH",
            "KEY_SPAWN",
        ]:
            self.assertIn(key, text)
        catalog = read(CATALOG)
        self.assertIn("class_name EnemyClipCatalog", catalog)
        self.assertIn("func directional_dash(", catalog)
        self.assertIn("HeroRigContract.directional_dodge", catalog)
        self.assertIn("func resume_after_one_shot(", catalog)

    def test_animator_uses_hero_rig_contract(self) -> None:
        text = read(ANIM)
        self.assertIn("HeroRigContract.animation_player(wrapper)", text)
        dash = code_lines(func_body(text, "_play_dash"))
        self.assertIn("EnemyClipCatalog.directional_dash", dash)

    def test_finite_length_guard(self) -> None:
        body = code_lines(func_body(read(ANIM), "_length"))
        self.assertIn("EnemyClipCatalog.finite_length", body)


class TestSceneMaps(unittest.TestCase):
    def test_every_enemy_scene_still_has_idle_and_attack(self) -> None:
        for rel in SCENES:
            txt = read(rel)
            self.assertIn('"idle":', txt, msg=rel)
            self.assertIn('"attack":', txt, msg=rel)
            self.assertIn("yaw_offset_degrees = 180.0", txt, msg=rel)

    def test_kenney_maps_expose_stun_cast_telegraph_dash(self) -> None:
        for rel in [
            "scenes/enemies/basic_enemy.tscn",
            "scenes/enemies/fast_enemy.tscn",
            "scenes/enemies/heavy_enemy.tscn",
            "scenes/enemies/ranged_enemy.tscn",
        ]:
            txt = read(rel)
            self.assertIn('"stun":', txt, msg=rel)
            self.assertIn('"cast":', txt, msg=rel)
            self.assertIn('"telegraph":', txt, msg=rel)
            self.assertIn('"dash":', txt, msg=rel)
            self.assertIn('"spawn":', txt, msg=rel)

    def test_eight_animator_scenes(self) -> None:
        self.assertEqual(len(SCENES), 8)


if __name__ == "__main__":
    unittest.main()
