"""Regression tests for the eight authored skill cast-focus props, icons and their wiring.

The foci are shipped assets, so these tests read the files the game would load — the GLB, the
four PNG maps, the icons, the prop scenes, the skill resources and the catalogue — and re-derive
the recipe's own promises from them. Nothing here re-runs the generator: a test that rebuilds an
asset can only prove the builder is self-consistent, and `build_report.json` already carries the
hashes that pin what was actually written.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
for candidate in (ROOT, ROOT / 'tool'):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from tool.validate_assets import check_model, check_png, gltf_document
from tool.validate_resources import check_file

FOCI = {
    'seismic_slam': 'Graviton Pulse',
    'bladestorm': 'EMP Burst',
    'phantom_rush': 'Phase Dash',
    'shatterwave': 'Sonic Disruptor',
    'chain_lightning': 'Tesla Arc',
    'frost_nova_skill': 'Cryo Pulse',
    'mending_light': 'Repair Field',
    'warcry_skill': 'Overclock',
}
MODEL_DIR = ROOT / 'data' / 'models' / 'skills'
TRIANGLE_BUDGET = 4200
FOOTPRINT_LIMIT = 0.60
ATLAS = 512
ISLAND = 128


def model_dir(skill_id: str) -> Path:
    return MODEL_DIR / skill_id


class SkillFocusModelTests(unittest.TestCase):
    def test_every_skill_has_a_focus_and_nothing_else_does(self):
        built = {path.name for path in MODEL_DIR.iterdir() if path.is_dir() and path.name != 'icons'}
        self.assertEqual(built, set(FOCI), 'the focus set must match data/skills exactly')
        for skill_id in FOCI:
            self.assertTrue((model_dir(skill_id) / 'focus.glb').is_file(), f'{skill_id}: focus.glb missing')

    def test_focuses_are_gltf_two_with_a_full_attribute_set(self):
        for skill_id in FOCI:
            path = model_dir(skill_id) / 'focus.glb'
            doc = check_model(path, {path.resolve()})
            self.assertEqual(doc['asset']['version'], '2.0', f'{skill_id}: not glTF 2.0')
            self.assertEqual(len(doc['meshes']), 1, f'{skill_id}: a focus must be one draw call')
            self.assertEqual(len(doc['materials']), 1, f'{skill_id}: a focus must use one material')
            primitive = doc['meshes'][0]['primitives'][0]
            for attribute in ('POSITION', 'NORMAL', 'TANGENT', 'TEXCOORD_0'):
                self.assertIn(attribute, primitive['attributes'], f'{skill_id}: {attribute} missing')
            self.assertIn('indices', primitive, f'{skill_id}: an indexed mesh is required')
            position = doc['accessors'][primitive['attributes']['POSITION']]
            self.assertEqual(len(position['min']), 3, f'{skill_id}: POSITION needs a bounds record')
            self.assertTrue(all(low <= high for low, high in zip(position['min'], position['max'])),
                            f'{skill_id}: POSITION bounds are inverted')

    def test_focus_geometry_stays_inside_the_prop_budget(self):
        for skill_id in FOCI:
            doc, _binary = gltf_document(model_dir(skill_id) / 'focus.glb')
            extras = doc['extras']
            self.assertEqual(extras['recipe'], 'skill_focus_v1', f'{skill_id}: unexpected recipe')
            self.assertEqual(extras['skill_id'], skill_id)
            self.assertEqual(extras['display_name'], FOCI[skill_id])
            self.assertLessEqual(extras['triangles'], TRIANGLE_BUDGET,
                                 f"{skill_id}: {extras['triangles']} triangles over budget")
            self.assertLessEqual(extras['islands'], (ATLAS // ISLAND) ** 2, f'{skill_id}: atlas overflow')
            self.assertEqual(extras['atlas'], ATLAS, f'{skill_id}: atlas must be 512')
            wide, _tall, deep = extras['size_metres']
            self.assertLessEqual(max(wide, deep), FOOTPRINT_LIMIT, f'{skill_id}: footprint too wide')
            self.assertGreater(extras['size_metres'][1], 0.25, f'{skill_id}: focus is too squat to read')
            self.assertAlmostEqual(extras['aabb_min'][1], 0.0, places=4,
                                   msg=f'{skill_id}: the deck must sit on the floor, not float')

    def test_normals_are_unit_length_and_tangents_agree_with_them(self):
        """A focus is judged on its shading data: a bad tangent frame is invisible until it is lit."""
        for skill_id in FOCI:
            path = model_dir(skill_id) / 'focus.glb'
            doc, binary = gltf_document(path)
            primitive = doc['meshes'][0]['primitives'][0]
            normals = _read_floats(doc, binary, primitive['attributes']['NORMAL'], 3)
            tangents = _read_floats(doc, binary, primitive['attributes']['TANGENT'], 4)
            self.assertEqual(len(normals) % 3, 0)
            self.assertEqual(len(tangents) // 4, len(normals) // 3, f'{skill_id}: attribute count mismatch')
            worst_normal = max(abs(sum(component * component for component in normals[i:i + 3]) - 1.0)
                               for i in range(0, len(normals), 3))
            self.assertLess(worst_normal, 1e-3, f'{skill_id}: NORMAL is not unit length')
            worst_w = max(abs(abs(tangents[i + 3]) - 1.0) for i in range(0, len(tangents), 4))
            self.assertLess(worst_w, 1e-6, f'{skill_id}: TANGENT.w must be +-1')
            worst_dot = max(abs(normals[3 * k] * tangents[4 * k] + normals[3 * k + 1] * tangents[4 * k + 1]
                                 + normals[3 * k + 2] * tangents[4 * k + 2])
                            for k in range(len(normals) // 3))
            self.assertLess(worst_dot, 1e-3, f'{skill_id}: tangent is not orthogonal to its normal')

    def test_uv_layout_lands_inside_the_atlas_islands(self):
        for skill_id in FOCI:
            path = model_dir(skill_id) / 'focus.glb'
            doc, binary = gltf_document(path)
            primitive = doc['meshes'][0]['primitives'][0]
            uvs = _read_floats(doc, binary, primitive['attributes']['TEXCOORD_0'], 2)
            self.assertTrue(all(0.0 <= value <= 1.0 for value in uvs), f'{skill_id}: UV outside 0..1')
            wide = max(uvs[i] for i in range(0, len(uvs), 2)) - min(uvs[i] for i in range(0, len(uvs), 2))
            self.assertGreater(wide, 0.05, f'{skill_id}: degenerate UV spread')

    def test_focus_material_is_a_pbr_atlas_material_with_emissive_glow(self):
        for skill_id in FOCI:
            path = model_dir(skill_id) / 'focus.glb'
            doc, _binary = gltf_document(path)
            material = doc['materials'][0]
            pbr = material['pbrMetallicRoughness']
            for slot in ('baseColorTexture', 'metallicRoughnessTexture'):
                self.assertIn(slot, pbr, f'{skill_id}: {slot} missing')
            for slot in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
                self.assertIn(slot, material, f'{skill_id}: {slot} missing')
            self.assertEqual(material['alphaMode'], 'OPAQUE', f'{skill_id}: a prop is not blended')
            self.assertFalse(material['doubleSided'], f'{skill_id}: sealed hulls must not be double sided')
            self.assertEqual(len(doc['images']), 4, f'{skill_id}: four 512 maps are the contract')
            for image in doc['images']:
                self.assertEqual(image['mimeType'], 'image/png', f'{skill_id}: textures must be PNG')
            strength = material['extensions']['KHR_materials_emissive_strength']['emissiveStrength']
            self.assertGreater(strength, 1.0, f'{skill_id}: the cast glow has no headroom')
            accent = material['emissiveFactor']
            self.assertTrue(all(0.0 < component <= 1.0 for component in accent),
                            f'{skill_id}: emissiveFactor must be a sane accent colour')

    def test_each_focus_ships_the_socket_nodes_an_effect_needs(self):
        for skill_id in FOCI:
            doc, _binary = gltf_document(model_dir(skill_id) / 'focus.glb')
            names = {node.get('name') for node in doc['nodes']}
            for socket in ('Socket/Cast', 'Socket/Flare', 'Socket/Base'):
                self.assertIn(socket, names, f'{skill_id}: {socket} missing')
            base = next(node for node in doc['nodes'] if node.get('name') == 'Socket/Base')
            self.assertEqual(tuple(base.get('translation', [0.0, 0.0, 0.0])), (0.0, 0.0, 0.0),
                             f'{skill_id}: the base socket must sit on the floor')
            cast = next(node for node in doc['nodes'] if node.get('name') == 'Socket/Cast')
            self.assertGreater(cast['translation'][1], 0.2, f'{skill_id}: the cast socket is buried')

    def test_texture_maps_are_readable_pngs_of_the_agreed_size(self):
        for skill_id in FOCI:
            textures = model_dir(skill_id) / 'textures'
            prefix = 'Focus_' + ''.join(word.title() for word in skill_id.split('_'))
            for suffix in ('albedo', 'normal', 'ORM', 'emission'):
                path = textures / f'{prefix}_{suffix}.png'
                self.assertTrue(path.is_file(), f'{skill_id}: {path.name} missing')
                check_png(path)
                width, height = _png_size(path)
                self.assertEqual((width, height), (ATLAS, ATLAS), f'{skill_id}: {path.name} is not 512²')


class SkillFocusRenderTests(unittest.TestCase):
    def test_verification_renders_and_showcase_exist(self):
        for skill_id in FOCI:
            for name in ('focus_render.png', 'focus_front.png'):
                path = model_dir(skill_id) / name
                self.assertTrue(path.is_file(), f'{skill_id}: {name} missing')
                check_png(path)
        showcase = MODEL_DIR / 'skill_showcase.png'
        self.assertTrue(showcase.is_file(), 'the set contact sheet is missing')
        check_png(showcase)

    def test_skill_bar_icons_are_square_rgba_and_small(self):
        for skill_id in FOCI:
            path = MODEL_DIR / 'icons' / f'{skill_id}.png'
            self.assertTrue(path.is_file(), f'{skill_id}: icon missing')
            check_png(path)
            width, height = _png_size(path)
            self.assertEqual(width, height, f'{skill_id}: the skill bar crops a non-square icon')
            self.assertLessEqual(width, 128, f'{skill_id}: the skill bar draws icons at 24 px')
            self.assertGreaterEqual(width, 64, f'{skill_id}: icon is too small to re-use')
            data = path.read_bytes()
            colour_type = data[25]
            self.assertEqual(colour_type, 6, f'{skill_id}: the icon must carry an alpha channel')
            self.assertLess(len(data), 96 * 1024, f'{skill_id}: icon is needlessly heavy')


class SkillFocusSceneTests(unittest.TestCase):
    def test_prop_scenes_reference_their_own_model(self):
        for skill_id in FOCI:
            scene = ROOT / 'scenes' / 'props' / f'skill_focus_{skill_id}.tscn'
            self.assertTrue(scene.is_file(), f'{skill_id}: prop scene missing')
            problems: list[str] = []
            check_file(str(scene), problems)
            self.assertEqual(problems, [], f'{scene}: {problems}')
            text = scene.read_text()
            self.assertIn(f'res://data/models/skills/{skill_id}/focus.glb', text)
            self.assertIn('instance=ExtResource("1_focus_glb")', text)

    def test_skill_resources_point_at_their_rendered_icon(self):
        for skill_id in FOCI:
            path = ROOT / 'data' / 'skills' / f'{skill_id}.tres'
            text = path.read_text()
            self.assertIn(f'icon = ExtResource("2_icon")', text, f'{skill_id}: no icon wired')
            self.assertIn(f'res://data/models/skills/icons/{skill_id}.png', text)
            header = text.splitlines()[0]
            ext_count = text.count('[ext_resource')
            sub_count = text.count('[sub_resource')
            declared = int(header.split('load_steps=')[1].split()[0])
            self.assertEqual(declared, ext_count + sub_count + 1,
                             f'{skill_id}: load_steps must count every resource plus the own one')
            problems = []
            check_file(str(path), problems)
            self.assertEqual(problems, [], f'{skill_id}: {problems}')


class SkillFocusProvenanceTests(unittest.TestCase):
    def test_build_report_locks_every_file_it_wrote(self):
        report = json.loads((MODEL_DIR / 'build_report.json').read_text())
        self.assertEqual(report['recipe'], 'skill_focus_v1')
        self.assertEqual(report['generator'], 'tool/build_skill_foci.py')
        self.assertEqual(report['license_notice'], 'ASSET_LICENSES/skill-foci.md')
        self.assertEqual({entry['skill_id'] for entry in report['models']}, set(FOCI))
        self.assertEqual(report['budget'], {'triangles_per_prop': TRIANGLE_BUDGET, 'atlas': ATLAS,
                                            'island': ISLAND, 'icon': 128})
        listed = {entry['path'] for entry in report['files']}
        for skill_id in FOCI:
            self.assertIn(f'data/models/skills/{skill_id}/focus.glb', listed)
            self.assertIn(f'data/models/skills/icons/{skill_id}.png', listed)
        for entry in report['files']:
            path = ROOT / entry['path']
            self.assertTrue(path.is_file(), f"{entry['path']} was reported but is not on disk")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(digest, entry['sha256'], f"{entry['path']} changed since the build report")
        for source in report['recipe_files']:
            self.assertTrue((ROOT / source['path']).is_file(), f"{source['path']} is gone")

    def test_reported_geometry_matches_the_shipped_glb(self):
        report = json.loads((MODEL_DIR / 'build_report.json').read_text())
        for entry in report['models']:
            doc, _binary = gltf_document(model_dir(entry['skill_id']) / 'focus.glb')
            extras = doc['extras']
            self.assertEqual(entry['triangles'], extras['triangles'], f"{entry['skill_id']}: triangle count")
            self.assertEqual(entry['vertices'], extras['vertices'], f"{entry['skill_id']}: vertex count")
            self.assertEqual(entry['parts'], len(extras['parts']), f"{entry['skill_id']}: part count")
            self.assertEqual(entry['islands'], extras['islands'], f"{entry['skill_id']}: island count")

    def test_catalogue_wires_model_icon_and_scene_for_every_skill(self):
        catalog = json.loads((ROOT / 'assets' / 'catalog.json').read_text())
        skills = catalog['gameplay_skills']
        self.assertEqual(set(skills), set(FOCI))
        for skill_id, entry in skills.items():
            for field in ('model', 'icon', 'prop_scene'):
                self.assertIn(field, entry, f'{skill_id}: catalogue is missing "{field}"')
                self.assertTrue((ROOT / entry[field]).is_file(),
                                f"{skill_id}: catalogue points at a missing {entry[field]}")
            self.assertEqual(entry['texture'], 'assets/scifi/fx/ring.png',
                             f'{skill_id}: the cast ring texture is still what the effect uses')


def _read_floats(doc: dict, binary: bytes, accessor_index: int, components: int) -> list[float]:
    accessor = doc['accessors'][accessor_index]
    view = doc['bufferViews'][accessor['bufferView']]
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    count = accessor['count'] * components
    fmt = {5126: ('f', 4), 5123: ('H', 2), 5125: ('I', 4)}[accessor['componentType']]
    return list(struct.unpack_from(f'<{count}{fmt[0]}', binary, start))


def _png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    return struct.unpack_from('>II', data, 16)


if __name__ == '__main__':
    unittest.main()
