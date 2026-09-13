"""Authored campaign/topology and shipping-entry contracts; no fake engine claims."""
import re
from copy import deepcopy
import math
from pathlib import Path
import tempfile
import unittest

from tool import validate_campaign as campaign

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def report_district_area(data):
    return sum(s["rect"][2] * s["rect"][3] for s in data["sectors"])


def _crosses(edge, seam, horizontal_connector):
    """True when a perimeter wall module seals this connector seam point.

    Seam points are sampled 4 m off the 8 m module centre line so a wall whose
    segment boundary lands exactly on the centre is still detected.
    """
    (ax, az), (bx, bz) = edge
    if horizontal_connector:
        return ax == bx == seam[0] and min(az, bz) < seam[1] < max(az, bz)
    return az == bz == seam[1] and min(ax, bx) < seam[0] < max(ax, bx)


class CampaignRuntimeBudgetTests(unittest.TestCase):
    """The offline validator and the GDScript loader must agree on budgets.

    The station grew to 864 x 672 m, so the world caps now live in three places
    (validator, nav grid, definition). These checks keep them from drifting,
    and keep actor clamps tied to the authored bounds instead of a literal.
    """

    def test_world_budget_constants_match_the_runtime(self):
        grid = source("scripts/arena/arena_nav_grid.gd")
        definition = source("scripts/campaign/campaign_definition.gd")
        for text in (grid, definition):
            self.assertIn(f"const WORLD_EXTENT_LIMIT := {campaign.MAX_WORLD_EXTENT}.0", text)
        self.assertIn(f"const WORLD_CELL_LIMIT := {campaign.MAX_NAV_CELLS}", grid)
        # The loader row budgets are enforced offline too.
        self.assertIn(f"raw.floors.size() > {campaign.MAX_FLOOR_REGIONS}", definition)
        self.assertIn(f"value.size() > {campaign.MAX_TABLE_ROWS}", definition)

    def test_expanded_world_still_fits_the_runtime_budgets(self):
        data = campaign.load()
        self.assertLessEqual(len(data["floors"]), campaign.MAX_FLOOR_REGIONS)
        for key in ("sectors", "props", "interactions", "encounters", "missions"):
            self.assertLessEqual(len(data[key]), campaign.MAX_TABLE_ROWS, key)
        x, z, w, d = data["bounds"]
        self.assertLessEqual(math.ceil(w / campaign.CELL) * math.ceil(d / campaign.CELL),
                             campaign.MAX_NAV_CELLS)

    def test_loader_row_budgets_are_enforced_offline(self):
        data = deepcopy(campaign.load())
        data["floors"] = data["floors"] + [[0, 0, 8, 8]] * (campaign.MAX_FLOOR_REGIONS + 1)
        with self.assertRaisesRegex(campaign.CampaignError, "loader budget"):
            campaign.validate(data)

    def test_actor_clamps_follow_the_authored_world(self):
        game = source("scripts/campaign/campaign_game.gd")
        encounters = source("scripts/campaign/campaign_encounters.gd")
        self.assertIn("player.set_bounds(definition.containment_half())", game)
        self.assertIn("actor.set_bounds(_definition.containment_half())", encounters)
        for name, text in (("campaign_game.gd", game), ("campaign_encounters.gd", encounters)):
            with self.subTest(script=name):
                self.assertNotRegex(text, r"set_bounds\(\s*[0-9]",
                                    f"{name} hard-codes a clamp radius")

    def test_service_causeways_are_distance_culled_too(self):
        world = source("scripts/campaign/campaign_world.gd")
        self.assertIn("_connectors.append(", world)
        self.assertIn("root.visible = near.distance_to(Vector2(at.x, at.z)) < 105.0", world)
        # The three-batch Android budget stays measured over districts only.
        self.assertIn("_visible_ids.append(String(entry.id))", world)
        self.assertIn('"visible_districts": _visible_ids.duplicate()', world)

    def test_campaign_combat_uses_a_bounded_flow_field(self):
        grid = source("scripts/arena/arena_nav_grid.gd")
        encounters = source("scripts/campaign/campaign_encounters.gd")
        self.assertIn("func rebuild_flow_field(target_pos: Vector3, radius: float = 0.0)", grid)
        self.assertRegex(encounters, r"rebuild_flow_field\(\w+, FLOW_RADIUS\)")
        self.assertRegex(encounters, r"const FLOW_RADIUS := (\d+)\.0")
        radius = float(re.search(r"const FLOW_RADIUS := (\d+)\.0", encounters).group(1))
        # Every actor that can be live sits inside the window (spawn 70 / despawn 90 m).
        self.assertGreaterEqual(radius, 90.0)


class CampaignTopologyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.authored = campaign.load()
        cls.graph = campaign.Topology(cls.authored)

    def test_all_authored_content_is_valid_and_connected(self):
        report = campaign.validate(self.authored)
        self.assertEqual(report["districts"], 12)
        self.assertEqual(report["missions"], 13)
        self.assertEqual(report["authored_enemies"], 96)
        self.assertEqual(report["navigation_cells"], 36288)
        self.assertEqual(report["reachable_walkable_cells"], 13440)

    def test_expanded_footprint_is_authored_not_generated(self):
        x, z, w, d = self.authored["bounds"]
        # Six times the original 352 x 272 m station (rounded out to the 8 m
        # module grid), still one fixed world with no roll or seed.
        self.assertEqual((w, d), (864, 672))
        self.assertGreaterEqual(w * d / (352 * 272), 6.0)
        self.assertLess(w * d / (352 * 272), 6.5)
        self.assertNotIn("seed", self.authored)
        self.assertNotIn("arena_id", self.authored)
        self.assertEqual(len(self.authored["sectors"]), 12)
        self.assertEqual(report_district_area(self.authored), 12 * 128 * 112)

    def test_coordinate_conversion_is_rectangular_and_offset(self):
        self.assertEqual((self.graph.width, self.graph.depth), (216, 168))
        self.assertEqual(self.graph.cell([-216, .2, 44]), (54, 95))
        self.assertEqual(self.graph.center((54, 95)), (-214, 46))

    def test_void_is_not_a_giant_walkable_arena(self):
        for point in [(-420, 0), (420, 0), (0, -320), (0, 320), (-176, -120), (176, 120)]:
            with self.subTest(point=point):
                self.assertNotIn(self.graph.cell(point), self.graph.walkable)

    def test_every_connector_deck_is_walkable(self):
        districts = [tuple(s["rect"]) for s in self.authored["sectors"]]
        connectors = [f for f in self.authored["floors"] if tuple(f) not in districts]
        self.assertGreaterEqual(len(connectors), 30)
        for area in connectors:
            x, z, w, d = area
            centre = [x + w / 2.0, .2, z + d / 2.0]
            with self.subTest(connector=area):
                self.assertIn(self.graph.cell(centre), self.graph.walkable)

    def test_shared_district_edges_are_open_not_walled(self):
        """A deck edge that borders another deck is never railed shut."""
        floors = self.authored["floors"]
        edges = self.graph.perimeter_edges()
        for area in floors:
            x, z, w, d = area
            horizontal = w > d
            seams = []
            if horizontal:
                for sx, step in ((x, -4.0), (x + w, 4.0)):
                    seams += [(sx, z + d / 2.0 - 4.0, step, 0.0), (sx, z + d / 2.0 + 4.0, step, 0.0)]
            else:
                for sz, step in ((z, -4.0), (z + d, 4.0)):
                    seams += [(x + w / 2.0 - 4.0, sz, 0.0, step), (x + w / 2.0 + 4.0, sz, 0.0, step)]
            for sx, sz, dx, dz in seams:
                if not any(fx <= sx + dx < fx + fw and fz <= sz + dz < fz + fd
                           for fx, fz, fw, fd in floors):
                    continue  # outer boundary: a rail there is correct
                blocking = [edge for edge in edges if _crosses(edge, (sx, sz), horizontal)]
                with self.subTest(deck=area, seam=(sx, sz)):
                    self.assertEqual(blocking, [], f"Sealed connector at {sx},{sz}")

    def test_each_checkpoint_can_reach_every_story_target(self):
        targets = {t for m in self.authored["missions"] for t in m["targets"]}
        for sector in self.authored["sectors"]:
            reachable = self.graph.reachable(sector["checkpoint"])
            for item in self.authored["interactions"]:
                if item["id"] in targets:
                    self.assertIn(self.graph.cell(item["at"]), reachable)

    def test_start_and_all_checkpoints_have_safe_spawn_clearance(self):
        members = [m for group in self.authored["encounters"] for m in group["members"]]
        for sector in self.authored["sectors"]:
            nearest = min(campaign.math.dist(sector["checkpoint"], m["at"]) for m in members)
            self.assertGreaterEqual(nearest, 24, sector["id"])

    def test_station_routes_have_real_distance_not_teleport_links(self):
        sectors = {s["id"]: s for s in self.authored["sectors"]}
        for far in ["command", "comms", "foundry"]:
            route = self.graph.path(sectors["docks"]["checkpoint"], sectors[far]["checkpoint"])
            with self.subTest(district=far):
                self.assertGreater(len(route) * 4, 400)
        for a, b in zip(route, route[1:]):
            self.assertAlmostEqual(campaign.math.dist(a, b), 4)

    def test_disconnecting_every_connector_deck_is_rejected(self):
        data = deepcopy(self.authored)
        districts = [tuple(s["rect"]) for s in data["sectors"]]
        data["floors"] = [r for r in data["floors"] if tuple(r) in districts]
        with self.assertRaisesRegex(campaign.CampaignError, "disconnected"):
            campaign.validate(data)

    def test_blocked_guard_spawn_regression_is_caught(self):
        data = deepcopy(self.authored)
        data["encounters"][1]["members"][0]["at"] = [-420, .2, -320]
        with self.assertRaisesRegex(campaign.CampaignError, "Blocked or unreachable"):
            campaign.validate(data)

    def test_every_district_has_a_rest_pad_supply_and_guard_post(self):
        for sector in self.authored["sectors"]:
            with self.subTest(district=sector["id"]):
                lockers = [i for i in self.authored["interactions"]
                           if i["sector"] == sector["id"] and i["kind"] == "cache"]
                guards = [m for g in self.authored["encounters"] if g["sector"] == sector["id"]
                          for m in g["members"]]
                self.assertEqual(len(lockers), 1)
                self.assertGreaterEqual(len(guards), 6)

    def test_invalid_target_and_reference_are_rejected(self):
        for mutation in ["position", "reference", "encounter"]:
            data = deepcopy(self.authored)
            if mutation == "position":
                data["interactions"][0]["at"] = [1000, .2, 0]
            elif mutation == "reference":
                data["missions"][0]["targets"] = ["missing_console"]
            else:
                data["missions"][0]["requires"] = ["missing_group"]
            with self.subTest(mutation=mutation), self.assertRaises(campaign.CampaignError):
                campaign.validate(data)

    def test_duplicate_spawn_and_reused_story_target_are_rejected(self):
        data = deepcopy(self.authored)
        data["encounters"][1]["members"][0]["id"] = data["encounters"][0]["members"][0]["id"]
        with self.assertRaisesRegex(campaign.CampaignError, "Duplicate spawn"):
            campaign.validate(data)
        data = deepcopy(self.authored)
        data["missions"][1]["targets"] = data["missions"][0]["targets"][:]
        with self.assertRaisesRegex(campaign.CampaignError, "reused"):
            campaign.validate(data)

    def test_non_finite_and_off_module_geometry_are_rejected(self):
        for value in [float("nan"), float("inf"), -159]:
            data = deepcopy(self.authored)
            data["floors"][0][0] = value
            with self.subTest(value=value), self.assertRaises(campaign.CampaignError):
                campaign.validate(data)

    def test_untracked_splitters_and_exploders_are_not_silently_supported(self):
        for kind in ["splitter", "exploder"]:
            data = deepcopy(self.authored)
            data["encounters"][0]["members"][0]["type"] = kind
            with self.subTest(kind=kind), self.assertRaisesRegex(campaign.CampaignError, "Untracked"):
                campaign.validate(data)

    def test_android_caps_are_bounded(self):
        for key, value in [("max_active_enemies", 19), ("max_visible_sectors", 4)]:
            data = deepcopy(self.authored)
            data[key] = value
            with self.assertRaisesRegex(campaign.CampaignError, "budget"):
                campaign.validate(data)

    def test_duplicate_json_keys_fail_instead_of_overwriting_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text('{"world_id":"station_zero","world_id":"other"}')
            with self.assertRaisesRegex(campaign.CampaignError, "Duplicate JSON key"):
                campaign.load(path)

    def test_overview_is_reproducible_from_the_actual_map(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "station.svg"
            campaign.write_svg(self.authored, path)
            self.assertEqual(path.read_text(), source("docs/campaign/STATION_ZERO_MAP.svg"))


class CampaignEntryAndPersistenceContracts(unittest.TestCase):
    def test_project_and_scene_router_start_the_real_campaign(self):
        path = "res://scenes/campaign/station_zero.tscn"
        self.assertIn(f'run/main_scene="{path}"', source("project.godot"))
        self.assertIn(f'const MAIN_SCENE := "{path}"', source("scripts/core/scene_router.gd"))
        self.assertIn("campaign_game.gd", source("scenes/campaign/station_zero.tscn"))

    def test_campaign_flow_has_no_arena_or_daily_setup(self):
        game = source("scripts/campaign/campaign_game.gd")
        ui = source("scripts/campaign/campaign_ui.gd")
        for banned in ["WaveManager.new", "Arena.new", "RunSetupPanel.new", "start_daily_run", "request_arena_selection"]:
            self.assertNotIn(banned, game + ui)
        self.assertIn("CONTINUE CAMPAIGN", ui)
        self.assertIn("NEW CAMPAIGN", ui)
        self.assertIn("STATION MAP", ui)

    def test_campaign_data_is_exported_explicitly(self):
        for path in ["export_presets.cfg", "export_presets.cfg.example"]:
            line = next(line for line in source(path).splitlines() if line.startswith("include_filter="))
            self.assertIn("data/campaign/*.json", line)

    def test_schema_eight_is_additive_not_a_profile_reset(self):
        schema = source("scripts/save/save_schema.gd")
        self.assertIn("const SCHEMA_VERSION := 8", schema)
        for field in ["campaign", "settings", "meta_ranks", "meta_wallet", "last_run_build"]:
            self.assertIn(f'"{field}"', schema)
        progress = source("scripts/campaign/campaign_progress.gd")
        for field in ["defeated", "interacted", "checkpoint", "mission", "upgrades", "xp", "weapons", "skills"]:
            self.assertIn(f'"{field}"', progress)

    def test_silent_xp_restore_does_not_replay_level_up_boons(self):
        method = source("scripts/player/experience_component.gd").split("func restore_total", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertIn("level_for_total_xp", method)
        self.assertNotIn("add_xp(", method)
        self.assertNotIn("_on_level_up(", method)

    def test_stream_out_is_not_a_kill_and_budget_is_enforced(self):
        script = source("scripts/campaign/campaign_encounters.gd")
        stream = script.split("func stream_nearby", 1)[1].split("\n\nfunc _spawn", 1)[0]
        self.assertNotIn("enemy_killed.emit", stream)
        self.assertNotIn("defeated.append", stream)
        self.assertIn("actor.queue_free()", stream)
        self.assertIn("SPAWNS_PER_TICK", stream)
        self.assertIn("_definition.max_active_enemies", stream)
        self.assertIn("id in _progress.defeated", stream)

    def test_commander_has_authored_finite_phases_not_untracked_summons(self):
        phases = source("scenes/campaign/security_commander.tscn")
        self.assertEqual(phases.count('type="Resource"'), 3)
        self.assertNotIn('&"summon"', phases)
        self.assertIn('&"shockwave"', phases)
        encounter = source("scripts/campaign/campaign_encounters.gd")
        self.assertIn("COMMANDER_SCENE", encounter)
        self.assertIn('boss.begin_fight(0, "command deck")', encounter)

    def test_mission_cursor_advances_before_rewards_and_wallet_persistence(self):
        method = source("scripts/campaign/campaign_director.gd").split("func _complete_mission", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertLess(method.index("progress.mission ="), method.index("_commit_reward"))
        self.assertIn("progress.checkpoint = String(mission.sector)", method)
        self.assertIn("_completion_pending", method)
        meta = source("scripts/meta/meta_progression.gd").split("func _on_run_ended", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertIn("if GameRoot.is_campaign():", meta)

    def test_touch_map_and_interact_cancel_on_safe_area_and_back(self):
        hud = source("scripts/campaign/campaign_hud.gd")
        for target in ["chart", "pause", "_interact"]:
            self.assertIn(f"TouchButtonInput.attach({target})", hud)
        ui = source("scripts/campaign/campaign_ui.gd")
        self.assertIn("_safe.safe_area_changed.connect(_relayout)", ui)
        self.assertIn("camera.cancel_touch_input()", ui)
        self.assertIn("NOTIFICATION_WM_GO_BACK_REQUEST", ui)

    def test_campaign_pickup_currency_reaches_permanent_wallet(self):
        method = source("scripts/pickups/pickup_manager.gd").split("PickupConfig.EFFECT_CURRENCY:", 1)[1].split("PickupConfig.EFFECT_SCORE:", 1)[0]
        self.assertIn("GameRoot.is_campaign()", method)
        self.assertIn("wallet.grant_currency", method)

    def test_geometry_uses_named_collision_bits_and_union_perimeter(self):
        geometry = source("scripts/campaign/campaign_geometry.gd")
        self.assertIn("CollisionLayers.WORLD_BODY_LAYER", geometry)
        self.assertIn("CollisionLayers.NO_LAYER", geometry)
        self.assertIn("func perimeter(regions: Array[Rect2])", geometry)
        self.assertIn("MultiMesh.new()", geometry)

    def test_native_campaign_harness_types_dynamic_ledger_sizes(self):
        harness = source("tests/verify_campaign_inner.gd")
        # Dictionary members are Variants: := cannot infer their size() result
        # in the native parser. Keep both before/after counters explicitly typed.
        self.assertEqual(harness.count("var before: int = _session.progress.defeated.size()"), 2)
        self.assertNotIn("var before := _session.progress.defeated.size()", harness)

    def test_native_campaign_wrapper_and_ci_are_registered(self):
        wrapper = source("scripts/run_campaign_validation.sh")
        self.assertIn("godot_test_profile", wrapper)
        self.assertIn("godot_test_timeout", wrapper)
        self.assertIn("check_godot_log.py", wrapper)
        self.assertIn("--require", wrapper)
        for path in [".github/workflows/android.yml", "scripts/build_android.sh"]:
            self.assertIn("run_campaign_validation.sh", source(path))
            self.assertIn("validate_campaign", source(path))


if __name__ == "__main__":
    unittest.main()
