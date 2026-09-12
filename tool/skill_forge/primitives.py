"""Deterministic hard-surface generators for the skill focus recipe.

Every generator writes straight into a `Part` (see `mesh.py`) so the recipe keeps control
of the transform, the material and the UV frame. All of them close their own caps, so a
shipped prop is a sealed hull a mobile renderer can back-face cull.

UV frames are parametric on purpose, never auto-projected: the atlas painter draws each
part's height field in the very same 0..1 space (`texture.py`), so "`u` around / `v`
along" a lathe means machined bands, bolt rings and wear gradients land exactly where the
geometry expects them. Caps take their own ring vertices and a planar frame, which is also
what keeps a chamfer's highlight crisp instead of smeared across a shared seam.
"""
from __future__ import annotations

import math

TWO_PI = math.tau


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _clamp(value, low, high):
    return low if value < low else high if value > high else value


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(a, fallback=(0.0, 0.0, 1.0)):
    length = math.sqrt(_dot(a, a))
    return _scale(a, 1.0 / length) if length > 1e-12 else fallback


# Planar helpers: outlines live in the XZ plane and are carried as 2-tuples, so the
# polygon ops get their own 2D arithmetic instead of tripping over the 3D vectors above.
def _sub2(a, b):
    return (a[0] - b[0], a[1] - b[1])


def _add2(a, b):
    return (a[0] + b[0], a[1] + b[1])


def _dot2(a, b):
    return a[0] * b[0] + a[1] * b[1]



def _norm2(a, fallback=(0.0, 0.0)):
    length = math.hypot(*a)
    return (a[0] / length, a[1] / length) if length > 1e-12 else fallback


# ------------------------------------------------------------------ outlines


def dedupe(points, tolerance=1e-7):
    out = []
    for point in points:
        if out and abs(point[0] - out[-1][0]) < tolerance and abs(point[1] - out[-1][1]) < tolerance:
            continue
        out.append(point)
    if len(out) > 2 and abs(out[0][0] - out[-1][0]) < tolerance and abs(out[0][1] - out[-1][1]) < tolerance:
        out.pop()
    return out


def regular(count, radius, rotation=0.0):
    """CCW regular polygon in the XZ plane as seen from +Y."""
    return [(math.cos(rotation + TWO_PI * index / count) * radius,
             math.sin(rotation + TWO_PI * index / count) * radius) for index in range(count)]




def gear_outline(teeth, root_radius, tip_radius, rotation=0.0, tooth_width=0.44):
    """Sprocket outline with flat-topped teeth: drive rings, throttle collars, cogs."""
    points = []
    span = TWO_PI / teeth
    for index in range(teeth):
        base = rotation + span * index
        for fraction, radius in ((0.0, root_radius), (0.5 - tooth_width / 2.0, root_radius),
                                 (0.5 - tooth_width / 4.0, tip_radius), (0.5 + tooth_width / 4.0, tip_radius),
                                 (0.5 + tooth_width / 2.0, root_radius), (1.0, root_radius)):
            angle = base + span * fraction
            points.append((math.cos(angle) * radius, math.sin(angle) * radius))
    return dedupe(points)


def airfoil(chord, thickness, camber=0.0, trailing=0.05, rows=8):
    """Closed lens outline, nose at +X: vanes, blades, impeller fins, dash strakes."""
    top, bottom = [], []
    for index in range(rows + 1):
        t = index / rows
        x = -chord / 2.0 + chord * t
        half = thickness / 2.0 * math.sin(math.acos(_clamp(1.0 - 2.0 * t, -1.0, 1.0))) ** 0.7
        half = max(half, thickness * trailing)
        bend = camber * math.sin(math.pi * t)
        top.append((x, bend + half))
        bottom.append((x, bend - half))
    return dedupe(top + bottom[::-1])


