"""Authored campaign/topology and shipping-entry contracts; no fake engine claims."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest

from tool import validate_campaign as campaign

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CampaignTopologyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.authored = campaign.load()
        cls.graph = campaign.Topology(cls.authored)

    def test_all_authored_content_is_valid_and_connected(self):
        report = campaign.validate(self.authored)
        self.assertEqual(report["districts"], 6)
        self.assertEqual(report["missions"], 7)
        self.assertEqual(report["authored_enemies"], 29)
        self.assertEqual(report["navigation_cells"], 5984)
        self.assertEqual(report["reachable_walkable_cells"], 2505)

    def test_coordinate_conversion_is_rectangular_and_offset(self):
        self.assertEqual((self.graph.width, self.graph.depth), (88, 68))
        self.assertEqual(self.graph.cell([-144, .2, 104]), (8, 60))
        self.assertEqual(self.graph.center((8, 60)), (-142, 106))

    def test_void_is_not_a_giant_walkable_arena(self):
        for point in [(-170, 0), (60, 0), (-60, 0), (160, -128)]:
            with self.subTest(point=point):
                self.assertNotIn(self.graph.cell(point), self.graph.walkable)

    def test_all_three_long_causeways_are_walkable(self):
        for x in [-112, 0, 112]:
            for z in range(-36, 56, 4):
                self.assertIn(self.graph.cell([x, z]), self.graph.walkable)

    def test_shared_district_edges_are_open_not_walled(self):
        for x in [-64, -48, 48, 64]:
            for z in [-76, 92]:
                blocking = [(a, b) for a, b in self.graph.perimeter_edges()
                            if a[0] == b[0] == x and min(a[1], b[1]) < z < max(a[1], b[1])]
                self.assertEqual(blocking, [], f"Sealed connector at {x},{z}")

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
        route = self.graph.path(sectors["docks"]["checkpoint"], sectors["reactor"]["checkpoint"])
        self.assertGreater(len(route) * 4, 400)
        for a, b in zip(route, route[1:]):
            self.assertAlmostEqual(campaign.math.dist(a, b), 4)

    def test_disconnect_all_north_south_routes_is_rejected(self):
        data = deepcopy(self.authored)
        data["floors"] = [r for r in data["floors"] if not (r[2] == 16 and r[3] == 96)]
        with self.assertRaisesRegex(campaign.CampaignError, "disconnected"):
            campaign.validate(data)

    def test_blocked_guard_spawn_regression_is_caught(self):
        data = deepcopy(self.authored)
        data["encounters"][1]["members"][3]["at"] = [20, .2, 64]
        with self.assertRaisesRegex(campaign.CampaignError, "Blocked or unreachable"):
            campaign.validate(data)

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
