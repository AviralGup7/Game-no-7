"""Actual shipped hero data, provenance and failure-path regression checks.

Standard-library only; no Blender/NumPy/network/Godot dependency in this suite.
Native Skeleton3D/AnimationPlayer checks live in tests/unit/test_hero_rig.gd.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

from tool import derived_assets
from tool import validate_assets
from tool import validate_hero

ROOT = Path(__file__).resolve().parents[2]


class HeroFidelityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = derived_assets.load_derived_manifest()
        cls.doc, cls.binary = validate_assets.gltf_document(ROOT / 'assets/characters/warden/ArenaWarden.glb')

    def validate(self, doc=None, binary=None):
        return validate_hero.check_hero(self.doc if doc is None else doc,
                                      self.binary if binary is None else binary, self.report)

    def test_production_geometry_skin_and_all_required_motion_are_valid(self):
        self.assertIn('76 real clips', self.validate())

    def test_exact_source_inventory_survives_retarget(self):
        donor, _ = validate_assets.gltf_document(ROOT / derived_assets.DONOR)
        self.assertEqual({a['name'] for a in donor['animations']}, {a['name'] for a in self.doc['animations']})
        self.assertNotEqual(donor['meshes'], self.doc['meshes'])
        self.assertEqual(len(self.doc['skins'][0]['joints']), 23)

    def test_runtime_and_catalog_select_the_replacement(self):
        catalog = json.loads((ROOT / 'assets/catalog.json').read_text())
        player = catalog['characters']['player']
        self.assertEqual(player['model'], 'assets/characters/warden/ArenaWarden.glb')
        self.assertIn(player['model'], (ROOT / 'scripts/visuals/character_visuals.gd').read_text())
        self.assertEqual(player['fallback_model'], derived_assets.DONOR)
        self.assertEqual(player['source_triangles'], self.report['measured']['triangles'])
        self.assertEqual(set(player['animations'].values()), validate_hero.required_clips())
        self.assertIn(catalog['gameplay_weapons']['gladius']['model'],
                      (ROOT / 'scenes/player/player.tscn').read_text())

    def test_a_missing_attack_cannot_masquerade_as_complete_rig(self):
        doc = copy.deepcopy(self.doc)
        doc['animations'][0]['name'] = 'Incomplete_Attack'
        with self.assertRaisesRegex(ValueError, 'combat contract'):
            self.validate(doc=doc)

    def test_empty_tracks_are_not_animation_coverage(self):
        doc = copy.deepcopy(self.doc)
        next(a for a in doc['animations'] if a['name'] == 'Hit_A')['channels'] = []
        with self.assertRaisesRegex(ValueError, 'reset all deform'):
            self.validate(doc=doc)

    def test_methods_or_transform_tracks_cannot_escape_skeleton(self):
        doc = copy.deepcopy(self.doc)
        doc['animations'][0]['channels'][0]['target']['node'] = len(doc['nodes']) - 1
        with self.assertRaisesRegex(ValueError, 'escapes deform rig'):
            self.validate(doc=doc)

    def test_non_increasing_timestamps_fail(self):
        doc = copy.deepcopy(self.doc)
        index = doc['animations'][0]['samplers'][0]['input']
        accessor = doc['accessors'][index]
        view = doc['bufferViews'][accessor['bufferView']]
        binary = bytearray(self.binary)
        offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        struct.pack_into('<f', binary, offset + 4, 0.0)
        with self.assertRaisesRegex(ValueError, 'non-increasing'):
            self.validate(binary=binary)

    def test_bad_skin_weights_fail(self):
        index = self.doc['meshes'][0]['primitives'][0]['attributes']['WEIGHTS_0']
        a = self.doc['accessors'][index]
        v = self.doc['bufferViews'][a['bufferView']]
        binary = bytearray(self.binary)
        struct.pack_into('<f', binary, v.get('byteOffset', 0) + a.get('byteOffset', 0), 3.0)
        with self.assertRaisesRegex(ValueError, 'skin weights'):
            self.validate(binary=binary)

    def test_body_and_gladius_share_exactly_three_pbr_maps(self):
        weapon, _ = validate_assets.gltf_document(ROOT / 'assets/characters/warden/WardenGladius.glb')
        self.assertEqual(self.doc['images'], weapon['images'])
        self.assertEqual(self.doc['materials'], weapon['materials'])
        self.assertNotIn('skins', weapon)
        self.assertNotIn('animations', weapon)

    def test_new_native_suite_is_registered(self):
        self.assertIn('res://tests/unit/test_hero_rig.gd', (ROOT / 'tests/run_tests.gd').read_text())
        imports = (ROOT / 'tests/validate_asset_imports.gd').read_text()
        self.assertIn('build_report.json', imports)
        self.assertIn('HeroRigContract.missing_requirements', imports)
        player_suite = (ROOT / 'tests/integration/test_player.gd').read_text()
        self.assertIn('class Juice extends HitstopManager:', player_suite)

    def test_animation_remains_cosmetic_and_body_dimensions_are_unchanged(self):
        animator = (ROOT / 'scripts/player/player_animation.gd').read_text()
        for forbidden in ('move_and_slide(', 'apply_damage(', 'global_position =', 'Engine.time_scale ='):
            self.assertNotIn(forbidden, animator)
        self.assertIn('HeroRigContract.directional_dodge', animator)
        material = (ROOT / 'scripts/visuals/hd_materials.gd').read_text()
        self.assertIn('metallic_specular', material)
        self.assertNotIn('source.specular', material)
        scene = (ROOT / 'scenes/player/player.tscn').read_text()
        self.assertIn('radius = 0.45\nheight = 1.9', scene)
        self.assertIn('collision_layer = 2\ncollision_mask = 1', scene)

    def test_viewer_uses_real_assets_and_vendor_module_graph_is_complete(self):
        viewer = (ROOT / 'tool/hero_preview.html').read_text()
        self.assertIn('../assets/characters/warden/ArenaWarden.glb', viewer)
        self.assertIn('../assets/characters/adventurers/Knight.glb', viewer)
        self.assertIn('../assets/characters/warden/build_report.json', viewer)
        for script in (ROOT / 'tool/vendor').glob('*.js'):
            import re
            for dep in re.findall(r"from ['\"](\.[^'\"]+)['\"]", script.read_text()):
                self.assertTrue((script.parent / dep).is_file(), (script.name, dep))
        self.assertNotIn('http://localhost', viewer)
        self.assertNotIn('127.0.0.1', viewer)


class DerivedProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.report = json.loads((ROOT / derived_assets.HERO_REPORT).read_text())
        paths = ({derived_assets.HERO_REPORT, derived_assets.DONOR, 'assets/manifest.json',
                  'ASSET_LICENSES/arena-warden.md'} | derived_assets.RECIPE_FILES | derived_assets.HERO_OUTPUTS)
        for relative in paths:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, path)

    def write_report(self):
        (self.root / derived_assets.HERO_REPORT).write_text(json.dumps(self.report))

    def test_copied_inventory_verifies_offline(self):
        self.assertEqual(derived_assets.load_derived_manifest(self.root)['recipe'], 'arena_warden_v1')

    def test_modified_texture_is_not_silently_approved(self):
        texture = self.root / 'assets/characters/warden/Warden_normal.png'
        data = bytearray(texture.read_bytes())
        data[-8] ^= 1
        texture.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            derived_assets.load_derived_manifest(self.root)

    def test_missing_output_is_fatal_to_verification(self):
        (self.root / 'assets/characters/warden/ArenaWarden.glb').unlink()
        with self.assertRaisesRegex(ValueError, 'missing file'):
            derived_assets.load_derived_manifest(self.root)

    def test_changed_recipe_requires_explicit_rebuild(self):
        script = self.root / 'tool/hero/rig.py'
        script.write_text(script.read_text() + '\n# changed retarget\n')
        with self.assertRaisesRegex(ValueError, 'stale recipe'):
            derived_assets.load_derived_manifest(self.root)

    def test_made_up_input_cannot_replace_reviewed_donor(self):
        self.report['inputs'][0]['sha256'] = '0' * 64
        self.write_report()
        with self.assertRaisesRegex(ValueError, 'licence/hash lock'):
            derived_assets.load_derived_manifest(self.root)

    def test_derivative_inventory_cannot_whitelist_arbitrary_downloads(self):
        self.report['files'][0]['path'] = 'assets/unreviewed.glb'
        self.write_report()
        with self.assertRaisesRegex(ValueError, 'unreviewed derivative'):
            derived_assets.load_derived_manifest(self.root)

    def test_missing_notice_is_rejected(self):
        (self.root / 'ASSET_LICENSES/arena-warden.md').unlink()
        with self.assertRaisesRegex(ValueError, 'licence/provenance'):
            derived_assets.load_derived_manifest(self.root)


if __name__ == '__main__':
    unittest.main()
