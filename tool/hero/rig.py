"""Proportion retarget + glTF packing for the Arena Warden authoring recipe.

The CC0 KayKit source supplies MOTION, not visible geometry/materials. The target
uses the source local rest axes but different bone lengths, inverse bind matrices,
and skin. Rotation deltas therefore have an exact rest-axis correspondence.
All controller/IK helper joints are discarded. Skinning and grounding are baked
here; there is no retargeter, IK solver or animation-driven gameplay at runtime.
"""
from __future__ import annotations

import json
import struct

import numpy as np
from scipy.spatial.transform import Rotation

BONES = ["root", "hips", "spine", "chest", "head"]
for side in ("l", "r"):
    BONES += [f"{part}.{side}" for part in ("upperarm", "lowerarm", "wrist", "hand", "handslot")]
    BONES += [f"{part}.{side}" for part in ("upperleg", "lowerleg", "foot", "toes")]
INDEX = {name: i for i, name in enumerate(BONES)}


def read_glb(path):
    blob = path.read_bytes()
    length, kind = struct.unpack_from('<II', blob, 12)
    if kind != 0x4E4F534A:
        raise ValueError('Missing GLB JSON chunk')
    document = json.loads(blob[20:20 + length])
    binary_size, binary_kind = struct.unpack_from('<II', blob, 20 + length)
    if binary_kind != 0x004E4942:
        raise ValueError('Missing GLB binary chunk')
    return document, blob[28 + length:28 + length + binary_size]


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    v = doc['bufferViews'][a['bufferView']]
    dtype = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', np.dtype(dtype).itemsize * width)
    return np.ndarray((a['count'], width), dtype=dtype, buffer=binary, offset=offset,
                      strides=(stride, np.dtype(dtype).itemsize)).copy()


def matrix(t, q, scale=None):
    m = np.eye(4)
    m[:3, :3] = Rotation.from_quat(q).as_matrix()
    if scale is not None:
        m[:3, :3] *= np.asarray(scale)
    m[:3, 3] = t
    return m


def worlds(nodes):
    out = [None] * len(nodes)
    parent = {c: p for p, n in enumerate(nodes) for c in n.get('children', [])}
    def visit(i):
        if out[i] is None:
            n = nodes[i]
            m = matrix(n.get('translation', [0, 0, 0]), n.get('rotation', [0, 0, 0, 1]),
                       n.get('scale'))
            out[i] = visit(parent[i]) @ m if i in parent else m
        return out[i]
    return np.asarray([visit(i) for i in range(len(nodes))])


def target_rig(doc):
    source_by_name = {n.get('name'): i for i, n in enumerate(doc['nodes'])}
    source_world = worlds(doc['nodes'])
    source_parent = {c: p for p, n in enumerate(doc['nodes']) for c in n.get('children', [])}
    positions = {'root': (0, 0, 0), 'hips': (0, 0.955, 0), 'spine': (0, 1.105, 0),
                 'chest': (0, 1.365, 0), 'head': (0, 1.560, 0)}
    for side, sign in (('l', 1), ('r', -1)):
        for name, x, y, z in [('upperarm', .205, 1.465, 0), ('lowerarm', .485, 1.465, 0),
                              ('wrist', .727, 1.465, 0), ('hand', .771, 1.465, 0),
                              ('handslot', .810, 1.465, .014), ('upperleg', .103, .965, 0),
                              ('lowerleg', .103, .520, .013), ('foot', .103, .095, -.009),
                              ('toes', .103, .052, .190)]:
            positions[f'{name}.{side}'] = (x * sign, y, z)
    nodes = []
    for name in BONES:
        original = doc['nodes'][source_by_name[name]]
        n = {'name': name, 'rotation': original.get('rotation', [0, 0, 0, 1]),
             'translation': list(positions[name])}
        p = source_parent.get(source_by_name[name])
        if p is not None and doc['nodes'][p].get('name') in INDEX:
            pname = doc['nodes'][p]['name']
            # Unscaled rest axes: source scale noise must not propagate into a new bind.
            basis = Rotation.from_matrix(source_world[p][:3, :3]).as_matrix()
            n['translation'] = (basis.T @ (np.array(positions[name]) - positions[pname])).tolist()
        n['children'] = [INDEX[doc['nodes'][i]['name']] for i in original.get('children', [])
                         if doc['nodes'][i].get('name') in INDEX]
        if not n['children']:
            del n['children']
        nodes.append(n)
    # The source's almost-identity scales are intentionally normalized away.
    return nodes, source_by_name


