"""Hard-surface mesh authoring for the skill focus recipe (authoring only).

Pure standard library on purpose (`docs/agent_skills/04` §2): the sandbox does not
guarantee NumPy or trimesh, and every byte of a shipped asset has to be reproducible
from this file alone, so no floating point is handed to a third-party package.

Units are metres, +Y up, +Z forward. A `Mesh` is a list of `Part`s; a part is one
authored island: its own triangles, its own UV mapping and one material recipe. Keeping
parts separate is what lets the atlas painter generate a real height field per part
(panel splits, rivets, engraved sigils) and derive a matching normal + ORM map, which
is how the shipped modular environment sets were built.

Winding is CCW seen from outside. Normals are area weighted and welded by position, then
split per hard-edge angle group, so a lathe barrel shades smooth while its machined
shoulders stay crisp, with no authored shading seams.
"""
from __future__ import annotations

import math

TWO_PI = math.tau
HARD_ANGLE_DEG = 42.0
WELD_GRID = 100000.0        # 10 microns: coincident vertices share one shading group


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _unit(value):
    return 0.0 if value < 0.0 else 1.0 if value > 1.0 else value


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _length2(a):
    return a[0] * a[0] + a[1] * a[1] + a[2] * a[2]


def _norm(a):
    length = math.sqrt(_length2(a))
    return _scale(a, 1.0 / length) if length > 1e-12 else (0.0, 1.0, 0.0)


def _rot_x(angle):
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    return (1.0, 0.0, 0.0, 0.0, cos_a, -sin_a, 0.0, sin_a, cos_a)


def _rot_y(angle):
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    return (cos_a, 0.0, sin_a, 0.0, 1.0, 0.0, -sin_a, 0.0, cos_a)


def _rot_z(angle):
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    return (cos_a, -sin_a, 0.0, sin_a, cos_a, 0.0, 0.0, 0.0, 1.0)


def _mat3_apply(m, v):
    return (m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
            m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
            m[6] * v[0] + m[7] * v[1] + m[8] * v[2])


def _mat3_compose(a, b):
    """Row-major 3x3 product, so rotations can be chained before any vertex is touched."""
    rows = [a[0:3], a[3:6], a[6:9]]
    columns = [[b[0], b[3], b[6]], [b[1], b[4], b[7]], [b[2], b[5], b[8]]]
    return tuple(sum(row[k] * column[k] for k in range(3)) for row in rows for column in columns)


def transform(translation=(0.0, 0.0, 0.0), rotation=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    """Return a vertex function: scale, then Z-X-Y euler rotation, then translate."""
    matrix = _mat3_compose(_rot_y(rotation[1]), _mat3_compose(_rot_x(rotation[0]), _rot_z(rotation[2])))
    sx, sy, sz = scale

    def apply(point):
        rotated = _mat3_apply(matrix, (point[0] * sx, point[1] * sy, point[2] * sz))
        return _add(rotated, translation)

    return apply


def chain(*transforms):
    """Compose transforms, outermost first (applied to a vertex in reverse order)."""

    def apply(point):
        for item in reversed(transforms):
            point = item(point)
        return point

    return apply


class Part:
    """One authored surface patch: geometry, its 0..1 UVs and its material request."""

    def __init__(self, name, family, spec=None, detail=None):
        self.name = name
        self.family = family        # a name in material.FAMILIES
        self.spec = dict(spec or {})    # family parameters (colour, band, grain ...)
        self.detail = dict(detail or {})  # shared machined marks (bands, fasteners ...)
        # Parts asking for the same family + spec + detail are painted once and share one
        # atlas island, so a ring of eight identical bolts costs one tile.
        self.island = None
        self.verts = []
        self.uvs = []
        self.tris = []
        self.normals = []
        self.tangents = []
        self.notes = {}
        self.closed = False         # sealed hull: safe to back-face cull
        self.hard = set()           # triangle indices that keep a hard edge (generator caps)

    def vertex(self, position, uv):
        """Append a vertex; the part owns the whole 0..1 frame, so a generator rounding a hair
        outside it is snapped back rather than left to fail the pack check."""
        self.verts.append((float(position[0]), float(position[1]), float(position[2])))
        self.uvs.append((_unit(float(uv[0])), _unit(float(uv[1]))))
        return len(self.verts) - 1

    def translate_from(self, mark, delta):
        """Move only the vertices a generator added after `mark` (its own `at` offset)."""
        if not any(delta):
            return
        for index in range(mark, len(self.verts)):
            x, y, z = self.verts[index]
            self.verts[index] = (x + delta[0], y + delta[1], z + delta[2])

    def bounds(self):
        """The part's own AABB, used by the outward-winding vote for open shells."""
        xs = [point[0] for point in self.verts]
        ys = [point[1] for point in self.verts]
        zs = [point[2] for point in self.verts]
        return ([min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)])

    def signed_volume(self):
        """Sum of the tetrahedra the triangles sweep out from the origin.

        Positive exactly when the winding is CCW-as-seen-from-outside — glTF's rule — so one
        number per part is enough to audit a whole hull."""
        total = 0.0
        for a, b, c in self.tris:
            pa, pb, pc = self.verts[a], self.verts[b], self.verts[c]
            total += (pa[0] * (pb[1] * pc[2] - pb[2] * pc[1])
                      + pa[1] * (pb[2] * pc[0] - pb[0] * pc[2])
                      + pa[2] * (pb[0] * pc[1] - pb[1] * pc[0]))
        return total / 6.0

    def scale_from(self, mark, about, factor):
        """Anisotropic scale about a pivot: squash a sphere into a lens without moving it."""
        wide, tall, deep = factor if isinstance(factor, tuple) else (factor, factor, factor)
        for index in range(mark, len(self.verts)):
            x, y, z = self.verts[index]
            self.verts[index] = (about[0] + (x - about[0]) * wide,
                                 about[1] + (y - about[1]) * tall,
                                 about[2] + (z - about[2]) * deep)

    def quad(self, a, b, c, d):
        self.tris.append((a, b, c))
        self.tris.append((a, c, d))

    def strip(self, rows):
        """rows: index rings of equal length, wound consistently, top to bottom."""
        for row in range(len(rows) - 1):
            upper, lower = rows[row], rows[row + 1]
            for col in range(len(upper)):
                nxt = (col + 1) % len(upper)
                self.quad(upper[col], upper[nxt], lower[nxt], lower[col])

    def fan(self, centre, ring, flip=False):
        for index in range(len(ring)):
            nxt = (index + 1) % len(ring)
            self.tris.append((centre, nxt, ring[index]) if flip else (centre, ring[index], nxt))


