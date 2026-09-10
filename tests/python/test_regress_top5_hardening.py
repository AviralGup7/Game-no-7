"""Regression guards for the five playability/perf follow-ups:

1. Arena nav (LOS DDA, south-preferring flow, A* clearance tax, spawn/gate layout)
2. Autoload-safe lookups (no GameRoot/EventBus identifiers in arena/status)
3. Hot-path allocations (shared projectile tints, cached minimap arena)
4. EventBus bind/unbind on EffectDirector
5. Device QA sideload script exists
"""
from pathlib import Path
import math
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def obstacle_layout(arena_id: str) -> list[tuple[float, float, float, float]]:
    """A shipped arena's obstacles as the game will build them: (x, z, half_x, half_z) for
    every placement, mirrors expanded, in authoring order.

    Read out of the .tres rather than imported from GDScript, so this stays a *data* guard
    that runs without the engine -- and so the numbers it checks are the ones a designer
    edits, not a copy of them kept here.
    """
    text = read(f"data/arenas/{arena_id}.tres")
    layout = re.search(r"obstacle_layout = Array\[ArenaObstaclePlacement\]\(\[(.*?)\]\)", text, re.S)
    assert layout is not None, f"{arena_id}.tres authors no obstacle_layout"
    expansion = {"none": 1, "x": 2, "z": 2, "rot180": 2, "both": 4}
    out: list[tuple[float, float, float, float]] = []
    for rid in re.findall(r'SubResource\("([^"]+)"\)', layout.group(1)):
        block = re.search(r'\[sub_resource type="Resource" id="%s"\]\n(.*?)(?=\n\[|\Z)' % re.escape(rid),
                          text, re.S)
        assert block is not None, f"{arena_id}: obstacle placement {rid} is referenced but undefined"
        body = block.group(1)
        x, _y, z = (float(t) for t in re.search(r"position = Vector3\(([^)]*)\)", body).group(1).split(","))
        hx = float(re.search(r"half_size_x = ([\d.eE+-]+)", body).group(1))
        hz = float(re.search(r"half_size_z = ([\d.eE+-]+)", body).group(1))
        mirror_m = re.search(r'mirror = &"(\w+)"', body)
        mirror = mirror_m.group(1) if mirror_m else "none"
        points = [(x, z)]
        if mirror in ("x", "both", "rot180"):
            points.append((-x, z))
        if mirror in ("z", "both", "rot180"):
            points.append((x, -z))
        if mirror == "both":
            points.append((-x, -z))
        assert len(points) == expansion[mirror], f"{arena_id}/{rid}: mirror expansion disagrees with GDScript"
        out.extend((px, pz, hx, hz) for (px, pz) in points)
    return out



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
        """The authored Ember layout keeps a jitter-proof gap to the axis spawn markers.

        This used to grep `Vector3(8.0 * s, 0.0, 8.0 * s)` out of ArenaObstacles. The
        numbers moved into data (ArenaConfig.obstacle_layout), where they are now read
        exactly as the game reads them -- which makes the *guarantee* assertible instead of
        the expression that produced it. The history the old literal carried is preserved
        in the .tres and restated here: 8.5 sat each corner exactly 2.5 m from a +-11 spawn
        (foot 0.8 + jitter 1.2 + safety 0.5), i.e. zero margin.
        """
        placements = obstacle_layout("ember_crucible")
        self.assertGreaterEqual(len(placements), 8, f"expected the 8 expanded obstacles, got {len(placements)}")
        spawns = [(11.0, 0.0), (-11.0, 0.0), (0.0, 11.0), (0.0, -11.0)]
        for (px, pz, hx, hz) in placements:
            foot = max(hx, hz)
            for (sx, sz) in spawns:
                gap = math.hypot(px - sx, pz - sz)
                self.assertGreater(gap, foot + 1.2 + 0.5,
                                   f"ember obstacle at ({px}, {pz}) can be touched by spawn jitter at ({sx}, {sz})")
        radii = {abs(px) for (px, pz, _hx, _hz) in placements if abs(pz) < 0.01}
        self.assertEqual(radii, {8.0}, f"cardinal pillars must ring the forge at exactly 8.0 m, got {radii}")

    def test_default_gate_towers_leave_throat(self):
        """The Pit's twin rubble towers must leave a passable throat beside the obelisk."""
        placements = obstacle_layout("default_arena")
        gate = [(px, hx) for (px, pz, hx, _hz) in placements if abs(pz) < 0.01 and abs(px) < 5.0]
        self.assertEqual(len(gate), 2, f"expected the two gate blocks, got {gate}")
        inner = min(abs(px) - hx for (px, hx) in gate)
        self.assertGreater(inner, 1.5, f"gate throat is only {inner:.2f} m wide from the centre line")
        # The obelisk footprint (0.55 m) has to leave real space to walk through.
        self.assertGreater(inner - 0.55, 1.0, "the gate towers crowd the obelisk instead of flanking it")


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