class Writer:
    def __init__(self):
        self.doc = {'asset': {'version': '2.0', 'generator': 'Last Stand Arena Warden / recipe 1'},
                    'bufferViews': [], 'accessors': []}
        self.data = bytearray()
        self.cache = {}

    def view(self, data, target=None):
        while len(self.data) % 4:
            self.data.append(0)
        v = {'buffer': 0, 'byteOffset': len(self.data), 'byteLength': len(data)}
        if target:
            v['target'] = target
        self.doc['bufferViews'].append(v)
        self.data.extend(data)
        return len(self.doc['bufferViews']) - 1

    def add(self, data, kind, target=None, bounds=False):
        data = np.asarray(data)
        component = {np.dtype('<f4'): 5126, np.dtype('<u4'): 5125, np.dtype('<u2'): 5123}[data.dtype]
        key = (data.tobytes(), kind, target, bounds)
        if key in self.cache:
            return self.cache[key]
        a = {'bufferView': self.view(key[0], target), 'componentType': component,
             'count': len(data), 'type': kind}
        if bounds:
            a['min'] = np.atleast_1d(data.min(axis=0)).tolist()
            a['max'] = np.atleast_1d(data.max(axis=0)).tolist()
        self.doc['accessors'].append(a)
        idx = len(self.doc['accessors']) - 1
        self.cache[key] = idx
        return idx

    def finish(self):
        self.doc['buffers'] = [{'byteLength': len(self.data)}]
        js = json.dumps(self.doc, separators=(',', ':'), ensure_ascii=True).encode()
        js += b' ' * (-len(js) % 4)
        binary = bytes(self.data) + b'\0' * (-len(self.data) % 4)
        return (struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binary)) +
                struct.pack('<II', len(js), 0x4E4F534A) + js +
                struct.pack('<II', len(binary), 0x004E4942) + binary)


def sample(times, values, sample_times, rotation=False):
    """glTF LINEAR interpolation; shortest-arc unit quaternion interpolation."""
    times = times.reshape(-1)
    before = np.clip(np.searchsorted(times, sample_times, side='right') - 1, 0, len(times) - 1)
    after = np.minimum(before + 1, len(times) - 1)
    t = np.clip((sample_times - times[before]) /
                np.maximum(times[after] - times[before], 1e-9), 0, 1)[:, None]
    a, b = values[before].astype(float), values[after].astype(float)
    if not rotation:
        return a * (1 - t) + b * t
    dot = np.sum(a * b, axis=1, keepdims=True)
    b = np.where(dot < 0, -b, b)
    dot = np.clip(np.abs(dot), 0, 1)
    theta = np.arccos(dot)
    sine = np.maximum(np.sin(theta), 1e-9)
    q = (np.sin((1 - t) * theta) * a + np.sin(t * theta) * b) / sine
    q = np.where(dot > .9995, a * (1 - t) + b * t, q)
    return q / np.maximum(np.linalg.norm(q, axis=1, keepdims=True), 1e-9)


def pose_worlds(nodes, translations, rotations):
    frame_count = len(translations)
    local = np.zeros((frame_count, len(nodes), 4, 4))
    local[:, :, :3, :3] = Rotation.from_quat(rotations.reshape(-1, 4)).as_matrix().reshape(frame_count, -1, 3, 3)
    local[:, :, :3, 3] = translations
    local[:, :, 3, 3] = 1
    parent = {c: p for p, n in enumerate(nodes) for c in n.get('children', [])}
    output = np.zeros_like(local)
    done = set()
    def visit(i):
        if i not in done:
            output[:, i] = visit(parent[i]) @ local[:, i] if i in parent else local[:, i]
            done.add(i)
        return output[:, i]
    for i in range(len(nodes)):
        visit(i)
    return output



