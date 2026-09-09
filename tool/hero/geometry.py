"""Small, deterministic skinned-surface authoring helpers (authoring only).

All coordinates are metres, +Y up, +Z forward. No downloaded mesh is used.
Requires the pinned NumPy version in tool/hero/requirements.txt.
"""
from __future__ import annotations

import math
import numpy as np


class Geometry:
    def __init__(self, bones: dict[str, int]):
        self.bones = bones
        self.positions = []
        self.uvs = []
        self.joints = []
        self.weights = []
        self.indices = []
        self.parts = []

    def add(self, name, vertices, uv, faces, zone, binding):
        vertices = np.asarray(vertices, dtype=np.float64)
        start = len(self.positions)
        # Eight padded material tiles in one 1K atlas; one opaque draw surface.
        uv = np.asarray(uv, dtype=np.float64)
        uv[:, 0] = (zone % 4 + 0.025 + uv[:, 0] * 0.95) / 4
        uv[:, 1] = (zone // 4 + 0.015 + uv[:, 1] * 0.97) / 2
        self.positions.extend(vertices)
        self.uvs.extend(uv)
        for pos in vertices:
            weights = binding(pos) if callable(binding) else {binding: 1.0}
            weights = [(self.bones[b], float(w)) for b, w in weights.items() if w > 0.00001]
            if not 1 <= len(weights) <= 4:
                raise ValueError(f"Invalid influences on {name}: {weights}")
            total = sum(w for _, w in weights)
            self.joints.append([b for b, _ in weights] + [0] * (4 - len(weights)))
            self.weights.append([w / total for _, w in weights] + [0.0] * (4 - len(weights)))
        self.indices.extend([[start + a, start + b, start + c] for a, b, c in faces])
        self.parts.append({"name": name, "first_vertex": start, "vertices": len(vertices),
                           "triangles": len(faces), "material_tile": zone})

    def arrays(self):
        p = np.asarray(self.positions, dtype=np.float64)
        faces = np.asarray(self.indices, dtype=np.uint32)
        # Remove collapsed pole faces before calculating smooth area-weighted normals.
        fn = np.cross(p[faces[:, 1]] - p[faces[:, 0]], p[faces[:, 2]] - p[faces[:, 0]])
        valid = np.linalg.norm(fn, axis=1) > 1e-12
        faces, fn = faces[valid], fn[valid]
        n = np.zeros_like(p)
        for corner in range(3):
            np.add.at(n, faces[:, corner], fn)
        # Weld coincident normals WITHIN each part (UV seams, not plate edges).
        for part in self.parts:
            lo, hi = part["first_vertex"], part["first_vertex"] + part["vertices"]
            _, inverse = np.unique(np.round(p[lo:hi], 7), axis=0, return_inverse=True)
            summed = np.zeros((int(inverse.max()) + 1, 3))
            np.add.at(summed, inverse, n[lo:hi])
            n[lo:hi] = summed[inverse]
        length = np.linalg.norm(n, axis=1)
        n[length < 1e-12] = [0, 1, 0]
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        uvs = np.asarray(self.uvs, dtype=np.float64)
        tangent, bitangent = np.zeros_like(p), np.zeros_like(p)
        dp1, dp2 = p[faces[:, 1]] - p[faces[:, 0]], p[faces[:, 2]] - p[faces[:, 0]]
        du1, du2 = uvs[faces[:, 1]] - uvs[faces[:, 0]], uvs[faces[:, 2]] - uvs[faces[:, 0]]
        determinant = du1[:, 0] * du2[:, 1] - du1[:, 1] * du2[:, 0]
        inv = np.zeros_like(determinant)
        np.divide(1.0, determinant, out=inv, where=np.abs(determinant) > 1e-12)
        ft = (du2[:, 1, None] * dp1 - du1[:, 1, None] * dp2) * inv[:, None]
        fb = (du1[:, 0, None] * dp2 - du2[:, 0, None] * dp1) * inv[:, None]
        for corner in range(3):
            np.add.at(tangent, faces[:, corner], ft)
            np.add.at(bitangent, faces[:, corner], fb)
        tangent -= n * np.sum(tangent * n, axis=1, keepdims=True)
        invalid = np.linalg.norm(tangent, axis=1) < 1e-10
        fallback = np.cross(n, np.where((np.abs(n[:, 1]) < .9)[:, None], [0, 1, 0], [1, 0, 0]))
        tangent[invalid] = fallback[invalid]
        tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-12)
        sign = np.where(np.sum(np.cross(n, tangent) * bitangent, axis=1) < 0, -1.0, 1.0)
        return {"POSITION": p.astype('<f4'), "NORMAL": n.astype('<f4'),
                "TANGENT": np.c_[tangent, sign].astype('<f4'),
                "TEXCOORD_0": uvs.astype('<f4'),
                "JOINTS_0": np.asarray(self.joints, dtype='<u2'),
                "WEIGHTS_0": np.asarray(self.weights, dtype='<f4'),
                "indices": faces.reshape(-1).astype('<u4')}

    def shell(self, name, profiles, zone, bone, center=(0, 0, 0), segments=32,
              arc=(-math.pi, math.pi), basis=None, ridge=0.0, omit=None):
        """Loft elliptical profiles (height, X radius, Z radius), optionally open."""
        vertices, uv, faces = [], [], []
        for row, (height, rx, rz) in enumerate(profiles):
            for col in range(segments + 1):
                angle = arc[0] + (arc[1] - arc[0]) * col / segments
                z = math.cos(angle) * rz
                if z > 0:
                    z += ridge * math.exp(-20 * angle * angle)
                vertices.append((math.sin(angle) * rx, height, z))
                uv.append((col / segments, row / (len(profiles) - 1)))
                if row < len(profiles) - 1 and col < segments:
                    if omit and omit(row, angle):
                        continue
                    a = row * (segments + 1) + col
                    b = a + segments + 1
                    faces.extend(((a, a + 1, b), (a + 1, b + 1, b)))
        vertices = np.asarray(vertices)
        if basis is not None:
            vertices = vertices @ np.asarray(basis).T
        vertices += np.asarray(center)
        self.add(name, vertices, uv, faces, zone, bone)

    def ellipsoid(self, name, center, radii, zone, bone, segments=20, rings=12):
        profiles = []
        for j in range(rings + 1):
            phi = -math.pi / 2 + math.pi * j / rings
            profiles.append((math.sin(phi) * radii[1],
                             math.cos(phi) * radii[0], math.cos(phi) * radii[2]))
        self.shell(name, profiles, zone, bone, center, segments)

    def tube(self, name, points, radius, zone, bone, segments=8):
        points = np.asarray(points, dtype=np.float64)
        vertices, uv, faces = [], [], []
        for j, point in enumerate(points):
            tangent = points[min(j + 1, len(points) - 1)] - points[max(j - 1, 0)]
            tangent /= max(np.linalg.norm(tangent), 1e-12)
            axis = np.array([0, 0, 1.0]) if abs(tangent[2]) < 0.9 else np.array([0, 1.0, 0])
            x = np.cross(tangent, axis)
            x /= max(np.linalg.norm(x), 1e-12)
            z = np.cross(x, tangent)
            for i in range(segments + 1):
                angle = 2 * math.pi * i / segments
                vertices.append(point + radius * (math.sin(angle) * x + math.cos(angle) * z))
                uv.append((i / segments, j / (len(points) - 1)))
                if j < len(points) - 1 and i < segments:
                    a = j * (segments + 1) + i
                    b = a + segments + 1
                    faces.extend(((a, a + 1, b), (a + 1, b + 1, b)))
        self.add(name, vertices, uv, faces, zone, bone)

    def cloth(self, name, rows, zone, binding, columns=12):
        """Tailored, pleated panel with a real back face; no alpha or cloth solver."""
        vertices, uv, faces = [], [], []
        for row, (y, left, right, depth) in enumerate(rows):
            for col in range(columns + 1):
                u = col / columns
                x = left + (right - left) * u
                z = depth + 0.008 * math.cos(u * 6 * math.pi) * row / (len(rows) - 1)
                vertices.append((x, y, z))
                uv.append((u, row / (len(rows) - 1)))
                if row < len(rows) - 1 and col < columns:
                    a = row * (columns + 1) + col
                    b = a + columns + 1
                    faces.extend(((a, b, a + 1), (a + 1, b, b + 1)))
        # Front/back use independent vertices for correctly oriented normals.
        self.add(name, vertices, uv, faces, zone, binding)
        back = [(x, y, z - 0.003) for x, y, z in vertices]
        self.add(name + " lining", back, uv, [(c, b, a) for a, b, c in faces], zone, binding)


def blend_by_height(low, high, y0, y1):
    def bind(point):
        t = float(np.clip((point[1] - y0) / (y1 - y0), 0, 1))
        return {low: 1.0 - t, high: t}
    return bind
