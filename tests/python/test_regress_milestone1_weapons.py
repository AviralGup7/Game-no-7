"""Regression: Milestone 1 — 9 weapons fully integrated, visuals grounded without arbitrary offsets."""
from __future__ import annotations
import pathlib, re, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")

def parse_tres_weapon_ids() -> list[str]:
    ids = []
    for p in (ROOT / "data" / "weapons").glob("*.tres"):
        txt = p.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r'weapon_id\s*=\s*&"([^"]+)"', txt)
        if m:
            # Check disabled flag — only count enabled weapons
            disabled = re.search(r"disabled\s*=\s*(true|false)", txt)
            is_disabled = disabled and disabled.group(1) == "true"
            if not is_disabled:
                ids.append(m.group(1))
    return sorted(ids)

class Milestone1WeaponsIntegrationTests(unittest.TestCase):
    def test_all_enabled_weapons_in_player_tscn_models(self):
        """All 9 enabled weapon configs must have a PackedScene entry in PlayerEquipment.models."""
        enabled = parse_tres_weapon_ids()
        self.assertEqual(len(enabled), 9, msg=f"expected 9 enabled weapons, got {enabled}")
        expected = sorted(["gladius","sentinel_spear","stormhammer","sunbow","twinfangs","warreaxe","ember_scepter","moonlance","venom_chain"])
        self.assertEqual(enabled, expected)
        txt = read("scenes/player/player.tscn")
        # Check models dict contains each id
        for wid in expected:
            self.assertIn(f'&"{wid}"', txt, msg=f"weapon {wid} missing from player.tscn")
        # Ensure lengths dict also has each
        # Extract lengths line
        m = re.search(r"lengths\s*=\s*\{([^}]+)\}", txt, re.DOTALL)
        self.assertIsNotNone(m)
        lengths_body = m.group(1)
        for wid in expected:
            self.assertIn(f'&"{wid}"', lengths_body, msg=f"length for {wid} missing")
        # Ensure we have distinct ext_resources for ember_scepter (Skeleton_Staff.gltf)
        self.assertIn("Skeleton_Staff.gltf", txt)
        # moonlance and venom_chain reuse existing Spear/Dagger — verify reuse present
        self.assertIn('ExtResource(\"19_spear\")', txt)
        self.assertIn('ExtResource(\"22_dagger\")', txt)

    def test_player_tscn_weapon_lengths_reasonable(self):
        txt = read("scenes/player/player.tscn")
        # Extract lengths values
        m = re.search(r"lengths\s*=\s*\{([^}]+)\}", txt, re.DOTALL)
        self.assertIsNotNone(m)
        body = m.group(1)
        # Parse float values after colon
        vals = re.findall(r":\s*([0-9.]+)", body)
        for v in vals:
            f = float(v)
            self.assertGreaterEqual(f, 0.4, msg=f"length {f} too small")
            self.assertLessEqual(f, 2.2, msg=f"length {f} too large")
        # Check specific new weapons have distinct lengths
        self.assertIn("&\"ember_scepter\": 1.35", txt)
        self.assertIn("&\"moonlance\": 1.85", txt)
        self.assertIn("&\"venom_chain\": 0.85", txt)

    def test_player_animation_has_weapon_specific_clips_for_all_melee_hybrid(self):
        txt = read("scripts/player/player_animation.gd")
        # All non-pure-ranged weapons should have an explicit clip
        for wid in ["sentinel_spear","stormhammer","warreaxe","twinfangs","moonlance","venom_chain"]:
            self.assertIn(f'&"{wid}"', txt, msg=f"weapon_attack_clips missing {wid}")
        # Ember scepter should have Spellcast_Shoot clip distinct from ranged_clip
        self.assertIn('&"ember_scepter": &"Spellcast_Shoot"', txt)
        # Verify ranged override priority: weapon_attack_clips check comes AFTER ranged fallback
        # So custom ranged clip wins. Ensure order: ranged check before weapon clip.
        idx_ranged = txt.find('is_ranged() and not inst.config.is_melee()')
        idx_weapon = txt.find('weapon_attack_clips.has(inst.config.weapon_id)')
        # After our fix, ranged comes first, weapon second => weapon wins
        self.assertGreater(idx_weapon, idx_ranged, msg="weapon_attack_clips should override ranged_clip for ember_scepter")

    def test_character_visuals_grounding_without_arbitrary_offsets(self):
        txt = read("scripts/visuals/character_visuals.gd")
        # Grounding derives from measured post-scale bounds (no magic numbers):
        # position assignment uses the -bounds.get_center / -bounds.position pattern.
        self.assertIn("-bounds.get_center().x", txt)
        self.assertIn("-bounds.position.y", txt)
        self.assertIn("-bounds.get_center().z", txt)
        # ...applied exactly once: bounds already include scale/rotation, so a second
        # `* factor` would double-count the fit scale and offset the body off-capsule.
        self.assertNotIn("get_center().x * factor", txt)
        self.assertNotIn("position.y * factor", txt)
        self.assertNotIn("get_center().z * factor", txt)
        # Yaw is PI uniform, no per-role random yaw
        self.assertIn('"yaw\": PI', txt)

    def test_model_visual_normalization_uses_longest_axis_and_pivot(self):
        txt = read("scripts/visuals/model_visual.gd")
        self.assertIn("longest := maxf(box.size.x, maxf(box.size.y, box.size.z))", txt)
        self.assertIn("pivot := box.get_center()", txt)
        self.assertIn("pivot.y = box.position.y", txt)
        self.assertIn("(fitted.get_child(0) as Node3D).position = Vector3.ZERO", read("scripts/player/player_equipment.gd"))

    def test_weapon_configs_disabled_false_for_all_nine(self):
        for p in (ROOT / "data" / "weapons").glob("*.tres"):
            txt = p.read_text(encoding="utf-8", errors="ignore")
            wid_m = re.search(r'weapon_id\s*=\s*&"([^"]+)"', txt)
            if wid_m and wid_m.group(1) in ["ember_scepter","moonlance","venom_chain"]:
                self.assertIn("disabled = false", txt, msg=f"{wid_m.group(1)} should be enabled")

    def test_no_duplicate_weapon_models_after_switch(self):
        txt = read("scripts/player/player_equipment.gd")
        # Ensure old model is freed before new one added (prevents duplicate meshes)
        self.assertIn("_model.free()", txt)
        self.assertIn("_second_model.free()", txt)
        self.assertIn("if _second_model != null:", txt)

if __name__ == "__main__":
    unittest.main()
