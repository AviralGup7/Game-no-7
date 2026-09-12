"""Regression: 2026-09-11 fix pass (version, haptics, remaps, tutorial, pickers, waves)."""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class VersionIdentityTests(unittest.TestCase):
    def test_project_and_export_share_0_7_0(self) -> None:
        self.assertIn('config/version="0.7.0"', read("project.godot"))
        self.assertIn('version/name="0.7.0"', read("export_presets.cfg"))
        self.assertIn("version/code=4", read("export_presets.cfg"))
        example = read("export_presets.cfg.example")
        self.assertIn('version/name="0.7.0"', example)
        self.assertIn('gradle_build/min_sdk="24"', example)
        self.assertIn('gradle_build/target_sdk="34"', example)


class ArenaAndLoadoutWiringTests(unittest.TestCase):
    def test_ui_commands_delegate_arena_selection(self) -> None:
        txt = read("scripts/ui/ui_commands.gd")
        self.assertIn("GameRoot.request_arena_selection(id)", txt)
        self.assertNotIn("id == ContentRegistry.get_selected_arena_id()", txt)

    def test_game_root_exposes_arena_and_weapon_commands(self) -> None:
        txt = read("scripts/core/game_root.gd")
        self.assertIn("func request_arena_selection(id: StringName) -> bool:", txt)
        self.assertIn("func set_pending_weapon(weapon_id: StringName) -> void:", txt)
        self.assertIn("ContentRegistry.select_arena(id)", txt)

    def test_run_setup_no_longer_advertises_preview_only(self) -> None:
        txt = read("scripts/ui/run_setup_panel.gd")
        self.assertNotIn("not available in this build", txt)
        self.assertIn("GameRoot.set_pending_weapon", txt)
        self.assertIn("func _arena_is_playable", txt)


class RemapPersistenceTests(unittest.TestCase):
    def test_settings_serialize_bindings_on_save(self) -> None:
        txt = read("scripts/ui/settings_panel.gd")
        self.assertIn("saved.set_input_bindings(InputRemapper.serialize_actions())", txt)
        self.assertIn("Bindings save with your profile", txt)
        self.assertNotIn("current save schema has no binding field", txt)

    def test_save_manager_applies_bindings_on_load(self) -> None:
        txt = read("scripts/save/save_manager.gd")
        self.assertIn("InputRemapper.snapshot_factory()", txt)
        self.assertIn("InputRemapper.deserialize_actions(_settings.input_bindings)", txt)
        self.assertIn("InputRemapper.restore_factory()", txt)

    def test_schema_is_at_least_six(self) -> None:
        txt = read("scripts/save/save_schema.gd")
        self.assertGreaterEqual(int(re.search(r"const SCHEMA_VERSION := (\d+)", txt).group(1)), 6)
        self.assertIn("input_bindings", read("scripts/save/settings_data.gd"))


class TutorialAndWaveTests(unittest.TestCase):
    def test_coach_walks_seven_steps(self) -> None:
        txt = read("scripts/ui/tutorial_manager.gd")
        self.assertIn(
            "const STEP_ORDER := [STEP_MOVE, STEP_ATTACK, STEP_DODGE, STEP_WINDED, STEP_SKILL, STEP_UPGRADE, STEP_SURVIVE]",
            txt,
        )
        self.assertIn("EventBus.skill_cast", txt)
        self.assertIn("EventBus.upgrade_selected", txt)
        self.assertIn("EventBus.wave_completed", txt)

    def test_authored_midgame_waves_exist(self) -> None:
        for name in ("wave_06.tres", "wave_07.tres", "wave_08.tres", "wave_09.tres"):
            path = ROOT / "data" / "waves" / name
            self.assertTrue(path.exists(), "%s is missing" % name)
            body = path.read_text(encoding="utf-8")
            self.assertIn("script_class=\"WaveConfig\"", body)


class DocsAndChromeTests(unittest.TestCase):
    def test_readme_describes_the_shipping_campaign(self) -> None:
        # Arena/mode data remains tested separately; it is no longer the app's
        # primary flow. Documentation must follow the chosen connected world.
        txt = read("README.md")
        self.assertIn("one fixed, connected station", txt)
        self.assertIn("scenes/campaign/station_zero.tscn", txt)
        self.assertIn("seven story objectives", txt)
        self.assertNotIn("pick upgrades between\nwaves", txt)

    def test_diagnostics_workflow_tracks_this_branch(self) -> None:
        txt = read(".github/workflows/gdscript-diagnostics.yml")
        self.assertIn('branches: ["main", "arena/**"]', txt)
        self.assertNotIn("arena/01a08a34-game-no-7", txt)

    def test_debug_self_test_is_gated(self) -> None:
        txt = read("scripts/ui/settings_panel.gd")
        self.assertIn("TRIGGER TEST ERROR", txt)
        self.assertIn("debug_tools := OS.is_debug_build() or DebugErrorHandler.is_debug_mode()", txt)


if __name__ == "__main__":
    unittest.main()
