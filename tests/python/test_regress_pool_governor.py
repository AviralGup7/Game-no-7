"""Regression guards for Aim 6: governor budgets on run pools.

The monitor already scaled particles, damage numbers and simultaneous
enemies. Projectiles, pickups, VFX bursts/rings and spatial voices kept
their authored ceilings on a LOW phone. These pins assert the per-tier
caps exist, that PoolGovernor pushes them onto the live groups, and that
ProjectilePool's live cap wins over leftover idle slots.

Combat damage / pierce / speed are not scaled here.
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
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if " #" in line:
            line = line.split(" #", 1)[0]
        out.append(line)
    return "\n".join(out)


def func_body(text: str, name: str) -> str:
    m = re.search(
        r"^(?:static )?func %s\(.*?\).*?:\n(.*?)(?=^(?:static )?func |\Z)" % re.escape(name),
        text,
        re.S | re.M,
    )
    assert m is not None, "function %s not found" % name
    return m.group(1)


MONITOR = "scripts/utilities/performance_monitor.gd"
GOVERNOR = "scripts/utilities/pool_governor.gd"
MAIN = "scripts/main/main.gd"
UI = "scripts/ui/ui_root.gd"
POOL = "scripts/weapons/projectile_pool.gd"
PICKUPS = "scripts/pickups/pickup_manager.gd"
FX = "scripts/visuals/effect_director.gd"
SPATIAL = "scripts/audio/spatial_voice_pool.gd"
AUDIO = "scripts/audio/audio_manager.gd"
RUNNER = "tests/run_tests.gd"


class BudgetTableTests(unittest.TestCase):
    """Every new cap is a real method on PerformanceMonitor, monotone, bounded."""

    def test_monitor_exposes_the_new_caps(self) -> None:
        txt = read(MONITOR)
        for name in (
            "max_projectiles",
            "max_pickups",
            "max_vfx_bursts",
            "max_vfx_rings",
            "max_spatial_voices",
            "pool_budgets",
        ):
            self.assertIn("func %s(" % name, txt)

    def test_pool_budgets_dictionary_is_complete(self) -> None:
        body = func_body(read(MONITOR), "pool_budgets")
        for key in (
            '"projectiles"',
            '"pickups"',
            '"vfx_bursts"',
            '"vfx_rings"',
            '"spatial_voices"',
            '"damage_numbers"',
            '"enemies"',
        ):
            self.assertIn(key, body)

    def test_ultra_is_the_physical_ceiling(self) -> None:
        txt = read(MONITOR)
        proj = func_body(txt, "max_projectiles")
        self.assertIn("return 48", proj)
        self.assertIn("return 12", proj)
        pick = func_body(txt, "max_pickups")
        self.assertIn("return 24", pick)
        self.assertIn("return 8", pick)
        bursts = func_body(txt, "max_vfx_bursts")
        self.assertIn("return 10", bursts)
        self.assertIn("return 4", bursts)
        rings = func_body(txt, "max_vfx_rings")
        self.assertIn("return 14", rings)
        self.assertIn("return 5", rings)
        voices = func_body(txt, "max_spatial_voices")
        self.assertIn("return 16", voices)
        self.assertIn("return 4", voices)

    def test_debug_snapshot_carries_caps(self) -> None:
        body = func_body(read(MONITOR), "get_debug_snapshot")
        for key in (
            '"max_projectiles"',
            '"max_pickups"',
            '"max_vfx_bursts"',
            '"max_vfx_rings"',
            '"max_spatial_voices"',
        ):
            self.assertIn(key, body)

    def test_monitor_stays_free_of_autoload_identifiers(self) -> None:
        code = code_lines(read(MONITOR))
        self.assertNotIn("SaveManager", code)
        self.assertNotIn("\nEventBus", code)
        self.assertNotIn(".has_method(", code)
        self.assertNotIn('.call("', code)


class GovernorPushTests(unittest.TestCase):
    """PoolGovernor.apply is the single pusher; Main and UiRoot both call it."""

    def test_governor_has_no_autoload_identifiers(self) -> None:
        code = code_lines(read(GOVERNOR))
        self.assertNotIn("EventBus.", code)
        self.assertNotIn("GameRoot.", code)
        self.assertNotIn("SaveManager", code)
        self.assertNotRegex(code, r"(?<![\"/])AudioManager")
        self.assertIn("RunIsolation.AUDIO_PATH", read(GOVERNOR))
        self.assertIn("RunIsolation.SPATIAL_CHILD", read(GOVERNOR))

    def test_apply_pushes_every_pool(self) -> None:
        txt = read(GOVERNOR)
        self.assertIn("pool.apply_budget(cap)", txt)
        self.assertIn("pickups.apply_budget(cap)", txt)
        self.assertIn("fx.apply_budget(burst_cap, ring_cap)", txt)
        self.assertIn("numbers.set_max_live(cap)", txt)
        self.assertIn("spatial.apply_budget(voice_cap)", txt)

    def test_main_applies_on_create_and_tier_change(self) -> None:
        main = read(MAIN)
        self.assertIn("_apply_pool_budgets(perf)", main)
        self.assertIn("perf.quality_tier_changed.connect(_on_perf_tier_changed)", main)
        apply = func_body(main, "_apply_pool_budgets")
        self.assertIn("PoolGovernor.apply(perf, self)", apply)
        tick = func_body(main, "_on_perf_tier_changed")
        self.assertIn("_apply_pool_budgets()", tick)

    def test_ui_root_applies_on_auto_tier_change(self) -> None:
        body = func_body(read(UI), "_on_monitor_tier_changed")
        self.assertIn("set_max_live(monitor.max_damage_numbers())", body)
        self.assertIn("PoolGovernor.apply(monitor, self)", body)

    def test_unit_suite_registered_without_autoload_ids(self) -> None:
        runner = read(RUNNER)
        self.assertIn("res://tests/unit/test_pool_governor.gd", runner)
        unit = runner.split("const NODE_SUITES")[0]
        self.assertIn("test_pool_governor.gd", unit)
        suite = read("tests/unit/test_pool_governor.gd")
        self.assertNotIn("EventBus", suite)
        self.assertNotIn("GameRoot", suite)
        self.assertNotIn("AudioManager", suite)
        self.assertNotIn("SaveManager", suite)
        self.assertNotIn("ContentRegistry", suite)


class LiveCapTests(unittest.TestCase):
    """A leftover idle list must not defeat the governor cap."""

    def test_projectile_obtain_respects_live_cap_before_idle(self) -> None:
        obtain = func_body(read(POOL), "_obtain")
        self.assertIn("live_cap()", obtain)
        cap_idx = obtain.index("live_cap()")
        idle_idx = obtain.index("_idle.pop_back()")
        self.assertLess(cap_idx, idle_idx, "cap recycle must beat idle leftover")
        self.assertIn("_active.size() >= cap", obtain)

    def test_projectile_apply_budget_trims_active(self) -> None:
        body = func_body(read(POOL), "apply_budget")
        self.assertIn("_live_cap = clampi(cap, 1, maxi(pool_size, 1))", body)
        self.assertIn("while _active.size() > live_cap()", body)
        self.assertIn("pool_reset()", body)

    def test_pickup_apply_budget_trims_live(self) -> None:
        body = func_body(read(PICKUPS), "apply_budget")
        self.assertIn("max_live_pickups = clampi(cap, 1, 48)", body)
        self.assertIn("while _live.size() > max_live_pickups", body)

    def test_effect_director_keeps_physical_ceiling_pin(self) -> None:
        claim = read(FX).split("func _claim_burst(")[1].split("func _claim_ring(")[0]
        self.assertIn("_bursts.size() < MAX_BURSTS", claim)
        self.assertIn("_burst_cap", claim)
        ring = read(FX).split("func _claim_ring(")[1].split("func _make_burst_template(")[0]
        self.assertIn("_ring_pool.size() < MAX_RINGS", ring)
        self.assertIn("_ring_cap", ring)

    def test_spatial_drops_when_active_at_cap(self) -> None:
        play_at = func_body(read(SPATIAL), "play_at")
        self.assertIn("active_count() >= _voice_cap", play_at)
        play_on = func_body(read(SPATIAL), "play_on")
        self.assertIn("active_count() >= _voice_cap", play_on)
        self.assertIn("func apply_budget(cap: int) -> void:", read(SPATIAL))

    def test_audio_manager_forwards_spatial_budget(self) -> None:
        body = func_body(read(AUDIO), "set_spatial_budget")
        self.assertIn("_spatial.apply_budget(cap)", body)

    def test_combat_numbers_are_not_retuned(self) -> None:
        """Governor budgets must not sneak into damage / pierce / speed."""
        mon = read(MONITOR)
        self.assertNotIn("base_damage", mon)
        self.assertNotIn("pierce", mon)
        self.assertNotIn("projectile_speed", mon)
        gov = read(GOVERNOR)
        self.assertNotIn("base_damage", gov)
        self.assertNotIn("apply_damage", gov)


class CapsAreMonotonicSourceTests(unittest.TestCase):
    """The helper the NODE suite calls must actually compare descending tiers."""

    def test_monotonic_helper_walks_ultra_to_low(self) -> None:
        body = func_body(read(GOVERNOR), "caps_are_monotonic")
        self.assertIn("TIER_ULTRA", body)
        self.assertIn("TIER_LOW", body)
        self.assertIn("pool_budgets()", body)
        self.assertIn("value > int(prev[key])", body)

    def test_bounded_helper_uses_literals_not_autoload_scripts(self) -> None:
        """Keep PoolGovernor loadable from a unit file: no EffectDirector type."""
        body = func_body(read(GOVERNOR), "caps_are_bounded")
        self.assertNotIn("EffectDirector", body)
        self.assertNotIn("SpatialVoicePool", body)
        self.assertIn("int(b[\"vfx_bursts\"]) > 10", body)
        self.assertIn("int(b[\"spatial_voices\"]) > 16", body)


if __name__ == "__main__":
    unittest.main()