def inset(polygon, distance):
    """Offset a closed outline inward by a fixed distance, exactly.

    Every new vertex is where the two inward-offset edges that meet there intersect, which is the
    textbook miter and is stable at the near-straight vertices a fillet leaves behind. Walking a
    bisector instead divides by an angle that goes to zero there, so those points never move,
    the chamfer ring folds over itself, and any cap fanned off that ring alternates inwards.
    """
    count = len(polygon)
    area = _signed_area(polygon)
    facing = 1.0 if area > 0.0 else -1.0     # a CCW outline keeps its interior to the left
    lines = []
    for index in range(count):
        start, end = polygon[index], polygon[(index + 1) % count]
        edge = _sub2(end, start)
        length = math.hypot(edge[0], edge[1])
        if length < 1e-12:
            continue
        normal = (-edge[1] / length, edge[0] / length)
        if facing < 0.0:
            normal = (-normal[0], -normal[1])
        lines.append(((start[0] + normal[0] * distance, start[1] + normal[1] * distance), edge))
    if len(lines) < 3:
        return list(polygon)
    out = []
    for index in range(len(lines)):
        (point, direction) = lines[index - 1]
        (other, edge) = lines[index]
        cross = direction[0] * edge[1] - direction[1] * edge[0]
        if abs(cross) < 1e-9:                 # parallel edges: the offset point already agrees
            out.append(point)
            continue
        step = ((other[0] - point[0]) * edge[1] - (other[1] - point[1]) * edge[0]) / cross
        out.append((point[0] + direction[0] * step, point[1] + direction[1] * step))
    if _signed_area(out) * area <= 0.0 or len(out) != len(lines):
        # Collapsed inset (asking for more chamfer than the outline can carry): scale instead,
        # which cannot fold, so the hull still closes.
        centre = (sum(p[0] for p in polygon) / count, sum(p[1] for p in polygon) / count)
        radius = max(math.hypot(p[0] - centre[0], p[1] - centre[1]) for p in polygon)
        factor = max(0.05, (radius - distance) / max(radius, 1e-9))
        return [(centre[0] + (p[0] - centre[0]) * factor, centre[1] + (p[1] - centre[1]) * factor)
                for p in polygon]
    return out


def round_corners(polygon, radius, segments=2):
    """Fillet a convex outline: a machined corner catches a highlight, a mitre does not."""
    count = len(polygon)
    out = []
    for index in range(count):
        point = polygon[index]
        to_prev = _norm2(_sub2(polygon[(index - 1) % count], point), (1.0, 0.0))
        to_next = _norm2(_sub2(polygon[(index + 1) % count], point), (0.0, 1.0))
        length_prev = math.hypot(*_sub2(polygon[(index - 1) % count], point))
        length_next = math.hypot(*_sub2(polygon[(index + 1) % count], point))
        theta = math.acos(_clamp(_dot2(to_prev, to_next), -1.0, 1.0))
        if theta < 0.06 or abs(math.pi - theta) < 0.06:
            out.append(point)
            continue
        half = theta / 2.0
        cut = min(radius / math.tan(half), length_prev * 0.45, length_next * 0.45)
        arc_radius = cut * math.tan(half)
        centre_step = arc_radius / math.sin(half)
        direction = _norm2(_add2(to_prev, to_next), (1.0, 0.0))
        centre = (point[0] + direction[0] * centre_step, point[1] + direction[1] * centre_step)
        start = (point[0] + to_prev[0] * cut, point[1] + to_prev[1] * cut)
        end = (point[0] + to_next[0] * cut, point[1] + to_next[1] * cut)
        start_angle = math.atan2(start[1] - centre[1], start[0] - centre[0])
        end_angle = math.atan2(end[1] - centre[1], end[0] - centre[0])
        sweep = (end_angle - start_angle + math.pi) % TWO_PI - math.pi
        span = math.hypot(start[0] - centre[0], start[1] - centre[1])
        for step in range(segments + 1):
            angle = start_angle + sweep * step / segments
            out.append((centre[0] + math.cos(angle) * span, centre[1] + math.sin(angle) * span))
    return dedupe(out)


def _signed_area(polygon):
    total = 0.0
    for index in range(len(polygon)):
        x0, y0 = polygon[index]
        x1, y1 = polygon[(index + 1) % len(polygon)]
        total += x0 * y1 - x1 * y0
    return total / 2.0


def _bounds(polygon):
    return (min(p[0] for p in polygon), max(p[0] for p in polygon),
            min(p[1] for p in polygon), max(p[1] for p in polygon))


def _perimeter(polygon):
    total = 0.0
    for index in range(len(polygon)):
        total += math.dist(polygon[index], polygon[(index + 1) % len(polygon)])
    return max(total, 1e-9)


