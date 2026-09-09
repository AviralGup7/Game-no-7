"""Regression guards for the five playability/perf follow-ups:

1. Arena nav (LOS DDA, south-preferring flow, A* clearance tax, spawn/gate layout)
2. Autoload-safe lookups (no GameRoot/EventBus identifiers in arena/status)
3. Hot-path allocations (shared projectile tints, cached minimap arena)
4. EventBus bind/unbind on EffectDirector
5. Device QA sideload script exists
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class NavGridHardeningTests(unittest.TestCase):
    def test_los_uses_supercover_not_center_samples(self):
        src = read("scripts/arena/arena_nav_grid.gd")
        self.assertIn("Amanatides-Woo", src)
        self.assertNotIn("ceili(dist / (cell_size * 0.5))", src)
        self.assertIn("is_blocked_cell(Vector2i(x, z))", src)

    def test_flow_prefers_south_on_ties(self):
        src = read("scripts/arena/arena_nav_grid.gd")
        self.assertIn("Vector2i(0, 1), Vector2i(1, 1)", src)
        self.assertIn("float(n.y) * 10.0", src)

    def test_astar_taxes_wall_hugs(self):
        src = read("scripts/arena/arena_nav_grid.gd")
        self.assertIn("_cell_touches_blocked", src)
        self.assertIn("tax = 0.35", src)

    def test_ember_corners_clear_axis_spawns(self):
        src = read("scripts/arena/arena_obstacles.gd")
        self.assertIn("Vector3(8.0 * s, 0.0, 8.0 * s)", src)
        self.assertNotIn("Vector3(8.5 * s, 0.0, 8.5 * s)", src)

    def test_default_gate_towers_leave_throat(self):
        src = read("scripts/arena/arena_obstacles.gd")
        self.assertIn("Vector3(3.6 * s, 0.0, 0.0)", src)


class AutoloadPathLookupTests(unittest.TestCase):
    def test_arena_does_not_use_autoload_identifier(self):
        src = read("scripts/arena/arena.gd")
        self.assertNotIn("if GameRoot != null:", src)
        self.assertIn('get_node_or_null("/root/GameRoot")', src)
        self.assertIn("as GameRootService", src)

    def test_status_manager_looks_up_bus_by_path(self):
        src = read("scripts/status/status_manager.gd")
        self.assertIn("func _event_bus()", src)
        self.assertIn('tree.root.get_node_or_null(node_name)', src)
        self.assertNotIn("if EventBus != null:", src)

    def test_runner_boots_real_event_bus_node(self):
        src = read("tests/run_tests.gd")
        self.assertIn("_boot_project_autoloads", src)
        self.assertIn("res://scripts/core/event_bus.gd", src)


class HotPathTests(unittest.TestCase):
    def test_minimap_caches_arena(self):
        src = read("scripts/ui/minimap.gd")
        self.assertIn("var _cached_arena: Arena", src)
        self.assertIn("_cached_arena = _find_arena()", src)
        self.assertIn("is_instance_valid(_cached_arena)", src)

    def test_projectile_shares_two_materials(self):
        src = read("scripts/weapons/projectile.gd")
        self.assertIn("_shared_player_mat", src)
        self.assertIn("_shared_enemy_mat", src)


class EventBusLifecycleTests(unittest.TestCase):
    def test_event_bus_exposes_bind_unbind(self):
        src = read("scripts/core/event_bus.gd")
        self.assertIn("func bind(host: Node, sig: Signal, cb: Callable)", src)
        self.assertIn("func unbind(sig: Signal, cb: Callable)", src)

    def test_effect_director_unbinds_on_exit(self):
        src = read("scripts/visuals/effect_director.gd")
        self.assertIn("EventBus.bind(self", src)
        self.assertIn("func _exit_tree()", src)
        self.assertIn("EventBus.unbind", src)


class DeviceQaTests(unittest.TestCase):
    def test_device_script_and_doc_exist(self):
        self.assertTrue((ROOT / "scripts/device_qa.sh").is_file())
        self.assertTrue((ROOT / "docs/DEVICE_QA.md").is_file())
        sh = read("scripts/device_qa.sh")
        self.assertIn("adb", sh)
        self.assertIn("LastStandArena-debug.apk", sh)


if __name__ == "__main__":
    unittest.main()
