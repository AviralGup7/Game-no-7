#!/usr/bin/env python3
"""Build the project-authored Arena Warden and bake the licensed combat inventory.

    python3 -m venv .venv
    .venv/bin/pip install -r tool/hero/requirements.txt
    .venv/bin/python tool/build_hero.py

No network, Blender, hidden source scene, or game-time generation is required.
The committed GLB is the runtime asset; the donor GLB stays byte-identical.
--output-dir permits reproducibility checks without replacing the shipped asset.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
from hero.geometry import Geometry, blend_by_height
from hero.rig import BONES, INDEX, Writer, read_glb, retarget, target_rig, worlds

SOURCE = 'assets/characters/adventurers/Knight.glb'
DESTINATION = 'assets/characters/warden/ArenaWarden.glb'
STEEL, BRASS, LEATHER, CLOTH, MAIL, DARK, ENAMEL, SOLE = range(8)


def ring(g, name, y, rx, rz, bone, zone=BRASS, x=0, z=0, thickness=.003):
    points = [(x + math.sin(a) * rx, y, z + math.cos(a) * rz)
              for a in np.linspace(-math.pi, math.pi, 49)]
    g.tube(name, points, thickness, zone, bone, 6)


def build_geometry():
    g = Geometry(INDEX)
    # Gambeson and mail bridge all articulated gaps; metal never rubber-stretches.
    g.shell('tailored arming doublet', [(.925, .133, .096), (1.06, .119, .095),
            (1.20, .146, .112), (1.36, .187, .125), (1.45, .165, .101)], LEATHER,
            blend_by_height('hips', 'chest', 1.03, 1.35))
    g.shell('mail standard', [(1.44, .100, .085), (1.49, .090, .080),
            (1.57, .073, .072), (1.62, .078, .074)], MAIL, blend_by_height('chest', 'head', 1.45, 1.61))
    g.shell('forged breast and back plate', [(1.085, .131, .108), (1.12, .146, .118),
            (1.21, .172, .133), (1.31, .194, .147), (1.395, .202, .147),
            (1.435, .184, .124), (1.47, .125, .101), (1.492, .096, .086)],
            STEEL, 'chest', segments=48, ridge=.013)
    ring(g, 'rolled gorget edge', 1.493, .097, .087, 'chest')
    ring(g, 'cuirass lower rolled edge', 1.09, .133, .112, 'chest', thickness=.004)
    # Articulated fauld: overlapping steel lames over the belted waist.
    for i in range(3):
        y = 1.105 - i * .050
        g.shell(f'fauld lame {i}', [(y - .068, .151 + i * .004, .121),
                (y - .012, .139 + i * .003, .113), (y, .137 + i * .003, .111)],
                STEEL, 'hips', segments=40)
        ring(g, f'fauld roll {i}', y - .064, .151 + i * .004, .122, 'hips', thickness=.002)
    g.shell('waist harness', [(1.048, .153, .126), (1.053, .158, .131),
            (1.088, .157, .130), (1.093, .150, .125)], LEATHER, 'hips')
    # A subdued buckle, not a large fantasy medallion.
    g.tube('belt buckle', [(-.024, 1.051, .139), (.024, 1.051, .139),
           (.024, 1.09, .139), (-.024, 1.09, .139), (-.024, 1.051, .139)], .004, BRASS, 'hips')
    g.tube('buckle tongue', [(0, 1.051, .142), (0, 1.087, .142)], .002, STEEL, 'hips')
    # Blue split tabard is skinned to each thigh, not a rigid cape/board.
    for sign, side in [(1, 'l'), (-1, 'r')]:
        rows = [(1.042, .012, .126, .148), (.96, .013, .151, .149),
                (.84, .015, .167, .145), (.72, .019, .164, .144),
                (.59, .028, .155, .128), (.545, .040, .139, .118)]
        if sign < 0:
            rows = [(y, -right, -left, z) for y, left, right, z in rows]
        bind = blend_by_height('upperleg.' + side, 'hips', .78, 1.02)
        g.cloth('split blue tabard ' + side, rows, CLOTH, bind)
        for edge in (1, 2):
            g.tube('tabard stitched piping ' + side + str(edge),
                   [(r[edge], r[0], r[3] + .003) for r in rows], .0017, BRASS, bind, 5)
    # A fitted blue shoulder mantle, short enough not to require cape simulation.
    g.cloth('back mantle', [(1.447, -.156, .156, -.138), (1.37, -.178, .178, -.156),
            (1.24, -.154, .154, -.144), (1.16, -.128, .128, -.124)], CLOTH, 'chest')

    # Closed sallet: actual eye opening between shell rows, dark liner behind it.
    g.ellipsoid('helmet interior', (0, 1.716, -.006), (.113, .128, .111), DARK, 'head', 32, 18)
    helmet = [(1.588, .077, .073), (1.618, .096, .089), (1.664, .116, .112),
              (1.699, .121, .130), (1.717, .121, .139), (1.757, .124, .133),
              (1.804, .111, .116), (1.836, .080, .085), (1.855, .035, .038),
              (1.859, .001, .001)]
    g.shell('sallet with open sight slit', helmet, STEEL, 'head', segments=64,
            ridge=.008, omit=lambda row, a: row == 3 and -1.05 <= a <= 1.05)
    ring(g, 'helmet lower rolled seam', 1.619, .097, .090, 'head', STEEL, thickness=.003)
    brow = [(math.sin(a) * .122, 1.718, math.cos(a) * .140 + .006 * math.exp(-20 * a * a))
            for a in np.linspace(-1.10, 1.10, 30)]
    g.tube('visor brow bevel', brow, .0025, BRASS, 'head', 6)
    g.tube('sallet crown ridge', [(0, 1.758, .140), (0, 1.805, .122), (0, 1.838, .088),
           (0, 1.862, .015), (0, 1.845, -.072), (0, 1.804, -.119), (0, 1.736, -.137)],
           .0034, STEEL, 'head', 7)
    for sign in (-1, 1):
        for x in (.040, .057, .074):
            # Vent inlays sit on the lower visor curvature, never luminous eyes.
            depth = .116 * math.sqrt(max(0, 1 - (x / .119) ** 2)) + .004
            g.tube('visor breathing vent', [(sign * x, 1.645, depth - .007),
                   (sign * x, 1.669, depth + .003)], .0022, DARK, 'head', 6)
        for y in (1.685, 1.746):
            g.ellipsoid('visor pivot rivet', (sign * .119, y, .014), (.005, .005, .005),
                        BRASS, 'head', 10, 6)

    # Human-length arms, layered pauldrons, couters, tapered vambraces, gauntlets.
    for side, sign in [('l', 1), ('r', -1)]:
        upper, lower, hand = 'upperarm.' + side, 'lowerarm.' + side, 'hand.' + side
        basis = np.array([[0, sign, 0], [-sign, 0, 0], [0, 0, 1]])
        def arm(name, profiles, material, bone, segments=28):
            g.shell(name + ' ' + side, profiles, material, bone,
                    center=(0, 1.465, 0), segments=segments, basis=basis)
        arm('mail sleeve', [(.195, .081, .081), (.26, .078, .076), (.36, .061, .064),
                           (.472, .050, .055), (.497, .049, .052)], MAIL, upper)
        g.ellipsoid('shoulder arming joint ' + side, (sign * .202, 1.465, 0),
                    (.072, .080, .081), MAIL, upper, 24, 12)
        arm('pauldron dome', [(.155, .001, .001), (.175, .070, .079), (.209, .102, .114),
            (.250, .111, .121), (.290, .103, .112), (.323, .081, .091)], STEEL, upper, 40)
        for i in range(3):
            x = .294 + i * .025
            radius = .092 - i * .009
            arm(f'pauldron lame {i}', [(x, radius, radius * 1.13),
                (x + .034, radius - .005, radius * 1.08)], STEEL, upper)
            # Edge wire in a plane perpendicular to the humerus.
            g.tube('pauldron rolled edge ' + side, [(sign * (x + .034),
                   1.465 + math.sin(a) * (radius - .004), math.cos(a) * radius * 1.09)
                   for a in np.linspace(-math.pi, math.pi, 33)], .0023, BRASS, upper, 6)
        arm('rerebrace', [(.360, .061, .065), (.380, .063, .068),
            (.458, .052, .059), (.470, .052, .058)], STEEL, upper)
        g.ellipsoid('elbow arming joint ' + side, (sign * .486, 1.465, 0),
                    (.057, .052, .054), LEATHER, lower)
        arm('couter', [(.462, .050, .055), (.480, .070, .069),
                       (.510, .067, .067), (.522, .052, .056)], STEEL, lower)
        arm('vambrace', [(.514, .053, .057), (.549, .065, .066),
            (.612, .058, .060), (.685, .044, .046), (.715, .042, .044)], STEEL, lower, 36)
        for x, radius in [(.545, .065), (.687, .046)]:
            g.tube('vambrace seam ' + side, [(sign * x, 1.465 + math.sin(a) * radius,
                   math.cos(a) * radius) for a in np.linspace(-math.pi, math.pi, 33)], .0023,
                   BRASS, lower, 6)
        arm('gauntlet cuff', [(.700, .048, .052), (.723, .045, .048),
            (.751, .034, .040), (.769, .035, .041)], STEEL, hand)
        g.ellipsoid('leather glove ' + side, (sign * .791, 1.464, -.007),
                    (.046, .035, .041), LEATHER, hand, 24, 12)
        g.ellipsoid('gauntlet metacarpal plate ' + side, (sign * .786, 1.487, -.008),
                    (.038, .017, .034), STEEL, hand, 24, 10)
        for finger in range(4):
            z = -.031 + finger * .019
            points = [(sign * .802, 1.487, z), (sign * .831, 1.484, z),
                      (sign * .843, 1.464, z), (sign * .834, 1.447, z)]
            g.tube('articulated glove finger ' + side, points, .008, STEEL, hand, 8)
        g.tube('gauntlet thumb ' + side, [(sign * .785, 1.463, .035),
               (sign * .809, 1.446, .044), (sign * .825, 1.445, .027)], .012, LEATHER, hand, 10)
        for x in (.258, .29):
            g.ellipsoid('pauldron rivet ' + side, (sign * x, 1.52, .098),
                        (.004, .004, .004), BRASS, upper, 8, 6)

    # Fitted cuisses and shaped greaves, not low-poly cylinder limbs.
    for side, sign in [('l', 1), ('r', -1)]:
        x = sign * .103
        thigh, shin, foot = 'upperleg.' + side, 'lowerleg.' + side, 'foot.' + side
        g.shell('quilted chausses ' + side, [(.50, .056, .061), (.62, .065, .071),
                (.77, .081, .086), (.91, .083, .089), (.977, .076, .080)],
                LEATHER, thigh, center=(x, 0, .003))
        g.shell('cuisses ' + side, [(.557, .057, .070), (.590, .064, .078),
                (.713, .080, .092), (.830, .087, .094), (.894, .082, .089)], STEEL,
                thigh, center=(x, 0, .006), arc=(-1.94, 1.94), ridge=.006)
        for y, rx, rz in [(.578, .061, .074), (.866, .085, .094)]:
            ring(g, 'cuisses riveted border ' + side, y, rx, rz, thigh, STEEL, x, .006, .0025)
        g.ellipsoid('knee articulation ' + side, (x, .521, .012), (.059, .065, .066), MAIL, shin)
        g.shell('forged poleyn ' + side, [(.456, .010, .007), (.480, .052, .017),
                (.522, .072, .026), (.558, .057, .020), (.588, .018, .008)],
                STEEL, shin, center=(x, 0, .074), ridge=.006)
        g.ellipsoid('poleyn fan ' + side, (x + sign * .063, .532, .04),
                    (.033, .059, .023), STEEL, shin, 16, 10)
        g.shell('greave ' + side, [(.115, .040, .049), (.145, .043, .053),
                (.265, .058, .068), (.353, .064, .075), (.430, .061, .071),
                (.471, .056, .062)], STEEL, shin, center=(x, 0, -.009), ridge=.007, segments=36)
        for y, r, rz in [(.144, .044, .055), (.453, .060, .067)]:
            ring(g, 'greave edge ' + side, y, r, rz, shin, BRASS, x, -.009, .0028)
        g.shell('boot welt ' + side, [(.011, .058, .139), (.019, .069, .151),
                (.033, .070, .152), (.043, .065, .145)], SOLE, foot, center=(x, 0, .075))
        g.ellipsoid('sabatons ' + side, (x, .063, .070), (.067, .052, .147), STEEL, foot, 36, 14)
        for i in range(6):
            z = -.021 + i * .038
            halfwidth = .064 * math.sqrt(max(.1, 1 - ((z - .07) / .148) ** 2))
            points = [(x + u * halfwidth, .064 + .043 * math.sqrt(max(0, 1 - u * u)), z)
                      for u in np.linspace(-1, 1, 17)]
            g.tube('sabatons overlapping lame ' + side, points, .0025, STEEL, foot, 6)

    # Original arena heraldry: blue enamel lozenge and a restrained seven-ray seal.
    g.ellipsoid('blue enamel seal', (0, 1.355, .162), (.034, .041, .007), ENAMEL, 'chest', 24, 12)
    for a in np.linspace(0, 2 * math.pi, 8)[:-1]:
        g.tube('seven ray chest seal', [(math.sin(a) * .017, 1.355 + math.cos(a) * .017, .171),
               (math.sin(a) * .029, 1.355 + math.cos(a) * .030, .170)], .0018, BRASS, 'chest', 5)
    for sign in (-1, 1):
        for y, z in [(1.415, .116), (1.32, .134), (1.21, .123)]:
            g.ellipsoid('cuirass rivet', (sign * (.159 if y > 1.3 else .136), y, z),
                        (.0035, .0035, .0035), BRASS, 'chest', 8, 6)
    for i, (pos, joints, weights) in enumerate(zip(g.positions, g.joints, g.weights)):
        head_weight = sum(w for j, w in zip(joints, weights) if j == INDEX['head'])
        if head_weight:
            g.positions[i] = np.asarray(pos) - [0, .035 * head_weight, 0]
    return g


def texture_atlas():
    """Authored metal grain/wear, leather pores, woven cloth and mail normal detail.

    RGB base colour (sRGB); tangent normal and packed occlusion/roughness/metallic
    are linear data. No lighting/shadows are baked into the base colour map.
    """
    rng = np.random.default_rng(7)
    width, height = 256, 512
    y, x = np.mgrid[0:height, 0:width]
    colors = [(117, 128, 140), (144, 115, 70), (43, 34, 29), (31, 66, 106),
              (88, 93, 102), (22, 26, 31), (26, 73, 116), (25, 23, 22)]
    roughness = [.47, .46, .86, .92, .52, .56, .30, .94]
    metallic = [.94, .90, 0, 0, .90, .78, .65, 0]
    base = np.zeros((1024, 1024, 3), dtype=np.uint8)
    normal = np.zeros_like(base)
    orm = np.zeros_like(base)
    for zone in range(8):
        fine = rng.normal(0, 1, (height, width))
        large = rng.integers(30, 220, (16, 8), dtype=np.uint8)
        large = np.asarray(Image.fromarray(large).resize((width, height), Image.Resampling.BICUBIC)) / 255
        scratches = Image.new('L', (width, height))
        draw = ImageDraw.Draw(scratches)
        for _ in range(110):
            px, py = rng.integers(0, width), rng.integers(0, height)
            draw.line((int(px), int(py), int(px + rng.integers(-7, 8)),
                       int(py + rng.integers(3, 25))), fill=int(rng.integers(30, 110)), width=1)
        scratch = np.asarray(scratches, dtype=float) / 255
        grain = .5 * np.sin(x * 2.5 + np.sin(y * .07)) + fine * .6
        bump = fine * .002 + grain * .002 - scratch * .038
        variation = (large - .5) * 14 + fine * 1.2 + scratch * 21
        if zone in (LEATHER, SOLE):
            bump = (large - .5) * .04 + fine * .016
            variation = (large - .5) * 12 + fine * 1.2
        if zone == CLOTH:
            weave = np.sin(x * math.pi / 2) * np.sin(y * math.pi / 2)
            seams = np.maximum(0, np.cos((x + y * .22) * math.pi / 38)) ** 20
            bump = weave * .018 + seams * .020
            variation = weave * 2 + (large - .5) * 8
        if zone == MAIL:
            # Interlocking elliptical ring relief, at a scale appropriate to chain mail.
            ox = ((x + (y // 14 % 2) * 6) % 12 - 6) / 5.2
            oy = (y % 14 - 7) / 6.1
            dist = np.sqrt(ox ** 2 + oy ** 2)
            link = np.exp(-((dist - .78) * 8) ** 2)
            bump = link * .15
            variation = (link - .35) * 48
        dx = (np.roll(bump, -1, 1) - np.roll(bump, 1, 1)) * 2.0
        dy = (np.roll(bump, -1, 0) - np.roll(bump, 1, 0)) * 2.0
        n = np.stack([-dx, -dy, np.ones_like(dx)], axis=-1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        rgb = np.clip(np.asarray(colors[zone]) + variation[:, :, None], 0, 255).astype(np.uint8)
        packed = np.stack([np.ones_like(fine), np.clip(roughness[zone] + (large - .5) * .12 + scratch * .1, .1, 1),
                           np.full_like(fine, metallic[zone])], axis=-1)
        region = np.s_[zone // 4 * height:(zone // 4 + 1) * height,
                       zone % 4 * width:(zone % 4 + 1) * width]
        base[region] = rgb
        normal[region] = np.clip((n * .5 + .5) * 255, 0, 255).astype(np.uint8)
        orm[region] = np.clip(packed * 255, 0, 255).astype(np.uint8)
    images = []
    for array in [base, normal, orm]:
        output = io.BytesIO()
        Image.fromarray(array).save(output, format='PNG', optimize=False, compress_level=9)
        images.append(output.getvalue())
    return images



def build_gladius(images):
    """A narrow, bevelled PBR blade with its grip at the socket origin."""
    g = Geometry({'root': 0})
    g.shell('leaf blade', [(.087, .030, .004), (.143, .033, .0045),
            (.29, .028, .005), (.50, .031, .0045), (.66, .036, .004),
            (.75, .021, .0025), (.823, .0004, .0003)], STEEL, 'root', segments=8)
    g.shell('bronze guard', [(.060, .044, .020), (.076, .072, .023),
            (.089, .072, .023), (.102, .039, .018)], BRASS, 'root', segments=24)
    g.shell('leather grip', [(-.084, .019, .018), (-.064, .021, .019),
            (.045, .021, .019), (.070, .023, .020)], LEATHER, 'root', segments=24)
    g.ellipsoid('bronze pommel', (0, -.101, 0), (.030, .025, .024), BRASS, 'root', 24, 12)
    points = [(math.sin(a) * .0218, -.067 + a / (18 * math.pi) * .116,
               math.cos(a) * .020) for a in np.linspace(0, 18 * math.pi, 200)]
    g.tube('bound grip seam', points, .0011, SOLE, 'root', 5)
    writer = Writer()
    arrays = g.arrays()
    attrs = {name: writer.add(arrays[name], kind, 34962, name == 'POSITION')
             for name, kind in [('POSITION', 'VEC3'), ('NORMAL', 'VEC3'),
                                ('TANGENT', 'VEC4'), ('TEXCOORD_0', 'VEC2')]}
    writer.doc.update({'scene': 0, 'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'WardenGladius', 'mesh': 0}],
        'meshes': [{'primitives': [{'attributes': attrs, 'material': 0,
                    'indices': writer.add(arrays['indices'], 'SCALAR', 34963)}]}]})
    add_material(writer.doc, images)
    writer.doc['asset']['copyright'] = 'Last Stand: Arena project-authored equipment.'
    return writer.finish()


def add_material(doc, names):
    doc['images'] = [{'name': name.removesuffix('.png'), 'uri': name} for name in names]
    doc['textures'] = [{'sampler': 0, 'source': i} for i in range(3)]
    doc['samplers'] = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}]
    doc['materials'] = [{'name': 'Warden authored PBR atlas', 'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 0}, 'metallicRoughnessTexture': {'index': 2},
        'metallicFactor': 1.0, 'roughnessFactor': 1.0}, 'normalTexture': {'index': 1, 'scale': 1.0},
        'occlusionTexture': {'index': 2}, 'doubleSided': False}]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(output_dir):
    source_path = ROOT / SOURCE
    locked = json.loads((ROOT / 'assets/manifest.json').read_text())
    donor_entry = next(f for f in locked['files'] if f['path'] == SOURCE)
    if sha(source_path.read_bytes()) != donor_entry['sha256']:
        raise ValueError('The motion donor differs from the reviewed download lock')
    source, binary = read_glb(source_path)
    nodes, _ = target_rig(source)
    geometry = build_geometry()
    arrays = geometry.arrays()
    writer = Writer()
    doc = writer.doc
    doc['nodes'] = nodes
    # Both skeleton and mesh are scene roots (no ignored skinned-parent transform).
    mesh_node = len(nodes)
    doc['nodes'].append({'name': 'Warden_Armor', 'mesh': 0, 'skin': 0})
    doc['scenes'] = [{'name': 'Arena Warden', 'nodes': [INDEX['root'], mesh_node]}]
    doc['scene'] = 0
    bind = np.linalg.inv(worlds(nodes[:len(BONES)]))
    matrices = np.asarray([m.flatten(order='F') for m in bind], dtype='<f4')
    doc['skins'] = [{'name': 'WardenDeform', 'inverseBindMatrices': writer.add(matrices, 'MAT4'),
                     'skeleton': INDEX['root'], 'joints': list(range(len(BONES)))}]
    attributes = {}
    for name, kind in [('POSITION', 'VEC3'), ('NORMAL', 'VEC3'), ('TANGENT', 'VEC4'), ('TEXCOORD_0', 'VEC2'),
                       ('JOINTS_0', 'VEC4'), ('WEIGHTS_0', 'VEC4')]:
        attributes[name] = writer.add(arrays[name], kind, 34962, name == 'POSITION')
    doc['meshes'] = [{'name': 'Warden forged armor and tailored underlayers', 'primitives': [{
        'attributes': attributes, 'indices': writer.add(arrays['indices'], 'SCALAR', 34963), 'material': 0}]}]
    output_dir.mkdir(parents=True, exist_ok=True)
    image_names = ['Warden_base_color.png', 'Warden_normal.png', 'Warden_ORM.png']
    for name, image in zip(image_names, texture_atlas()):
        (output_dir / name).write_bytes(image)
    add_material(doc, image_names)
    (output_dir / 'WardenGladius.glb').write_bytes(build_gladius(image_names))
    clips = retarget(writer, source, binary, nodes[:len(BONES)], arrays)
    triangles = len(arrays['indices']) // 3
    if triangles > 42000 or len(BONES) > 32:
        raise ValueError('Mobile hero geometry/skin budget exceeded')
    doc['asset']['copyright'] = 'Project-authored geometry/textures; motion derived from Kay Lousberg, KayKit Adventurers (CC0-1.0).'
    doc['extras'] = {'hero': {'recipe': 1, 'height_m': round(float(np.ptp(arrays['POSITION'][:, 1])), 6), 'triangles': triangles,
                    'deform_bones': len(BONES), 'draw_surfaces': 1, 'texture_size': [1024, 1024],
                    'animation_count': len(clips), 'motion_source': SOURCE,
                    'motion_source_sha256': donor_entry['sha256'], 'ground_clearance_m': .006},
                    'authored_parts': geometry.parts}
    data = writer.finish()
    dest = output_dir / 'ArenaWarden.glb'
    output_dir.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    report = {'schema_version': 1, 'recipe': 'arena_warden_v1',
              'description': 'Project-authored proportional armored hero; baked CC0 motion retarget. Not a scanned/photoreal human.',
              'license_notice': 'ASSET_LICENSES/arena-warden.md',
              'generator': 'tool/build_hero.py',
              'inputs': [{'path': SOURCE, 'sha256': donor_entry['sha256'], 'license': 'CC0-1.0'}],
              'recipe_files': [{'path': p, 'sha256': sha((ROOT / p).read_bytes())} for p in
                               ['tool/build_hero.py', 'tool/hero/geometry.py', 'tool/hero/rig.py', 'tool/hero/requirements.txt']],
              'files': [{'path': 'assets/characters/warden/' + name,
                         'bytes': (output_dir / name).stat().st_size,
                         'sha256': sha((output_dir / name).read_bytes())}
                        for name in ['ArenaWarden.glb', 'WardenGladius.glb'] + image_names],
              'budgets': {'max_triangles': 42000, 'max_bones': 32, 'max_draw_surfaces': 1,
                          'max_texture_edge': 1024, 'max_file_bytes': 8 * 1024 * 1024},
              'measured': {'triangles': triangles, 'vertices': len(arrays['POSITION']),
                           'bones': len(BONES), 'draw_surfaces': 1, 'texture_images': 3,
                           'bytes': len(data), 'bundle_bytes': sum((output_dir / name).stat().st_size for name in
                               ['ArenaWarden.glb', 'WardenGladius.glb'] + image_names), 'clips': len(clips)},
              'clips': clips}
    (output_dir / 'build_report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['measured'], indent=2))
    if len(data) > report['budgets']['max_file_bytes']:
        raise ValueError('Hero payload exceeds budget')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'assets/characters/warden')
    args = parser.parse_args()
    build(args.output_dir)
