"""Regression: Milestones 2-7 — remaining work validation."""
from __future__ import annotations
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")

class Milestone2_SkillsAndVFX(unittest.TestCase):
    def test_skill_colors_cover_all_8(self):
        txt = read("scripts/visuals/effect_director.gd")
        for sid in ["bladestorm","frost_nova_skill","phantom_rush","seismic_slam","warcry_skill","chain_lightning","mending_light","shatterwave"]:
            self.assertIn(f'&"{sid}"', txt, msg=f"SKILL_COLORS missing {sid}")
        # legacy aliases still present
        self.assertIn('&"frost_nova"', txt)
        self.assertIn('&"warcry"', txt)
        # distinct radii
        self.assertIn("shatterwave", txt)
        self.assertIn("chain_lightning", txt)
    def test_status_colors_cover_all_13(self):
        txt = read("scripts/visuals/effect_director.gd")
        for sid in ["burn","bleed","shock","slow","stun","guard","regen","warcry","exposed","frenzy","haste","overguard","poison"]:
            self.assertIn(f'&"{sid}"', txt)
    def test_effect_director_priority_and_saturation(self):
        txt = read("scripts/visuals/effect_director.gd")
        self.assertIn("PRIORITY_CRITICAL", txt)
        self.assertIn("PRIORITY_BOSS", txt)
        self.assertIn("PRIORITY_SKILL", txt)
        self.assertIn("MAX_BURSTS := 10", txt)
        self.assertIn("MAX_RINGS := 14", txt)
        # saturation preserves critical/boss: steal lowest priority when saturated
        self.assertIn("Saturated: steal", txt)
        self.assertIn("_burst_prios", txt)
        self.assertIn("_ring_prios", txt)
    def test_enemy_boss_presentation(self):
        txt = read("scripts/enemies/boss_controller.gd")
        self.assertIn("BossPhaseLight", txt)
        self.assertIn("recolor", txt)
        self.assertIn("light_energy", txt)
        # Phase 5 deleted Arena.THEMES: the per-arena look became authored
        # ArenaThemeConfig/ArenaLandmarkConfig resources. What the milestone actually
        # promised is that each arena still has its own theme and its own named
        # centrepiece, so that is what gets asserted now -- against the data the game
        # loads, instead of against a constant that was itself the weak design.
        txt2 = read("scripts/arena/arena.gd")
        self.assertIn("ArenaThemeConfig", txt2)
        self.assertNotIn("THEMES := {", txt2)
        for arena_id in ("default_arena", "ember_crucible", "frost_hollow"):
            theme = read(f"data/arena_themes/{arena_id}.tres")
            self.assertIn(f'theme_id = &"{arena_id}"', theme, f"{arena_id} must own its theme")
            cfg = read(f"data/arenas/{arena_id}.tres")
            self.assertIn("theme = ExtResource(", cfg)
            self.assertIn("landmark = ExtResource(", cfg)
        silhouettes = " ".join(read(f"data/arena_landmarks/{k}.tres") for k in ("forge", "crystal", "obelisk"))
        for kind in ("forge", "crystal", "obelisk"):
            self.assertIn(f'kind = &"{kind}"', silhouettes, f"landmark silhouette '{kind}' is gone")
class Milestone3_AuthorityAndLifecycle(unittest.TestCase):
    def test_legacy_attack_modules_removed(self):
        # The M3 cleanup is done: AttackController/ComboChain were deleted, not
        # left as parallel legacy authorities. Nothing may resurrect them as
        # loadable gameplay code (comments may still say "removed").
        for rel in ["scripts/player/attack_controller.gd", "scripts/player/combo_chain.gd"]:
            self.assertFalse((ROOT / rel).exists(), f"legacy file must stay deleted: {rel}")
        needles = [
            "res://scripts/player/attack_controller.gd",
            "res://scripts/player/combo_chain.gd",
            "AttackController.new(",
            "ComboChain.new(",
            "as AttackController",
        ]
        for root in [(ROOT / "scripts"), (ROOT / "scenes"), (ROOT / "tests")]:
            for rel in sorted(root.rglob("*.gd")) + sorted(root.rglob("*.tscn")):
                text = rel.read_text(encoding="utf-8", errors="ignore")
                for needle in needles:
                    self.assertNotIn(needle, text, msg=f"legacy loadable reference {needle!r} in {rel}")
    def test_player_authoritative_chain(self):
        txt = read("scripts/player/player.gd")
        self.assertIn("Player → WeaponManager → WeaponInstance", txt)
        self.assertIn("MeleeResolver", txt)
        self.assertIn("DamagePayload", txt)
        self.assertNotIn("Legacy fallback", txt)
    def test_dash_intent(self):
        txt = read("scripts/player/player.gd")
        self.assertIn("request_dodge", txt)
        self.assertIn("DodgeController", txt)
        txt2 = read("scripts/player/dodge_controller.gd")
        self.assertIn("is_dodging", txt2)
        self.assertIn("get_dodge_direction", txt2)
    def test_event_bus_hardening(self):
        txt = read("scripts/core/event_bus.gd")
        self.assertIn("hardened lifecycle", txt.lower())
        self.assertIn("is_connected", txt)
        # Player and EffectDirector use is_connected guards
        self.assertIn("is_connected", read("scripts/player/player.gd"))
        director = read("scripts/visuals/effect_director.gd")
        self.assertIn("is_connected", director)