def rotation_between(a, b):
    a = a / max(np.linalg.norm(a), 1e-9)
    b = b / max(np.linalg.norm(b), 1e-9)
    cross = np.cross(a, b)
    sine = np.linalg.norm(cross)
    if sine < 1e-8:
        return Rotation.identity()
    return Rotation.from_rotvec(cross / sine * np.arctan2(sine, np.clip(a @ b, -1, 1)))


def condition_gait(nodes, translations, rotations, lift):
    """Offline two-bone leg solve: keep the donor's stride, not its chibi knee lift.

    Both legs use their own anatomical bend plane. Lower the swing ankle relative
    to the support ankle, retain world foot orientation, and solve fixed-length
    femur/tibia rotations. Nothing scales the mesh or runs an IK solver in game.
    """
    pose = pose_worlds(nodes, translations, rotations)
    for f in range(len(translations)):
        floor_ankle = min(pose[f, INDEX['foot.' + side], 1, 3] for side in ('l', 'r'))
        for side in ('l', 'r'):
            hip, knee, ankle = [INDEX[part + '.' + side] for part in ('upperleg', 'lowerleg', 'foot')]
            h, k, a = [pose[f, j, :3, 3].copy() for j in (hip, knee, ankle)]
            goal = a.copy()
            goal[1] = floor_ankle + (a[1] - floor_ankle) * lift
            length1, length2 = np.linalg.norm(k - h), np.linalg.norm(a - k)
            direction = goal - h
            distance = np.linalg.norm(direction)
            if distance < 1e-6:
                continue
            direction /= distance
            distance = float(np.clip(distance, abs(length1 - length2) + .001, length1 + length2 - .001))
            goal = h + direction * distance
            pole = k - h - direction * ((k - h) @ direction)
            if np.linalg.norm(pole) < 1e-6:
                pole = np.array([0., 0., 1.]) - direction * direction[2]
            pole /= max(np.linalg.norm(pole), 1e-8)
            cosine = np.clip((distance ** 2 + length1 ** 2 - length2 ** 2) / (2 * distance * length1), -1, 1)
            bend = h + direction * (length1 * cosine) + pole * (length1 * np.sqrt(1 - cosine ** 2))
            upper_delta = rotation_between(k - h, bend - h)
            upper_world = upper_delta * Rotation.from_matrix(pose[f, hip, :3, :3])
            lower_before = upper_delta * Rotation.from_matrix(pose[f, knee, :3, :3])
            lower_delta = rotation_between(upper_delta.apply(a - k), goal - bend)
            lower_world = lower_delta * lower_before
            parent_world = Rotation.from_matrix(pose[f, INDEX['hips'], :3, :3])
            rotations[f, hip] = (parent_world.inv() * upper_world).as_quat()
            rotations[f, knee] = (upper_world.inv() * lower_world).as_quat()
            rotations[f, ankle] = (lower_world.inv() * Rotation.from_matrix(pose[f, ankle, :3, :3])).as_quat()


