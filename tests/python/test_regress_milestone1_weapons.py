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
        for wid in expected:
            self.assertIn(f'res://assets/scifi/guns/{wid}.glb', txt)
        self.assertNotIn('assets/weapons/', txt)

    def test_firearms_have_authored_muzzles_and_metres(self):
        from tool.validate_assets import gltf_document
        for wid in parse_tres_weapon_ids():
            doc, _ = gltf_document(ROOT / f'assets/scifi/guns/{wid}.glb')
            marker = next(n for n in doc['nodes'] if n.get('name') == 'Muzzle')
            self.assertGreater(marker['translation'][2], .35)
            self.assertLess(marker['translation'][2], 1.1)
            self.assertNotIn('skins', doc)

    def test_player_animation_uses_firearm_recoil_and_reload(self):
        txt = read("scripts/player/player_animation.gd")
        self.assertIn('ranged_clip: StringName = &"Fire"', txt)
        self.assertIn('reload_clip: StringName = &"Reload"', txt)
        self.assertNotIn('Melee_Attack', txt)
        for wid in parse_tres_weapon_ids():
            cfg = read(f'data/weapons/{wid}.tres')
            self.assertIn('kind = &"ranged"', cfg)

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
        self.assertIn("_model = models[id].instantiate() as Node3D", read("scripts/player/player_equipment.gd"))

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
        self.assertLess(txt.index("_model.free()"), txt.index("_model = models[id].instantiate()"))
        self.assertNotIn("_second_model", txt)

if __name__ == "__main__":
    unittest.main()
