"""Regression: startup stability invariants (core-stability pass).

Guards the fixes for:
  RC1  player.tscn has NO primitive fallback Body -> invisible player on any
       device-side model mount failure.
  RC2  autoload _ready() order was non-deterministic w.r.t. data: GameRoot read
       best score/wave before SaveManager had loaded them from disk.
  RC3  world/player bootstrap failed silently (no validation, no clear logging).
"""
from __future__ import annotations
import pathlib, re, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class AutoloadOrderTests(unittest.TestCase):
    """Each singleton's _ready() may only read data from singletons declared ABOVE it."""

    def order(self) -> list[str]:
        txt = read("project.godot")
        section = txt.split("[autoload]", 1)[1].split("[", 1)[0]
        found = re.findall(r'^(\w+)="\*(res://[^"]+)"', section, re.M)
        return [name for name, _ in found]

    def test_dependency_first_order(self) -> None:
        order = self.order()
        pos = {name: i for i, name in enumerate(order)}
        # EventBus first: every other singleton reports/connects through it.
        self.assertLess(pos["EventBus"], pos["SaveManager"])
        self.assertLess(pos["EventBus"], pos["AudioManager"])
        self.assertLess(pos["EventBus"], pos["GameRoot"])
        # SaveManager must finish loading from disk before consumers read data.
        self.assertLess(pos["SaveManager"], pos["AudioManager"])
        self.assertLess(pos["SaveManager"], pos["GameRoot"])
        # ContentRegistry registers audio cues into AudioManager at _ready().
        self.assertLess(pos["AudioManager"], pos["ContentRegistry"])
        # GameRoot reads ContentRegistry during run start (not _ready), but keep
        # it after the content store so main-menu consumers see loaded content.
        self.assertLess(pos["ContentRegistry"], pos["GameRoot"])

    def test_all_eight_singletons_present(self) -> None:
        self.assertEqual(
            set(self.order()),
            {"EventBus", "SaveManager", "AudioManager", "ContentRegistry",
             "GameRoot", "SceneRouter", "RunAnalytics", "TestHarness"})


class PlayerVisualFallbackTests(unittest.TestCase):
    """RC1: the player keeps a scene-authored primitive visual as fallback."""

    def test_player_scene_has_body(self) -> None:
        txt = read("scenes/player/player.tscn")
        self.assertIn('[node name="Body" type="MeshInstance3D" parent="VisualRoot/CharacterModel"]', txt)

    def test_visual_mount_reports_fallback_state(self) -> None:
        txt = read("scripts/visuals/visual_mount.gd")
        self.assertIn("report_warning", txt)
        self.assertIn("NO FALLBACK VISUAL PRESENT", txt)

    def test_character_visuals_exposes_model_path_and_reports(self) -> None:
        txt = read("scripts/visuals/character_visuals.gd")
        self.assertIn("static func model_path", txt)
        self.assertIn("_report_mount_issue", txt)
        self.assertIn("failed to load model", txt)


class WorldBootstrapValidationTests(unittest.TestCase):
    """RC3: bootstrap validation + structured failure reporting."""

    def test_spawn_player_fails_closed(self) -> None:
        txt = read("scripts/main/main.gd")
        self.assertIn("func _validate_player_visual", txt)
        self.assertIn("Player spawned with NO visual representation", txt)
        self.assertIn("Player scene failed to instantiate", txt)
        self.assertIn("World build incomplete: player could not be spawned", txt)

    def test_world_and_wave_failures_report(self) -> None:
        txt = read("scripts/main/main.gd")
        self.assertIn("World build aborted: WorldRoot missing", txt)
        self.assertIn("Waves cannot start", txt)

    def test_finalize_reads_authoritative_bests(self) -> None:
        txt = read("scripts/core/game_root.gd")
        self.assertIn("SaveManager.get_best_score()", txt)
        self.assertIn("SaveManager.get_best_wave()", txt)


if __name__ == "__main__":
    unittest.main()