def retarget(writer, source, binary, nodes, arrays):
    """Bake every source clip at 30 Hz; normalize scale and remove planar root travel.

    Ground correction is derived from the SKIN, not a bob tween. In grounded clips
    the lowest support vertex stays 6 mm above the floor. Jump clips keep airtime.
    The same baked curves are consumed by Godot and the browser review tool.
    """
    source_by_name = {n.get('name'): i for i, n in enumerate(source['nodes'])}
    rest_t = np.asarray([n['translation'] for n in nodes])
    rest_q = np.asarray([n['rotation'] for n in nodes])
    inverse_bind = np.linalg.inv(worlds(nodes))
    positions = np.c_[arrays['POSITION'], np.ones(len(arrays['POSITION']))]
    joints, weights = arrays['JOINTS_0'], arrays['WEIGHTS_0']
    # Support hull: all unique source vertices. Chunk poses so authoring memory is bounded.
    unique = np.unique(np.round(np.c_[positions[:, :3], joints, weights], 6), axis=0, return_index=True)[1]
    positions, joints, weights = positions[unique], joints[unique], weights[unique]
    animations, report = [], []
    for clip in source['animations']:
        duration = max(float(accessor(source, binary, s['input'])[-1, 0]) for s in clip['samplers'])
        # The donor's single-frame *_Pose clips have duration zero. Give these a
        # one-frame hold rather than emitting illegal duplicate input timestamps.
        duration = max(duration, 1.0 / 30.0)
        ts = np.linspace(0, duration, max(2, round(duration * 30) + 1))
        translations = np.tile(rest_t, (len(ts), 1, 1))
        rotations = np.tile(rest_q, (len(ts), 1, 1))
        for channel in clip['channels']:
            original = source['nodes'][channel['target']['node']]
            name, path = original.get('name'), channel['target']['path']
            if name not in INDEX or path == 'scale':
                continue
            sampler = clip['samplers'][channel['sampler']]
            if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
                raise ValueError(f"Unreviewed interpolation in {clip['name']}")
            value = sample(accessor(source, binary, sampler['input']),
                           accessor(source, binary, sampler['output']), ts, path == 'rotation')
            joint = INDEX[name]
            if path == 'rotation':
                rotations[:, joint] = value
            elif name in ('root', 'hips'):
                delta = value - original.get('translation', [0, 0, 0])
                if name == 'root':
                    delta[:, [0, 2]] = 0.0
                else:
                    # New femur/tibia chain is ~2x the stylized donor. Preserve weight
                    # shifts, but let the support solve determine the vertical pelvis.
                    delta[:, 1] *= 1.8
                    # Strip net travel while retaining the anticipation/weight shift.
                    travel = delta[-1, [0, 2]] - delta[0, [0, 2]]
                    if np.linalg.norm(travel) > .20:
                        delta[:, [0, 2]] -= np.linspace(0, 1, len(ts))[:, None] * travel
                translations[:, joint] += delta
            # Non-root translations stay at the NEW rest offsets: no shrinking limbs.
        if clip['name'].startswith('Walking'):
            condition_gait(nodes, translations, rotations, .28)
        elif clip['name'].startswith('Running'):
            condition_gait(nodes, translations, rotations, .72)
        transforms = pose_worlds(nodes, translations, rotations)
        minimum = np.full(len(ts), np.inf)
        for start in range(0, len(ts), 8):
            skin = transforms[start:start + 8] @ inverse_bind
            posed_y = np.zeros((len(skin), len(positions)))
            for influence in range(4):
                row = skin[:, joints[:, influence], 1, :]
                posed_y += np.einsum('fvi,vi->fv', row, positions) * weights[None, :, influence]
            minimum[start:start + len(skin)] = posed_y.min(axis=1)
        if not clip['name'].startswith('Jump'):
            translations[:, INDEX['root'], 1] += .006 - minimum
        else:
            translations[:, INDEX['root'], 1] += np.maximum(.006 - minimum, 0)
        animation = {'name': clip['name'], 'channels': [], 'samplers': []}
        for j, name in enumerate(BONES):
            for path, values in [('translation', translations[:, j]), ('rotation', rotations[:, j])]:
                # Every clip resets every deform bone, even if a channel is constant.
                # This prevents remnants of interrupted death/dodge poses on a switch.
                compact = np.max(np.abs(values - values[0])) < 1e-6
                times = ts[[0, -1]] if compact else ts
                output = values[[0, -1]] if compact else values
                if path == 'rotation':
                    output = output / np.linalg.norm(output, axis=1, keepdims=True)
                    for i in range(1, len(output)):
                        if output[i - 1] @ output[i] < 0:
                            output[i] *= -1
                inp = writer.add(times.astype('<f4'), 'SCALAR', bounds=True)
                out = writer.add(output.astype('<f4'), 'VEC4' if path == 'rotation' else 'VEC3')
                animation['channels'].append({'sampler': len(animation['samplers']),
                                               'target': {'node': j, 'path': path}})
                animation['samplers'].append({'input': inp, 'output': out, 'interpolation': 'LINEAR'})
        animations.append(animation)
        report.append({'name': clip['name'], 'duration': round(duration, 6), 'frames': len(ts)})
    writer.doc['animations'] = animations
    return report
