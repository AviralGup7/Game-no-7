#!/usr/bin/env python3
"""Offline hero gate: real deform tracks, stable limbs, sockets, PBR and budgets.

Standard library only. Run `python3 tool/validate_hero.py`. Complements (does not
replace) the native Godot rig/mount/animation integration tests and device review.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tool.derived_assets import load_derived_manifest
from tool.validate_assets import gltf_document, require

WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
FORMATS = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    require('sparse' not in a, 'hero: sparse accessors are not part of this recipe')
    view = doc['bufferViews'][a['bufferView']]
    fmt = '<' + FORMATS[a['componentType']] * WIDTHS[a['type']]
    width = struct.calcsize(fmt)
    stride = view.get('byteStride', width)
    offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    require(offset + max(0, a['count'] - 1) * stride + width <= len(binary), 'hero: truncated accessor')
    return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(a['count'])]


def required_clips(root=ROOT):
    # Frozen contract for the retained, non-shipping Warden source archive.
    # Active robot contracts are checked independently by tool.scifi_assets.
    return set(['Idle', 'Walking_A', 'Running_A', '1H_Melee_Attack_Slice_Horizontal', '1H_Melee_Attack_Slice_Diagonal', '1H_Melee_Attack_Chop', '2H_Melee_Attack_Chop', '2H_Melee_Attack_Slice', '2H_Melee_Attack_Spin', '2H_Melee_Attack_Stab', 'Dualwield_Melee_Attack_Slice', '2H_Ranged_Shoot', '2H_Ranged_Reload', 'Dodge_Forward', 'Dodge_Backward', 'Dodge_Left', 'Dodge_Right', 'Hit_A', 'Death_A', 'Spellcast_Shoot', 'Spellcast_Raise', 'Cheer'])


def check_hero(doc, binary, report, root=ROOT):
    require(len(doc.get('skins', [])) == 1, 'hero: expected one deform skin')
    require(len(doc.get('meshes', [])) == 1, 'hero: expected one batched body mesh')
    primitives = doc['meshes'][0]['primitives']
    require(len(primitives) == 1, 'hero: body draw-surface budget exceeded')
    joints = doc['skins'][0]['joints']
    bones = {doc['nodes'][i]['name'] for i in joints}
    require(len(joints) <= 32 and len(bones) == len(joints), 'hero: invalid/oversized deform skeleton')
    require({'handslot.r', 'handslot.l', 'hips', 'chest', 'head'} <= bones, 'hero: missing required socket/bone')
    require(not any('IK' in bone or 'control-' in bone for bone in bones), 'hero: source controls leaked into runtime')
    bone_names = {i: doc['nodes'][i]['name'] for i in joints}
    animations = {clip['name']: clip for clip in doc.get('animations', [])}
    require(len(animations) == len(doc.get('animations', [])) == 76, 'hero: duplicate/missing source clips')
    contract = required_clips(root)
    require(len(contract) >= 22 and contract <= animations.keys(), 'hero: incomplete combat contract')
    decoded = {}
    def values(index):
        if index not in decoded:
            decoded[index] = accessor(doc, binary, index)
            require(all(math.isfinite(x) for row in decoded[index] for x in row), 'hero: non-finite data')
        return decoded[index]
    attr = primitives[0]['attributes']
    require({'POSITION', 'NORMAL', 'TANGENT', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'} <= attr.keys(),
            'hero: incomplete vertex/skin/tangent layout')
    vertices = values(attr['POSITION'])
    weights = values(attr['WEIGHTS_0'])
    vertex_joints = values(attr['JOINTS_0'])
    require(len(vertices) == len(weights) == len(vertex_joints), 'hero: mismatched skin streams')
    require(all(all(0 <= w <= 1 for w in row) and abs(sum(row) - 1) < .0001 for row in weights),
            'hero: unnormalized skin weights')
    require(all(all(0 <= j < len(joints) for j in row) for row in vertex_joints), 'hero: invalid joint index')
    for normal in values(attr['NORMAL']):
        require(abs(sum(x * x for x in normal) - 1) < .001, 'hero: non-unit normal')
    for tangent in values(attr['TANGENT']):
        require(abs(sum(x * x for x in tangent[:3]) - 1) < .001 and tangent[3] in (-1, 1),
                'hero: invalid tangent frame')
    require(all(all(0 <= x <= 1 for x in row) for row in values(attr['TEXCOORD_0'])), 'hero: atlas UV overflow')
    indices = values(primitives[0]['indices'])
    require(len(indices) % 3 == 0 and all(0 <= row[0] < len(vertices) for row in indices), 'hero: invalid topology')
    triangles = len(indices) // 3
    require(10000 < triangles <= 42000, 'hero: geometry budget / mesh replacement regression')
    require(1.80 < max(p[1] for p in vertices) - min(p[1] for p in vertices) < 1.90, 'hero: non-metric source scale')
    require(len(values(doc['skins'][0]['inverseBindMatrices'])) == len(joints), 'hero: incomplete bind matrices')
    varying = set()
    for name, clip in animations.items():
        addressed = set()
        for channel in clip['channels']:
            target = channel['target']
            j, path = target['node'], target['path']
            require(j in joints and path in ('translation', 'rotation'), 'hero: track escapes deform rig')
            require((j, path) not in addressed, 'hero: duplicate target channel')
            addressed.add((j, path))
            sampler = clip['samplers'][channel['sampler']]
            times, output = values(sampler['input']), values(sampler['output'])
            require(len(times) == len(output) >= 2, 'hero: missing motion keys')
            require(all(b[0] > a[0] for a, b in zip(times, times[1:])), 'hero: non-increasing key times')
            require(times[0][0] == 0 and times[-1][0] > 0, 'hero: empty clip duration')
            if name in ('Idle', 'Walking_A', 'Running_A'):
                seam = max(abs(a - b) for a, b in zip(output[0], output[-1]))
                # q and -q are the same orientation.
                if path == 'rotation':
                    seam = min(seam, max(abs(a + b) for a, b in zip(output[0], output[-1])))
                require(seam < .001, 'hero: locomotion loop has a pose discontinuity')
            if path == 'rotation':
                require(all(abs(sum(x * x for x in q) - 1) < .001 for q in output), 'hero: non-unit quaternion')
                if bone_names[j] != 'root' and any(max(abs(a - b) for a, b in zip(row, output[0])) > .005 for row in output):
                    varying.add(name)
            else:
                if bone_names[j] == 'root':
                    require(all(abs(p[0]) < .00001 and abs(p[2]) < .00001 for p in output), 'hero: planar root travel')
                elif bone_names[j] != 'hips':
                    rest = doc['nodes'][j]['translation']
                    require(all(max(abs(a - b) for a, b in zip(p, rest)) < .00001 for p in output),
                            'hero: non-root bone lengths change during motion')
        require(len(addressed) == len(joints) * 2, 'hero: clip does not reset all deform channels')
    require(contract <= varying, 'hero: pose-only placeholder substituted for a required clip')
    require(len(doc['images']) == 3, 'hero: expected three shared 1K PBR atlases')
    for image in doc['images']:
        path = root / 'assets/characters/warden' / image['uri']
        width, height = struct.unpack_from('>II', path.read_bytes(), 16)
        require((width, height) == (1024, 1024), 'hero: mobile texture budget exceeded')
    mat = doc['materials'][0]
    require(mat['pbrMetallicRoughness'].get('metallicFactor') == 1 and
            mat['pbrMetallicRoughness'].get('roughnessFactor') == 1 and
            'metallicRoughnessTexture' in mat['pbrMetallicRoughness'] and 'normalTexture' in mat,
            'hero: authored PBR surface response lost')
    require(mat.get('alphaMode', 'OPAQUE') == 'OPAQUE' and not mat.get('doubleSided'), 'hero: unnecessary alpha/double-sided cost')
    measured = report['measured']
    require(measured['triangles'] == triangles and measured['vertices'] == len(vertices) and
            measured['bones'] == len(joints) and measured['clips'] == len(animations), 'hero: stale measured inventory')
    require(sum(e['bytes'] for e in report['files']) == measured['bundle_bytes'] <= 8 * 1024 * 1024,
            'hero: bundle size budget / report mismatch')
    return f"Hero OK: {triangles:,} triangles, {len(joints)} bones, 76 real clips, one body surface; complete combat contract."


def main():
    try:
        report = load_derived_manifest()
        doc, binary = gltf_document(ROOT / 'assets/characters/warden/ArenaWarden.glb')
        print(check_hero(doc, binary, report))
        return 0
    except (OSError, ValueError, TypeError, KeyError, IndexError, struct.error) as error:
        print('Hero validation failed:', error)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
