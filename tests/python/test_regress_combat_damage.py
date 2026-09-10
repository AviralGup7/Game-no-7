"""Regression: combat damage & hitstop — guards Batch1 area_damage, payload, pool, hitstop."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class CombatDamageTests(unittest.TestCase):
    def test_area_damage_tie_deterministic(self):
        txt=read("scripts/combat/area_damage.gd")
        self.assertIn("is_equal_approx(d, best_dist) and best == null",txt)
        self.assertIn("Strict < keeps candidate order stable on ties",txt)
    def test_damage_payload_deep_duplicate_and_timestamp(self):
        txt=read("scripts/combat/damage_payload.gd")
        self.assertIn("metadata.duplicate(true)",txt)
        self.assertIn("timestamp_msec = timestamp_msec",txt)
        self.assertIn("Preserve original timestamp",txt)
    def test_projectile_pool_emergency_fallback(self):
        txt=read("scripts/weapons/projectile_pool.gd")
        self.assertIn("config.duplicate(true)",txt)
        self.assertIn("emergency fallback",txt)
        self.assertIn("if p == null:",txt)
        self.assertIn("_make_projectile()",txt)
    def test_hitstop_restores_on_exit(self):
        txt=read("scripts/combat/hitstop_manager.gd")
        self.assertIn("func _exit_tree()",txt)
        self.assertIn("Engine.time_scale = 1.0",txt)
        self.assertIn("stale hitstop/slowmo never freezes",txt)
    def test_hitstop_stacks_with_max(self):
        txt=read("scripts/combat/hitstop_manager.gd")
        self.assertIn("_hitstop_left = maxf(_hitstop_left, duration)",txt)
        self.assertIn("MAX_HITSTOP_SECONDS",txt)
    def test_arena_hazards_stable_spike_key(self):
        """Field throttling must key on a stable identity and live on the hazard.

        The throttle used to be a per-victim string key in node metadata
        ("spike_cd_<hazard index>_<quantised position>"), because a hazard record was an
        untyped Dictionary whose own hash folded in volatile fields (timer, marker).
        Metadata is serialized with the scene and slow to touch (godot#79222), so the
        rebuild moved the table onto the typed HazardInstance, keyed by the victim's
        object id. What must NOT come back: any hazard record hashing, and any per-victim
        metadata write on the tick path.
        """
        hazards = read("scripts/arena/arena_hazards.gd")
        instance = read("scripts/arena/hazard_instance.gd")
        self.assertIn("var _victim_ready: Dictionary[int, float] = {}", instance)
        self.assertIn("func victim_ready(victim_id: int, now: float) -> bool:", instance)
        self.assertIn("var key := victim.get_instance_id()", hazards)
        self.assertIn("instance.stamp_victim(key, _game_time)", hazards)
        for text, name in ((hazards, "arena_hazards.gd"), (instance, "hazard_instance.gd")):
            self.assertNotIn("set_meta(", text, f"{name} must not touch victim metadata")
            self.assertNotIn("get_meta(", text, f"{name} must not read node metadata")
            self.assertNotIn(".hash()", text, f"{name} must not key on a Dictionary hash")
    def test_ranged_resolver_clamps_spread(self):
        txt=read("scripts/weapons/ranged_resolver.gd")
        self.assertIn("maxf(spread_degrees, 0.0)",txt)
        self.assertIn("clamped_spread",txt)
    def test_weapon_instance_crits_go_through_pity(self):
        """Player swings used to call RngService.chance directly, so authored
        CriticalSystem pity never fired. roll_crit must persist pity on the instance."""
        txt=read("scripts/weapons/weapon_instance.gd")
        self.assertIn("CriticalSystem.roll",txt)
        self.assertIn("_crit_pity",txt)
        self.assertIn("crit_seed_salt",txt)
    def test_melee_resolver_uses_hit_radius_protocol(self):
        txt=read("scripts/weapons/melee_resolver.gd")
        body=txt[txt.find("func _target_radius"):txt.find("func _target_radius")+400]
        self.assertIn("get_hit_radius()",body)
        self.assertNotIn("EnemyBase",body)
        self.assertNotIn("get_config()",body)
    def test_zero_damage_after_mitigation_is_blocked(self):
        txt=read("scripts/player/health_component.gd")
        self.assertIn("IGNORE_BLOCKED",txt)
        self.assertIn("if amount <= 0.0:",txt)
    def test_hitscan_adds_target_hit_radius(self):
        txt=read("scripts/weapons/ranged_resolver.gd")
        self.assertIn("radius_tolerance + maxf(damageable.get_hit_radius()",txt)
    def test_weapon_status_uses_damageable_seam(self):
        txt=read("scripts/weapons/weapon_manager.gd")
        self.assertIn("get_status_manager()",txt)
        self.assertIn("sm.apply_effects(",txt)
        self.assertNotIn("sm.call(",txt)
if __name__=="__main__": unittest.main()
