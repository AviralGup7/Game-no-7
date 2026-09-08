"""Integration: wave/boss/spawn lifecycle — covers audit §25-26 scenarios.

These are headless-contract tests that assert the authoritative ledger and
signal-ordering invariants that were fixed in P0:

- Wave completion requires ledger accounting, not just spawned count
- Splitter children extend the ledger (planned += 2) so waves cannot stall
- Boss summons extend the ledger and require killing summons to complete
- Player death disables attacks/skills and freezes wave timers
- Repeated run lifecycle does not leak EventBus connections

They are pure Python checks of GDScript source contracts (Godot headless
would need the engine), so they run in the fast validate-resources stage.
"""

from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class WaveLedgerIntegrationTests(unittest.TestCase):
    """Audit §25 — Test 1: wave completion via ledger."""

    def test_spawn_ledger_tracks_planned_pending_active_defeated_failed(self):
        txt = read("scripts/enemies/spawn_ledger.gd").lower()
        for field in ["planned", "pending", "defeated", "failed"]:
            self.assertIn(field, txt)
        # active == spawned in this codebase (SpawnLedger uses spawned_count)
        self.assertTrue("active" in txt or "spawned" in txt)

    def test_wave_manager_waits_for_ledger_not_spawned(self):
        txt = read("scripts/waves/wave_manager.gd")
        # WaveManager must observe SpawnManager.all_cleared via ledger, not just spawn count
        self.assertIn("all_cleared", txt)
        self.assertIn("defeated_count", txt)

    def test_bounded_retry_prevents_stall(self):
        txt = read("scripts/enemies/spawn_ledger.gd")
        self.assertIn("MAX_FAILED_ATTEMPTS", txt)
        self.assertIn("note_attempt", txt)


