"""Regression: prestige meta now changes play.

Guards the wiring that turns three previously-inert "tables of IDs" into real
gameplay:

  1. Prestige challenge TIERS scale the Challenge run (mutator count, score /
     currency payout, wave cap) instead of a fixed Gladius + 2 mutators.
  2. Cosmetics (banner_survivor / trail_ember / aura_legend / ...) attach to the
     player, arena, and HUD/summary rather than only unlocking in the save file.
  3. OBJECTIVE_DEFEND_POINT and OBJECTIVE_COLLECT are implemented as real modes
     with spawn queues, win/lose conditions, HUD progress, and a runtime director.
"""
from __future__ import annotations
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class ChallengeTierTests(unittest.TestCase):
    def test_prestige_exposes_tier_accessors(self):
        txt = read("scripts/meta/prestige.gd")
        for fn in (
            "challenge_tier_label",
            "challenge_tier_score_mult",
            "challenge_tier_currency_mult",
            "challenge_tier_mutator_count",
            "challenge_tier_waves",
        ):
            self.assertIn("func %s(" % fn, txt)

    def test_tiers_carry_currency_and_waves(self):
        txt = read("scripts/meta/prestige.gd")
        # Every tier row must now carry the new escalation fields.
        self.assertIn('"currency_mult"', txt)
        self.assertIn('"waves"', txt)
        # Last Stand is the harshest tier.
        self.assertIn('"Last Stand Challenge"', txt)

    def test_gamemode_reads_prestige_tier(self):
        txt = read("scripts/meta/game_mode.gd")
        for fn in (
            "scales_with_prestige",
            "challenge_mutators",
            "score_multiplier_for",
            "currency_multiplier_for",
            "max_waves_for",
            "is_victory_wave_for",
        ):
            self.assertIn("func %s(" % fn, txt)
        # The mutator SET is drawn from a pool by tier count, not a fixed pair.
        self.assertIn("CHALLENGE_MUTATOR_POOL", txt)
        self.assertIn("challenge_tier_mutator_count", txt)

    def test_wave_manager_uses_prestige_scaled_challenge(self):
        txt = read("scripts/waves/wave_manager.gd")
        self.assertIn("_prestige_rank()", txt)
        self.assertIn("GameMode.challenge_mutators(_run_mode(), _prestige_rank())", txt)
        self.assertIn("GameMode.is_victory_wave_for(_run_mode(), _current_wave, _prestige_rank())", txt)
        self.assertIn("GameMode.max_waves_for(mode_id, _prestige_rank())", txt)
        self.assertIn("GameMode.score_multiplier_for(_run_mode(), _prestige_rank())", txt)

    def test_scorekeeper_avoids_double_counting_challenge_rank(self):
        txt = read("scripts/core/run_scorekeeper.gd")
        self.assertIn("score_multiplier_for", txt)
        self.assertIn("currency_multiplier_for", txt)
        # Flat per-rank prestige bonus only applies to modes that don't scale.
        self.assertIn("not GameMode.scales_with_prestige(_run.mode_id)", txt)


class CosmeticApplicationTests(unittest.TestCase):
    def test_cosmetics_catalog_exists(self):
        txt = read("scripts/meta/cosmetics.gd")
        self.assertIn("class_name Cosmetics", txt)
        for cid in ("banner_survivor", "trail_ember", "aura_legend", "trail_frost", "banner_last_stand"):
            self.assertIn(cid, txt)
        for fn in ("active_trail", "active_aura", "active_title", "active_banners"):
            self.assertIn("func %s(" % fn, txt)

    def test_player_cosmetics_node_attaches_visuals(self):
        txt = read("scripts/visuals/player_cosmetics.gd")
        self.assertIn("class_name PlayerCosmetics", txt)
        self.assertIn("GPUParticles3D", txt)  # real particle trail
        self.assertIn("Cosmetics.active_trail", txt)
        self.assertIn("Cosmetics.active_aura", txt)

    def test_main_applies_player_cosmetics_from_save(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("_apply_player_cosmetics", txt)
        self.assertIn("SaveManager.get_unlocked_cosmetics()", txt)
        self.assertIn("PlayerCosmetics.new()", txt)

    def test_arena_decorator_hangs_prestige_banners(self):
        txt = read("scripts/arena/arena_decorator.gd")
        self.assertIn("func apply_prestige_banners(", txt)
        self.assertIn("Cosmetics.active_banners", txt)
        main = read("scripts/main/main.gd")
        self.assertIn("decorator.apply_prestige_banners(", main)

    def test_summary_shows_prestige_identity(self):
        txt = read("scripts/ui/run_summary_panel.gd")
        self.assertIn("_prestige_identity_line", txt)
        self.assertIn("Cosmetics.active_title", txt)


class ObjectiveModeTests(unittest.TestCase):
    def test_defend_and_collect_modes_defined(self):
        txt = read("scripts/meta/game_mode.gd")
        self.assertIn("MODE_DEFEND", txt)
        self.assertIn("MODE_COLLECT", txt)
        self.assertIn("OBJECTIVE_DEFEND_POINT", txt)
        self.assertIn("OBJECTIVE_COLLECT", txt)
        # Both objectives now have spawn queues (endless until the win condition).
        self.assertIn("_defend_queue", txt)
        self.assertIn("_collect_queue", txt)
        self.assertIn("func collect_target(", txt)

    def test_objective_label_covers_new_objectives(self):
        txt = read("scripts/meta/game_mode.gd")
        section = txt.split("func objective_label")[1].split("func ")[0]
        self.assertIn("OBJECTIVE_DEFEND_POINT", section)
        self.assertIn("OBJECTIVE_COLLECT", section)

    def test_objective_director_runtime(self):
        txt = read("scripts/meta/objective_director.gd")
        self.assertIn("class_name ObjectiveDirector", txt)
        # Defend: beacon drain / repair / clock win, beacon-death loss.
        self.assertIn("_beacon_hp", txt)
        self.assertIn("_enemies_near_beacon", txt)
        self.assertIn('_resolve(false,', txt)
        self.assertIn('_resolve(true,', txt)
        # Collect: relic drops on kills + banking against a quota.
        self.assertIn("relic_shard", txt)
        self.assertIn("_relics_banked", txt)
        self.assertIn("_relic_target", txt)

    def test_objective_resolution_routes_through_gameroot(self):
        eb = read("scripts/core/event_bus.gd")
        self.assertIn("signal objective_resolved(", eb)
        self.assertIn("signal objective_progress(", eb)
        gr = read("scripts/core/game_root.gd")
        self.assertIn("_on_objective_resolved", gr)
        self.assertIn("_declare_victory()", gr)

    def test_main_spawns_objective_director(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("ObjectiveDirector.new()", txt)
        self.assertIn("objectives.configure(", txt)

    def test_hud_shows_objective_progress(self):
        txt = read("scripts/ui/game_hud.gd")
        self.assertIn("EventBus.objective_progress", txt)
        self.assertIn("func set_objective(", txt)

    def test_relic_pickup_registered(self):
        # Relic config exists, is a score pickup, and never enters normal drop tables.
        cfg = read("data/pickups/relic_shard.tres")
        self.assertIn('pickup_id = &"relic_shard"', cfg)
        self.assertIn('effect = &"score"', cfg)
        self.assertIn("drop_weight = 0.0", cfg)
        catalog = read("assets/catalog.json")
        self.assertIn('"relic_shard"', catalog)


if __name__ == "__main__":
    unittest.main()
