"""Station Zero budget single-sourcing + flow-field rebuild guard pins.

scripts/campaign/campaign_budgets.gd is the ONE typed home for every campaign
performance budget (18 active enemies, 2 spawns per 0.3 s tick, 3 visible
district batches, the 6,000-expansion A* cap, the 12 m route refresh, the
40,960-cell / 1,024 m nav limits, plus the streaming radii they justify).
Every runtime copy is an alias of that file and tool/validate_campaign.py
mirrors it; these tests fail if any copy drifts from the single source.

The second class pins the audit-#6 invariant textually: the combat flow field
is rebuilt ONLY behind a player-cell / nav-revision guard in the streaming
tick, plus the one spawn-event rebuild — no unconditional per-tick rebuild.
"""
import math
import re
import unittest
from pathlib import Path

from tool import validate_campaign as campaign

ROOT = Path(__file__).resolve().parents[2]

BUDGET_PATH = "scripts/campaign/campaign_budgets.gd"
CONST_RE = re.compile(r"^\s*const\s+([A-Z0-9_]+)\s*:=\s*([0-9]+(?:\.[0-9]+)?)\s*$", re.M)


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def parse_budgets():
    budgets = {}
    for name, value in CONST_RE.findall(source(BUDGET_PATH)):
        budgets[name] = float(value) if "." in value else int(value)
    return budgets


EXPECTED_BUDGETS = {
    "MAX_ACTIVE_ENEMIES": 18,
    "SPAWNS_PER_TICK": 2,
    "STREAM_TICK_SECONDS": 0.3,
    "MAX_VISIBLE_DISTRICTS": 3,
    "ASTAR_EXPANSION_LIMIT": 6000,
    "ROUTE_REFRESH_DISTANCE": 12.0,
    "WORLD_EXTENT_LIMIT": 1024.0,
    "WORLD_CELL_LIMIT": 40960,
    "FLOW_FIELD_RADIUS": 128.0,
    "SPAWN_DISTANCE": 70.0,
    "DESPAWN_DISTANCE": 90.0,
    "MAX_FLOOR_REGIONS": 64,
    "MAX_TABLE_ROWS": 512,
}

# Budget constants whose literal copies must no longer exist anywhere in the
# consumers: an alias is the only legal runtime copy.
CONSUMER_ALIASES = {
    "scripts/campaign/campaign_definition.gd": [
        ("WORLD_EXTENT_LIMIT", "CampaignBudgets.WORLD_EXTENT_LIMIT"),
        ("MAX_FLOOR_REGIONS", "CampaignBudgets.MAX_FLOOR_REGIONS"),
        ("MAX_TABLE_ROWS", "CampaignBudgets.MAX_TABLE_ROWS"),
    ],
    "scripts/arena/arena_nav_grid.gd": [
        ("WORLD_EXTENT_LIMIT", "CampaignBudgets.WORLD_EXTENT_LIMIT"),
        ("WORLD_CELL_LIMIT", "CampaignBudgets.WORLD_CELL_LIMIT"),
        ("ASTAR_EXPANSION_LIMIT", "CampaignBudgets.ASTAR_EXPANSION_LIMIT"),
    ],
    "scripts/campaign/campaign_encounters.gd": [
        ("TICK", "CampaignBudgets.STREAM_TICK_SECONDS"),
        ("DESPAWN_DISTANCE", "CampaignBudgets.DESPAWN_DISTANCE"),
        ("SPAWN_DISTANCE", "CampaignBudgets.SPAWN_DISTANCE"),
        ("SPAWNS_PER_TICK", "CampaignBudgets.SPAWNS_PER_TICK"),
        ("FLOW_RADIUS", "CampaignBudgets.FLOW_FIELD_RADIUS"),
    ],
    "scripts/campaign/campaign_director.gd": [
        ("ROUTE_REFRESH_DISTANCE", "CampaignBudgets.ROUTE_REFRESH_DISTANCE"),
    ],
}


class CampaignBudgetSingleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.budgets = parse_budgets()

    def test_single_source_defines_exactly_the_expected_budgets(self):
        # The key set is pinned too: adding or removing a budget is a
        # deliberate, reviewed change to BOTH files.
        self.assertEqual(self.budgets, EXPECTED_BUDGETS)

    def test_offline_validator_mirrors_the_single_source(self):
        mirrors = {
            "MAX_ACTIVE_ENEMIES": campaign.MAX_ACTIVE_ENEMIES,
            "MAX_VISIBLE_DISTRICTS": campaign.MAX_VISIBLE_DISTRICTS,
            "MAX_FLOOR_REGIONS": campaign.MAX_FLOOR_REGIONS,
            "MAX_TABLE_ROWS": campaign.MAX_TABLE_ROWS,
        }
        for key, mirror in mirrors.items():
            with self.subTest(budget=key):
                self.assertEqual(mirror, self.budgets[key])
        self.assertEqual(campaign.MAX_WORLD_EXTENT, self.budgets["WORLD_EXTENT_LIMIT"])
        self.assertEqual(campaign.MAX_NAV_CELLS, self.budgets["WORLD_CELL_LIMIT"])

    def test_every_runtime_copy_aliases_the_single_source(self):
        for path, aliases in CONSUMER_ALIASES.items():
            text = source(path)
            for name, single_source in aliases:
                with self.subTest(script=path, const=name):
                    self.assertIn(f"const {name} := {single_source}", text)

    def test_definition_clamps_authored_caps_at_the_single_source(self):
        definition = source("scripts/campaign/campaign_definition.gd")
        self.assertIn("var max_active_enemies := CampaignBudgets.MAX_ACTIVE_ENEMIES", definition)
        self.assertIn("var max_visible_sectors := CampaignBudgets.MAX_VISIBLE_DISTRICTS", definition)
        self.assertIn(
            'clampi(int(raw.get("max_active_enemies", CampaignBudgets.MAX_ACTIVE_ENEMIES)), '
            "1, CampaignBudgets.MAX_ACTIVE_ENEMIES)", definition)
        self.assertIn(
            'clampi(int(raw.get("max_visible_sectors", CampaignBudgets.MAX_VISIBLE_DISTRICTS)), '
            "1, CampaignBudgets.MAX_VISIBLE_DISTRICTS)", definition)

    def test_no_literal_budget_copies_remain_in_consumers(self):
        for path, aliases in CONSUMER_ALIASES.items():
            text = source(path)
            for name, _single_source in aliases:
                with self.subTest(script=path, const=name):
                    self.assertNotRegex(
                        text, rf"const\s+{name}\s*:=\s*[0-9]",
                        f"{path} hard-codes {name} instead of aliasing CampaignBudgets")

    def test_route_refresh_guard_uses_the_budget_not_a_literal(self):
        director = source("scripts/campaign/campaign_director.gd")
        self.assertIn(
            "_route_origin.distance_to(player.global_position) < ROUTE_REFRESH_DISTANCE",
            director)
        # The drifted literal that doubled the A* refresh rate (declared 12 m
        # budget, guard compared against 6 m).
        self.assertNotIn("distance_to(player.global_position) < 6.0", director)

    def test_authored_world_stays_inside_the_budgets(self):
        data = campaign.load()
        self.assertLessEqual(data["max_active_enemies"], self.budgets["MAX_ACTIVE_ENEMIES"])
        self.assertLessEqual(data["max_visible_sectors"], self.budgets["MAX_VISIBLE_DISTRICTS"])
        x, z, w, d = data["bounds"]
        self.assertLessEqual(w, self.budgets["WORLD_EXTENT_LIMIT"])
        self.assertLessEqual(d, self.budgets["WORLD_EXTENT_LIMIT"])
        cells = math.ceil(w / campaign.CELL) * math.ceil(d / campaign.CELL)
        self.assertLessEqual(cells, self.budgets["WORLD_CELL_LIMIT"])
        # The combat flow window must cover every actor that can be live.
        self.assertGreaterEqual(self.budgets["FLOW_FIELD_RADIUS"],
                                self.budgets["DESPAWN_DISTANCE"])


class FlowFieldRebuildGuardTests(unittest.TestCase):
    """Textual invariant: no unconditional per-tick flow-field rebuild."""

    @classmethod
    def setUpClass(cls):
        cls.encounters = source("scripts/campaign/campaign_encounters.gd")
        cls.grid = source("scripts/arena/arena_nav_grid.gd")
        cls.stream = cls.encounters.split("func stream_nearby", 1)[1].split("\n\nfunc ", 1)[0]
        cls.spawn = cls.encounters.split("func _spawn", 1)[1].split("\n\nfunc ", 1)[0]

    def test_stream_tick_rebuild_is_cell_and_revision_guarded(self):
        guard = ("if not _active.is_empty() and "
                 "(player_cell != _flow_cell or nav_revision != _flow_revision):")
        self.assertIn(guard, self.stream)
        self.assertIn("var nav_revision := _world.nav.get_revision()", self.stream)
        rebuild = "_world.nav.rebuild_flow_field(at, FLOW_RADIUS)"
        self.assertIn(rebuild, self.stream)
        # The rebuild sits INSIDE the guard, and the cache is refreshed with it.
        self.assertLess(self.stream.index(guard), self.stream.index(rebuild))
        tail = self.stream[self.stream.index(rebuild):]
        self.assertIn("_flow_cell = player_cell", tail)
        self.assertIn("_flow_revision = nav_revision", tail)

    def test_stream_tick_has_exactly_one_guarded_rebuild_site(self):
        self.assertEqual(self.stream.count("rebuild_flow_field("), 1)
        # The whole streaming script has exactly two rebuild sites: the guarded
        # tick rebuild and the spawn-event rebuild. Nothing else may call it.
        self.assertEqual(self.encounters.count("rebuild_flow_field("), 2)

    def test_spawn_event_rebuilds_and_relies_on_the_same_cell_noop(self):
        self.assertIn("_world.nav.rebuild_flow_field(_player.global_position, FLOW_RADIUS)",
                      self.spawn)

    def test_nav_grid_keeps_the_same_cell_same_radius_noop(self):
        # This guard is what makes a spawn in the same tick as a player-cell
        # change free: the second rebuild call returns before any Dijkstra.
        self.assertIn(
            "if tc == _flow_target and is_equal_approx(radius, _flow_radius):",
            self.grid)

    def test_nav_grid_exposes_a_blocker_mask_revision(self):
        self.assertIn("func get_revision() -> int:", self.grid)
        # One bump per successful build: arena build() and campaign
        # build_world().
        self.assertEqual(self.grid.count("_revision += 1"), 2)


if __name__ == "__main__":
    unittest.main()