class Mesh:
    """Parts plus the derived shading data (normals, tangents) and atlas packing."""

    def __init__(self, name, atlas=512, tile=128):
        self.name = name
        self.atlas = atlas
        self.tile = tile
        self.parts = []
        self.nodes = []             # extra glTF nodes authored by the recipe (sockets)
        self.extras = {}

    # ------------------------------------------------------------------ parts

    def socket(self, name, position):
        """Named glTF node (a cast socket / mount point) authored alongside the mesh."""
        self.nodes.append({'name': name, 'translation': [float(position[0]), float(position[1]), float(position[2])]})

    def part(self, name, family, spec=None, detail=None):
        if any(existing.name == name for existing in self.parts):
            raise ValueError(f"duplicate part name {name} in {self.name}")
        new = Part(name, family, spec, detail)
        self.parts.append(new)
        return new

    def island_key(self, part):
        """The material identity of a part: what the atlas deduplicates on."""
        return '%s|%s|%s' % (part.family, repr(sorted(part.spec.items())), repr(sorted(part.detail.items())))

    def copy(self, name, source, place=None, family=None):
        new = self.part(name, family if family is not None else source.family,
                        source.spec, source.detail)
        new.notes = dict(source.notes)
        new.closed = source.closed
        new.hard = set(source.hard)
        for position, uv in zip(source.verts, source.uvs):
            new.verts.append(place(position) if place else position)
            new.uvs.append(uv)
        new.tris = list(source.tris)
        return new

    def array(self, name, source, count, radius=0.0, phase=0.0, keep=False):
        """Radially array a part about +Y (bolt rings, vanes, rams, blades, coils)."""
        for index in range(count):
            angle = phase + TWO_PI * index / count
            yaw = _rot_y(angle)

            def place(point, yaw=yaw, radius=radius):
                moved = _add(point, (radius, 0.0, 0.0)) if radius else point
                return _mat3_apply(yaw, moved)

            self.copy(f"{name}_{index}", source, place)
        if not keep:
            self.parts.remove(source)

    def transform_part(self, name, place):
        """Re-seat a part in place: author at the origin, then move the finished piece."""
        for part in self.parts:
            if part.name == name:
                part.verts = [place(point) for point in part.verts]
                return part
        raise ValueError(f"no part named {name} in {self.name}")

    def mirror(self, name, source, axis=0, keep=True):
        """Mirrored twin of a part: asymmetric halves stay identical, not re-authored."""
        flip = [(-1.0, 1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, -1.0)][axis]

        def place(point, flip=flip):
            return (point[0] * flip[0], point[1] * flip[1], point[2] * flip[2])

        moved = self.copy(name, source, place)
        # Flipping handedness reverses winding: restore CCW.
        moved.tris = [(a, c, b) for a, b, c in source.tris]
        if not keep:
            self.parts.remove(source)
        return moved

    # ------------------------------------------------------------------ checks

    def triangle_count(self):
        return sum(len(part.tris) for part in self.parts)

    def vertex_count(self):
        return sum(len(part.verts) for part in self.parts)

    def bounds(self):
        points = [v for part in self.parts for v in part.verts]
        if not points:
            raise ValueError(f"{self.name}: no vertices authored")
        low = [min(point[i] for point in points) for i in range(3)]
        high = [max(point[i] for point in points) for i in range(3)]
        return low, high

    def validate(self):
        """Structural contract every shipped model must satisfy."""
        problems = []
        try:
            low, high = self.bounds()
        except ValueError as exc:
            return [str(exc)]
        for part, label in ((low, 'min'), (high, 'max')):
            if not all(math.isfinite(value) for value in part):
                problems.append(f"{self.name}: non-finite bounds")
                break
        if high[1] - low[1] > 1.9 or max(high[0] - low[0], high[2] - low[2]) > 1.9:
            problems.append(f"{self.name}: prop must fit the 1.9 m display envelope")
        if low[1] < -0.001:
            problems.append(f"{self.name}: geometry dips below the floor plane ({low[1]:.4f})")
        for part in self.parts:
            if not part.tris or not part.verts:
                problems.append(f"{part.name}: empty part")
                continue
            if len(part.normals) != len(part.verts):
                problems.append(f"{part.name}: shade() not applied")
            for tri in part.tris:
                if min(tri) < 0 or max(tri) >= len(part.verts):
                    problems.append(f"{part.name}: index out of range")
                    break
                a, b, c = (part.verts[i] for i in tri)
                if _length2(_cross(_sub(b, a), _sub(c, a))) < 1e-16:
                    problems.append(f"{part.name}: degenerate triangle")
                    break
            else:
                open_edges, flipped, doubled = self._edge_audit(part)
                if part.closed and part.signed_volume() <= 0.0:
                    problems.append(f'{part.name}: sealed hull is wound inwards '
                                    f'(signed volume {part.signed_volume():.6f})')
                if part.closed and open_edges:
                    problems.append(f"{part.name}: {open_edges} boundary edges on a sealed hull")
                if doubled:
                    problems.append(f"{part.name}: {doubled} edges shared by more than two faces")
                if flipped:
                    problems.append(f"{part.name}: {flipped} faces wound against their neighbour")
            for index, uv in enumerate(part.uvs):
                if not all(0.0 <= value <= 1.0 for value in uv):
                    problems.append(f"{part.name}: UV {index} outside 0..1 after packing")
                    break
        if not self.parts:
            problems.append(f"{self.name}: nothing authored")
        return problems

    @staticmethod
    def _edge_audit(part):
        """Welded edge census: a sealed hull has no boundary edge and no flipped face.

        Counting by position rather than index is the point — a UV seam legitimately
        splits a vertex, and that must not read as a hole.
        """
        welds = {}
        welded = []
        for position in part.verts:
            key = tuple(round(value * WELD_GRID) for value in position)
            slot = welds.get(key)
            if slot is None:
                slot = len(welds)
                welds[key] = slot
            welded.append(slot)
        uses = {}
        for index, (a, b, c) in enumerate(part.tris):
            for edge in ((a, b), (b, c), (c, a)):
                key = (welded[edge[0]], welded[edge[1]])
                if key[0] == key[1]:
                    continue
                uses.setdefault(tuple(sorted(key)), []).append((key, index))
        boundary = doubled = flipped = 0
        for instances in uses.values():
            if len(instances) == 1:
                boundary += 1
            elif len(instances) > 2:
                doubled += 1
            elif instances[0][0] == instances[1][0]:
                flipped += 1
        return boundary, flipped, doubled

    # ------------------------------------------------------------------ shading

    def orient_outward(self):
        """Repair winding so every part faces out, which is what back-face culling needs.

        A sealed hull is decided exactly (signed volume). An open shell — a lathe sleeve, a
        swept duct — has no volume to test, so its faces are voted on instead: a normal that
        points away from the part's own centre is an outside normal.
        """
        repaired = []
        for part in self.parts:
            if not part.verts or not part.tris:
                continue
            if part.closed:
                outward = part.signed_volume()
            else:
                low, high = part.bounds()
                middle = tuple((low[axis] + high[axis]) * 0.5 for axis in range(3))
                outward = 0.0
                for a, b, c in part.tris:
                    pa, pb, pc = part.verts[a], part.verts[b], part.verts[c]
                    face = _cross(_sub(pb, pa), _sub(pc, pa))
                    pivot = ((pa[0] + pb[0] + pc[0]) / 3.0 - middle[0],
                             (pa[1] + pb[1] + pc[1]) / 3.0 - middle[1],
                             (pa[2] + pb[2] + pc[2]) / 3.0 - middle[2])
                    outward += _dot(face, pivot)
            if outward < 0.0:
                part.tris = [(a, c, b) for a, b, c in part.tris]
                repaired.append(part.name)
        return repaired

    def shade(self, hard_angle=HARD_ANGLE_DEG):
        """Per-part smooth-by-angle normals plus matching tangent frames."""
        cos_limit = math.cos(math.radians(hard_angle))
        for part in self.parts:
            weld_of = [0] * len(part.verts)
            weld_count = 0
            welds = {}
            for index, position in enumerate(part.verts):
                key = tuple(round(value * WELD_GRID) for value in position)
                slot = welds.get(key)
                if slot is None:
                    slot = weld_count
                    welds[key] = slot
                    weld_count += 1
                weld_of[index] = slot
            clusters = {}
            for face, tri in enumerate(part.tris):
                # Flat caps (the fan each generator closes a hull with) never share a shading
                # group with the wall: real hard-surface workflow splits them exactly there, and
                # welding a chamfer into a plate instead turns every deck into a pinwheel.
                side = 1 if face in part.hard else 0
                a, b, c = (part.verts[i] for i in tri)
                face_normal = _cross(_sub(b, a), _sub(c, a))     # length = twice the area
                if _length2(face_normal) < 1e-18:
                    continue
                uvs = [part.uvs[i] for i in tri]
                edge1, edge2 = _sub(b, a), _sub(c, a)
                duv1 = (uvs[1][0] - uvs[0][0], uvs[1][1] - uvs[0][1])
                duv2 = (uvs[2][0] - uvs[0][0], uvs[2][1] - uvs[0][1])
                determinant = duv1[0] * duv2[1] - duv1[1] * duv2[0]
                if abs(determinant) > 1e-12:
                    factor = 1.0 / determinant
                    tangent = _scale(_add(_scale(edge2, duv1[1]), _scale(edge1, -duv2[1])), factor)
                    bitangent = _scale(_add(_scale(edge1, duv2[1]), _scale(edge2, -duv1[0])), factor)
                else:
                    tangent = _cross(face_normal, (0.0, 1.0, 0.0))
                    bitangent = _cross(face_normal, tangent)
                unit = _norm(face_normal)
                for vertex in tri:
                    bucket = clusters.setdefault((weld_of[vertex], side), [])
                    target = None
                    for cluster in bucket:
                        if _dot(unit, cluster['dir']) > cos_limit:
                            target = cluster
                            break
                    if target is None:
                        target = {'dir': unit, 'normal': (0.0, 0.0, 0.0),
                                  'tangent': (0.0, 0.0, 0.0), 'bitangent': (0.0, 0.0, 0.0),
                                  'vertices': []}
                        bucket.append(target)
                    target['normal'] = _add(target['normal'], face_normal)
                    target['tangent'] = _add(target['tangent'], tangent)
                    target['bitangent'] = _add(target['bitangent'], bitangent)
                    target['vertices'].append(vertex)
            normals = [None] * len(part.verts)
            tangents = [None] * len(part.verts)
            for bucket in clusters.values():
                for cluster in bucket:
                    normal = _norm(cluster['normal'])
                    tangent = _sub(cluster['tangent'], _scale(normal, _dot(cluster['tangent'], normal)))
                    tangent = _norm(tangent) if _length2(tangent) > 1e-14 else _norm(
                        _cross(normal, (0.0, 1.0, 0.0) if abs(normal[1]) < 0.9 else (1.0, 0.0, 0.0)))
                    handed = -1.0 if _dot(_cross(normal, tangent), cluster['bitangent']) < 0 else 1.0
                    for vertex in cluster['vertices']:
                        normals[vertex] = normal
                        tangents[vertex] = (tangent[0], tangent[1], tangent[2], handed)
            part.normals = [n if n is not None else (0.0, 1.0, 0.0) for n in normals]
            part.tangents = [t if t is not None else (1.0, 0.0, 0.0, 1.0) for t in tangents]
        return self