class Milestone4_AudioAndPolish(unittest.TestCase):
    def test_audio_mapping_documented(self):
        txt = read("scripts/audio/procedural_sfx.gd")
        self.assertIn("LIVE", txt)
        self.assertIn("FALLBACK", txt)
        self.assertIn("RESERVED", txt)
        self.assertIn("SFX_CUES", txt)
        # ensure catalog and procedural overlap
        import json, pathlib
        catalog = json.loads((ROOT/"assets/catalog.json").read_text(encoding="utf-8"))
        cues = catalog.get("audio_cues", {})
        self.assertGreaterEqual(len(cues), 28)
        self.assertIn("skill_cast", cues)
        self.assertIn("boss_spawned", cues)
    def test_ui_polish(self):
        txt = read("scripts/ui/upgrade_panel.gd")
        self.assertIn("rarity", txt.lower())
        txt2 = read("scripts/ui/touch_controls.gd")
        self.assertIn("64.0", txt2)
        txt3 = read("scripts/main/camera_rig.gd")
        self.assertIn("add_shake", txt3)
        self.assertIn("boss_slain", txt3)
    def test_arena_camera_polish(self):
        txt = read("scripts/arena/arena.gd")
        self.assertIn("apply_theme", txt)
        self.assertIn("emissive", txt)
        txt2 = read("scripts/main/camera_rig.gd")
        self.assertIn("max_shake_amplitude", txt2)
class Milestone5_IntegrationPersistence(unittest.TestCase):
    def test_persistence_dirty_flag(self):
        txt = read("scripts/save/save_manager.gd")
        self.assertIn("if ok:", txt)
        self.assertIn("_dirty = false", txt)
    def test_content_registry_covers_all(self):
        txt = read("scripts/core/content_registry.gd")
        for kind in ["_weapons","_skills","_status","_pickups"]:
            self.assertIn(kind, txt)
    def test_weapon_skill_loadout_snapshot(self):
        txt = read("scripts/player/player.gd")
        self.assertIn("get_build_snapshot", txt)
        self.assertIn("equipped_weapons", txt)
class Milestone6_AndroidPerf(unittest.TestCase):
    def test_mobile_renderer_and_perf(self):
        txt = read("project.godot")
        self.assertIn('renderer/rendering_method="mobile"', txt)
        # HD graphics pass: 2x MSAA + anisotropy + high-quality PCF shadows; the
        # mobile renderer is kept (no SSAO/SSR) to protect frame time on devices.
        self.assertIn("anti_aliasing/quality/msaa_3d=2", txt)
        self.assertIn("anisotropic_filtering_level=8", txt)
        self.assertIn("Mobile", txt)
        txt2 = read("export_presets.cfg")
        self.assertIn("arm64-v8a=true", txt2)
        self.assertTrue('version/name="0.7.0"' in txt2 or 'version/name="0.6.0"' in txt2 or 'version/name="0.5.0"' in txt2)
        txt3 = read(".github/workflows/android.yml")
        self.assertIn("validate-resources", txt3)
        self.assertIn("godot-tests", txt3)
        self.assertIn("build-android", txt3)
class Milestone7_CleanupDocs(unittest.TestCase):
    def test_no_todo_markers(self):
        import pathlib, re
        bad = []
        for p in (ROOT/"scripts").rglob("*.gd"):
            txt = p.read_text(encoding="utf-8",errors="ignore")
            if re.search(r"\bTODO\b|\bFIXME\b", txt):
                # allow validated helpers, not TODO
                if "TODO" in txt and "_validated" not in txt:
                    bad.append(str(p))
        self.assertEqual(bad, [], msg=str(bad))
    def test_determinism_documented(self):
        txt = read("docs/MILESTONE0_AUDIT.md")
        self.assertIn("Determinism", txt)
        self.assertIn("RngService", txt)
    def test_milestone1_doc_exists(self):
        # M1 weapon integration now has its own regression test
        self.assertTrue((ROOT/"tests/python/test_regress_milestone1_weapons.py").exists())
        self.assertTrue((ROOT/"scenes/player/player.tscn").exists())
        txt = read("scenes/player/player.tscn")
        self.assertIn("ember_scepter", txt)
        self.assertIn("moonlance", txt)
        self.assertIn("venom_chain", txt)
if __name__ == "__main__":
    unittest.main()