# ------------------------------------------------------------------ generators


def _wall_runs_forward(part, a, b):
    """Does an already-built face traverse the edge a->b? (True) or b->a? (False)"""
    for tri in part.tris:
        for index in range(3):
            if tri[index] == a and tri[(index + 1) % 3] == b:
                return True
            if tri[index] == b and tri[(index + 1) % 3] == a:
                return False
    return False


def _cap_fan(part, ring, centre_point, uv, reference=None):
    """Fan a cap onto an already-built wall, winding it against that wall's shared edges.

    The wall is the only authority worth asking: `slab`, `lathe` and `tube` each lay their quads
    out in a different order, and a cap that traverses a shared edge the *same* way as its wall
    leaves the hull inconsistently wound, so half the cap ends up interpolating shading normals
    from the inside of the part. A sealed hull has to run each shared edge in opposite
    directions on its two faces, which is exactly what this enforces.
    """
    centre = part.vertex(centre_point, uv)
    if len(ring) < 2:
        return
    first = len(part.tris)
    # `slab` gives the cap its own vertices so the top view can own a UV frame, which means the
    # wall has no edge between those indices to read: `reference` names the wall's own ring.
    probe = list(reference) if reference is not None else list(ring)
    same_way = _wall_runs_forward(part, probe[0], probe[1])
    for index in range(len(ring)):
        nxt = (index + 1) % len(ring)
        part.tris.append((centre, ring[nxt], ring[index]) if same_way else (centre, ring[index], ring[nxt]))
        part.hard.add(len(part.tris) - 1)


def lathe(part, profile, segments=32, squash=1.0, cap=True, twist=0.0, at=(0.0, 0.0, 0.0),
          wall=0.0):
    """Revolve a `(radius, height)` profile about +Y, bottom row first.

    A row of zero radius is a pole, so domes, spikes and needles need no special case.
    `twist` turns each successive profile row a fraction of a turn, which reads as a wound
    coil or a fluted spindle rather than a smeared band.

    `wall` gives an open profile a real thickness by returning it on itself, which is what turns
    a single-sided sleeve into a sealed shell: a collar or an insulator skirt without a wall is
    see-through from the top, and the far side of its own interior is what the player then sees.
    """
    rows = [(float(radius), float(height)) for radius, height in profile]
    if len(rows) < 2:
        raise ValueError(f"{part.name}: a lathe needs at least two profile rows")
    if wall > 0.0 and rows[0][0] > wall and rows[-1][0] > wall:
        inward = [(max(radius - wall, 0.0), height) for radius, height in rows]
        rows = rows + list(reversed(inward)) + [rows[0]]
    mark = len(part.verts)
    lengths = [0.0]
    for index in range(1, len(rows)):
        lengths.append(lengths[-1] + math.hypot(rows[index][0] - rows[index - 1][0],
                                                rows[index][1] - rows[index - 1][1]))
    span = max(lengths[-1], 1e-9)
    rings = []
    for row, (radius, height) in enumerate(rows):
        offset = TWO_PI * twist * row / max(len(rows) - 1, 1)
        ring = []
        for column in range(segments):
            angle = TWO_PI * column / segments + offset
            if radius <= 1e-9:
                ring.append(part.vertex((0.0, height, 0.0), (0.5, lengths[row] / span)))
            else:
                ring.append(part.vertex((math.cos(angle) * radius, height, math.sin(angle) * radius * squash),
                                        (column / segments, lengths[row] / span)))
        rings.append(ring)
    for row in range(len(rings) - 1):
        upper, lower = rings[row], rings[row + 1]
        top_pole = rows[row][0] <= 1e-9
        bottom_pole = rows[row + 1][0] <= 1e-9
        for column in range(segments):
            nxt = (column + 1) % segments
            if top_pole:
                part.tris.append((lower[nxt], lower[column], upper[column]))
            elif bottom_pole:
                part.tris.append((upper[column], upper[nxt], lower[column]))
            else:
                part.quad(upper[column], upper[nxt], lower[nxt], lower[column])
    if cap:
        for index, ring, bottom in ((0, rings[0], True), (len(rows) - 1, rings[-1], False)):
            radius, height = rows[index]
            if radius <= 1e-9:
                continue
            _cap_fan(part, ring, (0.0, height, 0.0), (0.5, 0.0 if bottom else 1.0))
    part.translate_from(mark, at)
    part.closed = bool(cap) or wall > 0.0
    return part