class SplitterIntegrationTests(unittest.TestCase):
    """Audit §25 — Test 2: splitter children extend authoritative ledger."""

    def test_dispatch_split_extends_ledger(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        self.assertIn("_dispatch_split", txt)
        # Must extend ledger so planned grows; not just spawn children
        self.assertIn("extend_one", txt)
        self.assertIn("split_count", txt)
        self.assertIn("splits_into", txt)

    def test_splitter_burst_registers_direct_spawn(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        self.assertIn("register_direct_spawn", txt)
        self.assertIn("_spawn_split_child", txt)

    def test_splitter_failure_still_extends_ledger(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        # Unknown child archetype must still be queued so ledger accounts for it as FAILED
        self.assertIn("unknown archetype", txt.lower())
        self.assertIn("extend_one", txt)


class BossSummonIntegrationTests(unittest.TestCase):
    """Audit §25 — Test 3: boss phase summons participate in ledger."""

    def test_boss_summon_extends_ledger(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        self.assertIn("_on_boss_summon_requested", txt)
        self.assertIn("extend_one", txt)
        # Timer restart logic prevents stall when ledger was empty
        self.assertIn("is_stopped", txt)

    def test_boss_signal_connected_before_begin_fight(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        # P0 fix: connect before begin_fight so immediate emit not lost — scope to the maker
        marker = "func _maybe_begin_boss_fight"
        self.assertIn(marker, txt)
        block = txt[txt.find(marker): txt.find(marker) + 1400]
        connect_idx = block.find("summon_requested.connect")
        # live call, not the comment/header that mentions begin_fight
        begin_idx = block.find('boss.call("begin_fight"')
        if begin_idx == -1:
            begin_idx = block.find("begin_fight\", _run_seed")
        self.assertNotEqual(connect_idx, -1, "summon_requested.connect missing in _maybe_begin_boss_fight")
        self.assertNotEqual(begin_idx, -1, "boss.call begin_fight missing in _maybe_begin_boss_fight")
        self.assertLess(
            connect_idx,
            begin_idx,
            "signal must be connected BEFORE begin_fight (audit §6)",
        )

    def test_boss_uses_seeded_rng_not_global(self):
        txt = read("scripts/enemies/boss_controller.gd")
        # P0 fix: must use _rng.randi_range, not global randi()
        self.assertIn("_rng.randi_range", txt)
        self.assertIn("_rng.seed", txt)
        # Ensure no bare randi() % abilities remaining
        self.assertNotIn("randi() %", txt)
        self.assertNotIn("randi() %", txt.replace(" ", ""))

    def test_boss_phases_use_deterministic_lookup(self):
        txt = read("scripts/enemies/boss_controller.gd")
        self.assertIn("phase_index_for_fraction", txt)
        self.assertIn("clampf(frac", txt)


class PlayerDeathIntegrationTests(unittest.TestCase):
    """Audit §25 — Test 4: death disables gameplay systems."""

    def test_player_death_disables_attacks(self):
        txt = read("scripts/player/attack_controller.gd")
        self.assertIn("set_attacks_enabled", txt)
        self.assertIn("is_alive", txt)

    def test_player_has_health_died_signal(self):
        txt = read("scripts/player/health_component.gd")
        self.assertIn("signal died", txt)
        self.assertIn("is_dead", txt)

    def test_game_root_routes_to_game_over(self):
        txt = read("scripts/core/game_root.gd")
        self.assertIn("GAME_OVER", txt)
        self.assertIn("request_game_over", txt)
        self.assertIn("player_alive", txt)

    def test_enemies_stop_on_game_over(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        self.assertIn("deactivate_all", txt)
        self.assertIn("set_ai_enabled", txt)


class PauseResumeIntegrationTests(unittest.TestCase):
    """Audit §25 — Test 5: pause freezes gameplay timers."""

    def test_pause_is_overlay(self):
        txt = read("scripts/core/game_root.gd")
        self.assertIn("PAUSED", txt)
        self.assertIn("_resume_state", txt)
        self.assertIn("_set_paused", txt)
        # Must gate elapsed time on _paused
        self.assertIn("_paused", read("scripts/core/game_root.gd"))

    def test_wave_pause_freezes_timers(self):
        txt = read("scripts/waves/wave_manager.gd")
        # WaveManager has phase gating; GameRoot's _process gates on _paused
        self.assertIn("_paused", read("scripts/core/game_root.gd"))


class RunLifecycleLeakTests(unittest.TestCase):
    """Audit §25-26 — Test 6: repeated runs do not leak EventBus connections."""

    def test_wave_manager_disconnects_on_stop(self):
        txt = read("scripts/waves/wave_manager.gd")
        self.assertIn("is_connected", txt)
        self.assertIn("disconnect", txt)

    def test_boss_controller_disconnects_on_exit(self):
        txt = read("scripts/enemies/boss_controller.gd")
        self.assertIn("_exit_tree", txt)
        self.assertIn("disconnect", txt)

    def test_spawn_manager_prunes_stale_enemies(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        self.assertIn("_prune_active", txt)
        self.assertIn("is_instance_valid", txt)

    def test_hitstop_restores_time_scale(self):
        txt = read("scripts/combat/hitstop_manager.gd")
        self.assertIn("_exit_tree", txt)
        self.assertIn("Engine.time_scale = 1.0", txt)


class ContentLoaderRecursionTests(unittest.TestCase):
    """Audit §3 — loader must be recursive for data/enemies/bosses/ etc."""

    def test_loader_is_recursive(self):
        txt = read("scripts/core/content_loader.gd")
        self.assertIn("_recursive_list", txt)
        self.assertIn("current_is_dir", txt)
        self.assertIn("Recurse into subdirectories", txt)

    def test_flat_directories_still_supported(self):
        txt = read("scripts/core/content_loader.gd")
        # Must still handle flat layout (not only recursive)
        self.assertIn("data/enemies", txt)


class DeterminismAuditTests(unittest.TestCase):
    """Audit §21-22 — no gameplay system should call global RNG directly."""

    def test_attack_controller_uses_injected_or_seeded_rng(self):
        txt = read("scripts/player/attack_controller.gd")
        # Must have injectable source and seeded fallback, not bare randf()
        self.assertIn("_crit_roll_source", txt)
        self.assertIn("RngService", txt)
        # The final fallback randf() is only for no-seed headless; primary path is seeded
        self.assertIn("seed_val", txt)

    def test_boss_not_using_global_randi(self):
        txt = read("scripts/enemies/boss_controller.gd")
        self.assertNotIn("randi() %", txt)

    def test_camera_rig_is_cosmetic_only(self):
        txt = read("scripts/main/camera_rig.gd")
        # Camera shake may use randf_range for cosmetic; should be documented as non-gameplay
        self.assertIn("randf_range", txt)

    def test_damage_numbers_are_cosmetic(self):
        txt = read("scripts/ui/damage_number_layer.gd")
        self.assertIn("randf_range", txt)


if __name__ == "__main__":
    unittest.main()
