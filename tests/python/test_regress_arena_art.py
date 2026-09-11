"""Arena art pass: per-arena bespoke dressing, landmark floor art, hazard models.

Locks the "generate what we can, download what we can't" pass:
* 13 downloaded KayKit dungeon models (per-arena shield banners, clutter variety,
  gate trophies, frost candles, depot crates, open vent grate) are manifest-locked;
* the landmark builder enriches all three silhouettes with floor art + idle motion;
* torch sconces get a deterministic glow halo on the approved Kenney flare sprite;
* hazard markers mount floor models under an honest (never scaled) telegraph disc;
* the decorator composes the new art per arena and keeps wall props visual-only.
"""

import hashlib
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

DECORATOR_GD = "scripts/arena/arena_decorator.gd"
BUILDER_GD = "scripts/arena/arena_landmark.gd"
TORCH_GD = "scripts/arena/torch_flicker.gd"
MARKER_GD = "scripts/arena/hazard_marker.gd"

NEW_DUNGEON_FILES = (
    "assets/environment/dungeon/banner_shield_red.glb",
    "assets/environment/dungeon/banner_shield_yellow.glb",
    "assets/environment/dungeon/banner_shield_blue.glb",
    "assets/environment/dungeon/barrel_large_decorated.glb",
    "assets/environment/dungeon/barrel_small_stack.glb",
    "assets/environment/dungeon/box_small_decorated.glb",
    "assets/environment/dungeon/box_stacked.glb",
    "assets/environment/dungeon/candle_triple.glb",
    "assets/environment/dungeon/candle_thin_lit.glb",
    "assets/environment/dungeon/sword_shield.glb",
    "assets/environment/dungeon/sword_shield_gold.glb",
    "assets/environment/dungeon/trunk_medium_A.glb",
    "assets/environment/dungeon/floor_tile_grate_open.glb",
)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def code(rel: str) -> str:
    out = []
    for line in read(rel).splitlines():
        if line.lstrip().startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def load_manifest() -> dict:
    return json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))


class ShieldBannerIdentityTests(unittest.TestCase):
    def test_station_displays_replace_fantasy_banners(self):
        src = code(DECORATOR_GD)
        self.assertIn('res://assets/environment/space_station/', src)
        self.assertNotIn('banner_shield_', src)
        self.assertIn('display-wall.glb', src)
        self.assertTrue((ROOT / 'assets/environment/space_station/display-wall.glb').is_file())


class DownloadedArtIsLockedTests(unittest.TestCase):
    def test_new_dungeon_files_are_manifest_locked(self):
        manifest = load_manifest()
        by_path = {entry["path"]: entry for entry in manifest["files"]}
        for rel in NEW_DUNGEON_FILES:
            self.assertIn(rel, by_path, f"{rel} is not in assets/manifest.json")
            entry = by_path[rel]
            self.assertEqual(entry["pack"], "dungeon", f"{rel} left the reviewed dungeon pack")
            raw = (ROOT / rel).read_bytes()
            self.assertEqual(len(raw), entry["bytes"], f"{rel} byte length drifted")
            self.assertEqual(hashlib.sha256(raw).hexdigest(), entry["sha256"],
                             f"{rel} checksum drifted from its lock")
            self.assertEqual(entry["url"],
                             "https://api.github.com/repos/KayKit-Game-Assets/"
                             "KayKit-Dungeon-Remastered-1.0/contents/"
                             f"{entry['source_path']}?ref={manifest['sources']['dungeon']['revision']}",
                             f"{rel} URL no longer matches the pinned source")


class LandmarkFloorArtTests(unittest.TestCase):
    def test_builder_carries_floor_art_and_idle(self):
        src = code(BUILDER_GD)
        for needle in ("func _build_floor_art(", "FLOOR_RING_OUTER", "func _torus(",
                       "func _register_pulse(", "func _process(", "_spin"):
            self.assertIn(needle, src, f"landmark idle/floor-art piece is gone: {needle}")

    def test_floor_ring_clears_the_dais(self):
        """The wide accent ring must sit outside the dais rim or the dais hides it."""
        src = code(BUILDER_GD)
        m = re.search(r"FLOOR_RING_INNER := ([\d.]+)", src)
        self.assertIsNotNone(m, "FLOOR_RING_INNER is gone")
        ring_inner = float(m.group(1))
        tscn = read("scenes/arena/arena.tscn")
        d = re.search(r'id="Mesh_dais_rim"\]\ntop_radius = ([\d.]+)', tscn)
        self.assertIsNotNone(d, "dais rim subresource is gone from arena.tscn")
        self.assertGreater(ring_inner, float(d.group(1)),
                           "the landmark floor ring would hide under the dais rim")


class TorchGlowTests(unittest.TestCase):
    def test_glow_halo_uses_the_approved_sprite(self):
        src = code(TORCH_GD)
        self.assertIn("res://assets/scifi/fx/flare.png", src)
        self.assertIn("Sprite3D", src)
        self.assertIn("BILLBOARD_ENABLED", src)
        manifest = load_manifest()
        paths = {entry["path"] for entry in manifest["files"]}
        self.assertIn("assets/effects/kenney/flare_01.png", paths,
                      "the torch glow sprite is not manifest-locked")


class HazardModelTests(unittest.TestCase):
    def test_markers_mount_floor_models(self):
        src = code(MARKER_GD)
        self.assertIn("MODEL_BY_HAZARD", src)
        for hazard_id, model in (("spike_bed", "hazard_tile.glb"),
                                 ("fire_vent", "hazard_tile.glb"),
                                 ("pressure_plate", "hazard_tile.glb")):
            self.assertIn(hazard_id, src, f"{hazard_id} lost its floor model")
            self.assertIn(model, src, f"{hazard_id} no longer mounts {model}")
        self.assertIn("HdMaterials.polish", src,
                      "hazard floor models skip the HD material pass")
        self.assertIn("func _build_rim(", src, "the hitbox rim ring is gone")

    def test_telegraph_disc_never_scales(self):
        """The disc is the honest hitbox read: pulsing it by scale would lie about
        the radius, so only emission energies may move."""
        self.assertNotIn("_disc.scale", code(MARKER_GD),
                         "the telegraph disc must never scale away from the hitbox")


class DecoratorCompositionTests(unittest.TestCase):
    def test_new_props_are_composed(self):
        src = code(DECORATOR_GD)
        for needle in ("func _mount_trophy_pair(", "TROPHY_LIFT", "SC_SWORD_GOLD",
                       "SC_CANDLELIT", "candle_angle", "SC_BOXSTACK", "SC_TRUNK",
                       "SC_BARREL_DECOR", "SC_BOX_DECOR"):
            self.assertIn(needle, src, f"decorator lost a composed prop: {needle}")

    def test_wall_props_stay_visual_only(self):
        src = code(DECORATOR_GD)
        body = src[src.index("func _wall_props("):].split("\nfunc ")[0]
        self.assertNotIn("_add_prop_collision", body,
                         "wall-hung banners must not gain colliders")
        self.assertNotIn("StaticBody3D", body,
                         "wall-hung banners must not gain bodies")


class ArtCatalogDocTests(unittest.TestCase):
    def test_catalog_doc_covers_the_new_art(self):
        doc = read("docs/ASSET_CATALOG.md")
        self.assertIn("256 checksum-locked", doc)
        self.assertIn("94 models", doc)
        self.assertIn("banner_shield", doc)


if __name__ == "__main__":
    unittest.main()