def slab(part, outline, y0, y1, bevel=0.0, taper=0.0, cap=True, at=(0.0, 0.0, 0.0)):
    """Extrude a closed XZ outline along +Y, with an optional chamfer and linear taper.

    Plates, brackets, hex hubs, gear collars and fins are all this call with a different
    outline. The chamfer is real geometry, so its highlight survives any camera angle;
    `taper` shrinks the outline toward the top for a horn, a blade or a spike base.
    """
    outline = dedupe(outline)
    if len(outline) < 3:
        raise ValueError(f"{part.name}: a slab outline needs three points")
    low_x, high_x, low_y, high_y = _bounds(outline)
    span_x, span_y = max(high_x - low_x, 1e-9), max(high_y - low_y, 1e-9)
    centre_x, centre_z = (low_x + high_x) / 2.0, (low_y + high_y) / 2.0
    height = y1 - y0
    if height <= 0.0:
        raise ValueError(f"{part.name}: slab needs y1 above y0")
    bevel = min(bevel, height * 0.45, min(span_x, span_y) * 0.45)
    chamfer = inset(outline, bevel) if bevel > 1e-6 else None
    levels = [y0, y0 + bevel, y1 - bevel, y1] if bevel > 1e-6 else [y0, y1]
    inset_rows = [True, False, False, True] if bevel > 1e-6 else [False, False]
    perimeter = _perimeter(outline)
    walked = []
    total = 0.0
    for index, point in enumerate(outline):
        if index:
            total += math.dist(point, outline[index - 1])
        walked.append(total / perimeter)
    mark = len(part.verts)
    rings = []
    for level, use_inset in zip(levels, inset_rows):
        shrink = 1.0 - taper * ((level - y0) / height)
        source = chamfer if (use_inset and chamfer) else outline
        ring = []
        for index, point in enumerate(source):
            ring.append(part.vertex((point[0] * shrink, level, point[1] * shrink),
                                    (walked[index] if len(source) == len(walked) else 0.5,
                                     (level - y0) / height)))
        rings.append(ring)
    for row in range(len(rings) - 1):
        upper, lower = rings[row], rings[row + 1]
        for column in range(len(upper)):
            nxt = (column + 1) % len(upper)
            part.quad(upper[column], upper[nxt], lower[nxt], lower[column])
    if cap:
        # A cap is planar, so it gets its own ring vertices and a bbox-normalised frame: the
        # wall keeps a perimeter UV, the cap keeps a readable top view. Both share positions,
        # so the hull stays sealed even where the outline is a 26-point gear.
        for ring, bottom in ((rings[0], True), (rings[-1], False)):
            points = [part.verts[index] for index in ring]
            level = points[0][1]
            low_px = min(point[0] for point in points)
            high_px = max(point[0] for point in points)
            low_pz = min(point[2] for point in points)
            high_pz = max(point[2] for point in points)
            mid_x, mid_z = (low_px + high_px) / 2.0, (low_pz + high_pz) / 2.0
            wide = max(high_px - low_px, 1e-6)
            deep = max(high_pz - low_pz, 1e-6)
            cap_ring = [part.vertex(point, (0.5 + (point[0] - mid_x) / wide, 0.5 + (point[2] - mid_z) / deep))
                        for point in points]
            _cap_fan(part, cap_ring, (mid_x, level, mid_z), (0.5, 0.5), reference=ring)
    part.translate_from(mark, at)
    part.closed = bool(cap)
    return part


