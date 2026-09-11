"""Regression guards for Aim 5: run teardown isolation.

GAME_OVER keeps WorldRoot so the summary camera still has an arena. Until
MAIN_MENU `_clear_world()` frees it, in-flight projectiles, magnet pickups,
VFX, hitstop and spatial Foley would keep simulating under the overlay.
These pins assert the drain + unbind actually happens at that boundary, and
that UI EventBus observers are left alone.

Static-source on purpose: the Python suite has no Godot binary. Behaviour
lives in tests/unit/test_run_isolation.gd (NODE).
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


ISOLATION = "scripts/core/run_isolation.gd"
MAIN = "scripts/main/main.gd"
PICKUPS = "scripts/pickups/pickup_manager.gd"
POOL = "scripts/weapons/projectile_pool.gd"
FX = "scripts/visuals/effect_director.gd"
HITSTOP = "scripts/combat/hitstop_manager.gd"
AUDIO = "scripts/audio/audio_manager.gd"
SPATIAL = "scripts/audio/spatial_voice_pool.gd"
PLAYER = "scripts/player/player.gd"
PLAYER_AUDIO = "scripts/player/player_audio.gd"
OBJECTIVE = "scripts/meta/objective_director.gd"
UI = "scripts/ui/ui_root.gd"
NUMBERS = "scripts/ui/damage_number_layer.gd"
RUNNER = "tests/run_tests.gd"


class GameOverKeepsWorldTests(unittest.TestCase):
    """GAME_OVER must drain pools without freeing WorldRoot."""

    def test_game_over_isolates_without_clearing_world(self) -> None:
        body = func_body(read(MAIN), "_on_state_changed")
        self.assertIn("GameRoot.State.GAME_OVER:", body)
        over = body.split("GameRoot.State.GAME_OVER:")[1]
        self.assertIn("_stop_run_waves()", over)
        self.assertIn("_isolate_run_pools()", over)
        self.assertNotIn("_clear_world()", over)

    def test_main_menu_still_clears_world(self) -> None:
        body = func_body(read(MAIN), "_on_state_changed")
        menu = body.split("GameRoot.State.MAIN_MENU:")[1].split("GameRoot.State.")[0]
        self.assertIn("_clear_world()", menu)

    def test_clear_world_isolates_then_frees(self) -> None:
        body = func_body(read(MAIN), "_clear_world")
        self.assertIn("_isolate_run_pools()", body)
        self.assertIn("remove_child(child)", body)
        self.assertIn("child.free()", body)
        self.assertLess(body.index("_isolate_run_pools()"), body.index("child.free()"))

    def test_stop_run_waves_is_still_waves_and_ai_only(self) -> None:
        body = func_body(read(MAIN), "_stop_run_waves")
        self.assertIn("_wave_manager.stop()", body)
        self.assertIn("deactivate_all()", body)
        self.assertNotIn("isolate_run", body)
        self.assertNotIn("free()", body)

    def test_isolate_run_pools_walks_groups_and_parks_audio(self) -> None:
        body = func_body(read(MAIN), "_isolate_run_pools")
        self.assertIn("RunIsolation.isolate_from(self)", body)
        self.assertIn("AudioManager.isolate_run()", body)


class IsolatorContractTests(unittest.TestCase):
    """RunIsolation is the single walker; it must not name autoload identifiers."""

    def test_isolator_has_no_autoload_identifiers(self) -> None:
        code = code_lines(read(ISOLATION))
        self.assertNotIn("EventBus.", code)
        self.assertNotIn("GameRoot.", code)
        self.assertNotIn("SaveManager", code)
        self.assertNotIn("ContentRegistry", code)
        # Path lookup, never the autoload identifier.
        self.assertNotRegex(code, r"(?<![\"/])AudioManager")
        self.assertIn('"/root/AudioManager"', read(ISOLATION))
        self.assertIn('"SpatialVoices"', read(ISOLATION))

    def test_isolator_calls_each_pool_isolate(self) -> None:
        txt = read(ISOLATION)
        for call in (
            "pool.isolate_run()",
            "pickups.isolate_run()",
            "fx.isolate_run()",
            "hit.isolate_run()",
            "obj.isolate_run()",
            "numbers.clear_all()",
            "player.isolate_run()",
            "spatial.isolate_run()",
        ):
            self.assertIn(call, txt, "missing %s" % call)

    def test_isolator_does_not_free_the_world(self) -> None:
        body = func_body(read(ISOLATION), "isolate_from")
        self.assertNotIn(".free()", body)
        self.assertNotIn("queue_free", body)

    def test_node_suite_registered(self) -> None:
        runner = read(RUNNER)
        self.assertIn("res://tests/unit/test_run_isolation.gd", runner)
        # NODE, not UNIT: the suite builds tree pools.
        unit = runner.split("const NODE_SUITES")[0]
        node = runner.split("const NODE_SUITES")[1].split("const INTEGRATION")[0]
        self.assertNotIn("test_run_isolation.gd", unit)
        self.assertIn("test_run_isolation.gd", node)


class PoolDrainApiTests(unittest.TestCase):
    """Each run-scoped pool exposes isolate_run and actually stops work."""

    def test_projectile_isolate_drains_and_refuses_fire(self) -> None:
        txt = read(POOL)
        self.assertIn("func isolate_run() -> void:", txt)
        body = func_body(txt, "isolate_run")
        self.assertIn("release_all()", body)
        self.assertIn("_isolated = true", body)
        fire = func_body(txt, "fire")
        self.assertIn("_isolated", fire)

    def test_pickup_switches_to_event_bindings(self) -> None:
        txt = read(PICKUPS)
        self.assertIn("var _bus := EventBindings.new()", txt)
        self.assertIn("_bus.bind(EventBus.enemy_killed, _on_enemy_killed)", txt)
        self.assertNotIn("EventBus.enemy_killed.connect(_on_enemy_killed)", txt)
        iso = func_body(txt, "isolate_run")
        self.assertIn("_bus.unbind_all()", iso)
        self.assertIn("purge_all()", iso)
        spawn = func_body(txt, "spawn_pickup")
        self.assertIn("_isolated", spawn)

    def test_effect_director_unbinds_while_staying_in_tree(self) -> None:
        txt = read(FX)
        self.assertIn("func _unbind_events() -> void:", txt)
        iso = func_body(txt, "isolate_run")
        self.assertIn("_unbind_events()", iso)
        self.assertIn("_hide_all()", iso)
        exit_body = func_body(txt, "_exit_tree")
        self.assertIn("_unbind_events()", exit_body)
        self.assertIn("func burst_at(", txt)
        self.assertIn("if _isolated:", func_body(txt, "burst_at"))
        self.assertIn("if _isolated:", func_body(txt, "ring_at"))

    def test_hitstop_isolate_restores_timescale(self) -> None:
        body = func_body(read(HITSTOP), "isolate_run")
        self.assertIn("reset_effects()", body)
        reset = func_body(read(HITSTOP), "reset_effects")
        self.assertIn("Engine.time_scale = 1.0", reset)

    def test_audio_isolate_parks_listener_and_leaves_ui_bank(self) -> None:
        body = func_body(read(AUDIO), "isolate_run")
        self.assertIn("bind_listener(null)", body)
        self.assertIn("_spatial.isolate_run()", body)
        self.assertNotIn("_ui_bank.stop_all()", body)
        self.assertNotIn("_ui_bank", body)

    def test_spatial_isolate_stops_world_voices(self) -> None:
        body = func_body(read(SPATIAL), "isolate_run")
        self.assertIn("set_listener(null)", body)
        self.assertIn("stop_all()", body)

    def test_player_unbinds_kill_feeds_without_hud(self) -> None:
        txt = read(PLAYER)
        self.assertIn("func isolate_run() -> void:", txt)
        self.assertIn("func _unbind_run_events() -> void:", txt)
        unbind = func_body(txt, "_unbind_run_events")
        self.assertIn("_on_enemy_kill_heal", unbind)
        self.assertIn("_on_enemy_kill_xp", unbind)
        iso = func_body(txt, "isolate_run")
        self.assertIn("_player_audio.isolate_run()", iso)
        # HUD lives on UiRoot; player isolate must not touch it.
        self.assertNotIn("player_health_changed", iso)

    def test_player_audio_unbinds_shot_sting(self) -> None:
        unbind = func_body(read(PLAYER_AUDIO), "_unbind_run_events")
        self.assertIn("projectile_fired", unbind)

    def test_objective_unbinds_collect_listeners(self) -> None:
        txt = read(OBJECTIVE)
        self.assertIn("var _bus := EventBindings.new()", txt)
        iso = func_body(txt, "isolate_run")
        self.assertIn("_bus.unbind_all()", iso)
        self.assertIn("_active = false", iso)

    def test_damage_numbers_join_the_group(self) -> None:
        ready = func_body(read(NUMBERS), "_ready")
        self.assertIn('add_to_group("damage_number_layer")', ready)


class HudListenersStayTests(unittest.TestCase):
    """UI EventBus observers must survive GAME_OVER isolation."""

    def test_ui_root_keeps_game_state_and_damage_observers(self) -> None:
        ui = read(UI)
        self.assertIn("EventBus.game_state_changed.connect(_on_state_changed)", ui)
        self.assertIn("EventBus.enemy_damaged.connect(_on_damage)", ui)
        self.assertIn("EventBus.settings_changed.connect(_apply_settings)", ui)
        self.assertNotIn("isolate_run", ui)
        self.assertNotIn("unbind_all", ui)

    def test_ui_still_clears_numbers_when_leaving_play(self) -> None:
        body = func_body(read(UI), "_show_screen")
        self.assertIn("_numbers.clear_all()", body)


if __name__ == "__main__":
    unittest.main()