def tube(part, path, radii, segments=12, cap=True, squash=1.0, twist=0.0, at=(0.0, 0.0, 0.0)):
    """Sweep a circular section (radius per point) along a polyline: struts, hoses, prongs.

    Frames use minimum-twistance parallel transport, so a bent hose never flips its UV
    seam and a coiled run keeps its ribbing evenly spaced along the arc.
    """
    if len(path) < 2:
        raise ValueError(f"{part.name}: a tube needs at least two path points")
    if len(radii) == 1:
        radii = list(radii) * len(path)
    if len(radii) != len(path):
        raise ValueError(f"{part.name}: a tube needs one radius per path point")
    mark = len(part.verts)
    lengths = [0.0]
    for index in range(1, len(path)):
        lengths.append(lengths[-1] + math.dist(path[index], path[index - 1]))
    span = max(lengths[-1], 1e-9)
    start_forward = _norm(_sub(path[1], path[0]), (0.0, 0.0, 1.0))
    up = (0.0, 1.0, 0.0) if abs(start_forward[1]) < 0.9 else (1.0, 0.0, 0.0)
    rings = []
    previous_side = None
    for index, point in enumerate(path):
        forward = _norm(_sub(path[min(index + 1, len(path) - 1)], path[max(index - 1, 0)]), (0.0, 0.0, 1.0))
        side = _norm(_cross(forward, up), (1.0, 0.0, 0.0))
        if previous_side is not None and _dot(side, previous_side) < 0.0:
            side = _scale(side, -1.0)
        previous_side = side
        normal = _norm(_cross(side, forward), (0.0, 1.0, 0.0))
        radius = radii[index]
        along = lengths[index] / span
        ring = []
        for column in range(segments):
            angle = TWO_PI * column / segments + TWO_PI * twist * along
            offset = _add(_scale(side, math.cos(angle) * radius),
                          _scale(normal, math.sin(angle) * radius * squash))
            ring.append(part.vertex(_add(point, offset), (column / segments, along)))
        rings.append(ring)
    for row in range(len(rings) - 1):
        upper, lower = rings[row], rings[row + 1]
        for column in range(segments):
            nxt = (column + 1) % segments
            part.quad(upper[column], upper[nxt], lower[nxt], lower[column])
    if cap:
        _cap_fan(part, rings[0], path[0], (0.5, 0.0))
        _cap_fan(part, rings[-1], path[-1], (0.5, 1.0))
    part.translate_from(mark, at)
    part.closed = bool(cap)
    return part


def revolve(part, loop, radius, segments=40, squash=1.0, at=(0.0, 0.0, 0.0)):
    """Sweep a closed profile loop around a centre circle: collars, O-rings, top loads.

    `loop` holds `(radial_offset, height_offset)` pairs in the profile plane, so a
    rectangle becomes a flat retaining ring and a circle becomes a torus.
    """
    loop = dedupe([(float(a), float(b)) for a, b in loop])
    if len(loop) < 3:
        raise ValueError(f"{part.name}: a revolve profile needs three points")
    mark = len(part.verts)
    grid = []
    for column in range(segments):
        angle = TWO_PI * column / segments
        ring = []
        for row, (radial, height) in enumerate(loop):
            reach = radius + radial
            point = (math.cos(angle) * reach, height, math.sin(angle) * reach * squash)
            ring.append(part.vertex(point, (column / segments, row / len(loop))))
        grid.append(ring)
    for column in range(segments):
        nxt = (column + 1) % segments
        for row in range(len(loop)):
            below = (row + 1) % len(loop)
            part.quad(grid[column][row], grid[nxt][row], grid[nxt][below], grid[column][below])
    part.translate_from(mark, at)
    part.closed = True
    return part


def sphere(part, centre, radius, segments=24, rings=12, squash=(1.0, 1.0, 1.0)):
    """UV sphere for reactor cores and lenses; the poles are true single vertices."""
    profile = []
    for index in range(rings + 1):
        phi = -math.pi / 2.0 + math.pi * index / rings
        profile.append((math.cos(phi) * radius * squash[0], math.sin(phi) * radius * squash[1]))
    profile[0] = (0.0, profile[0][1])
    profile[-1] = (0.0, profile[-1][1])
    lathe(part, profile, segments=segments, squash=squash[2], cap=False, at=centre)
    part.closed = True
    return part



def circle(radius, samples=48, phase=0.0, squash=1.0, centre=(0.0, 0.0, 0.0), tilt=0.0):
    """Points around a ring in the XZ plane, optionally banked about +X."""
    points = []
    for index in range(samples + 1):
        angle = phase + TWO_PI * index / samples
        x = math.cos(angle) * radius
        z = math.sin(angle) * radius * squash
        y = math.sin(angle) * radius * squash * math.sin(tilt)
        points.append((x + centre[0], y + centre[1], z * math.cos(tilt) + centre[2]))
    return points
