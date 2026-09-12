"""Procedural PBR atlas painting for the skill focus recipe (authoring only).

One atlas per prop and four maps that all come out of the *same* per-part buffers: albedo,
tangent-space normal, glTF ORM (R = occlusion, G = roughness, B = metallic) and emissive.
Painting happens in each part's own parametric UV frame, which is what keeps the maps
attached to the machining — a lathe band, a bolt circle and a frost bleed are expressed
once in 0..1, and the normal, ORM and emissive channels are derived from that single
height field, so no channel can drift out of register with another.

Islands keep a replicated border around the painted interior. Padding alone stops atlas
bleed; dilation is what lets a mip chain shrink a 120-texel island to one clean average
colour instead of a blend of its neighbours.

Determinism: integer-hash noise, no `random`, fixed iteration order. Rebuilding from the
same recipe has to reproduce the asset byte for byte, because `data/models/skills/
build_report.json` locks the result by SHA-256 and `tool/validate_assets.py` re-reads it.
"""
from __future__ import annotations

import math

TWO_PI = math.tau


def _clamp(value, low=0.0, high=1.0):
    return low if value < low else high if value > high else value


def _mix(a, b, t):
    return a + (b - a) * t


def _smooth(edge0, edge1, value):
    t = _clamp((value - edge0) / max(edge1 - edge0, 1e-9))
    return t * t * (3.0 - 2.0 * t)


def hash2(i, j, seed=0):
    """Deterministic lattice hash in [0,1). Integer math only, so platforms cannot disagree."""
    value = (i * 374761393 + j * 668265263 + seed * 1442695041) & 0xffffffff
    value ^= (value >> 13)
    value = (value * 1274126177) & 0xffffffff
    value ^= (value >> 16)
    return (value & 0xffff) / 65535.0


def noise(u, v, frequency=4, seed=0, wrap=0):
    """Value noise on a lattice. `wrap` repeats the lattice along u, which is what a lathe
    or tube needs so its seam disappears."""
    x, y = u * frequency, v * frequency
    xi, yi = int(math.floor(x)), int(math.floor(y))
    xf, yf = x - xi, y - yi
    curve_x = xf * xf * (3.0 - 2.0 * xf)
    curve_y = yf * yf * (3.0 - 2.0 * yf)

    def corner(dx, dy):
        column = xi + dx
        if wrap:
            column %= wrap
        return hash2(column, yi + dy, seed)

    near = _mix(corner(0, 0), corner(1, 0), curve_x)
    far = _mix(corner(0, 1), corner(1, 1), curve_x)
    return _mix(near, far, curve_y)


def fbm(u, v, frequency=4, octaves=3, seed=0, wrap=0):
    """Fractal sum. When `wrap` is set, every octave repeats on its own integer lattice."""
    total = weight = norm = 0.0
    for index in range(octaves):
        step = max(1, int(frequency * (2 ** index)))
        total += weight * noise(u, v, step, seed + 11 * index, step if wrap else 0)
        norm += weight
        weight *= 0.5
    return total / max(norm, 1e-9)


# ------------------------------------------------------------------ pattern parts
#
# A pattern is a small pure function of the part's (u, v) that returns the modifiers the
# recipe wants. Keeping them separate from the recipes is what lets a housing wear a
# hazard band, a bolt ring and a data plate without becoming a wall of special cases.


def bands(v, positions, width, soft=0.35):
    """Raised bands along the profile: coil forms, insulator discs, collar ribs."""
    total = 0.0
    for position in positions:
        distance = abs(v - position) / max(width, 1e-6)
        total = max(total, _smooth(1.0, 1.0 - soft, distance))
    return total


def ribs(v, count, phase=0.0, sharpness=0.55):
    """Fine repeating ridges (threads, wiper tracks, cooling fins)."""
    wave = math.sin((v * count + phase) * TWO_PI)
    return _smooth(1.0 - sharpness, 1.0, wave)


def grid_lines(u, v, columns, rows, width=0.012, soft=2.5):
    """Panel splits: two orthogonal families of grooves."""
    def lines(x, count):
        phase = abs(((x * count) % 1.0) - 0.5) * 2.0
        return _smooth(1.0 - width * soft, 1.0 - width * 0.4, phase)
    return max(lines(u, columns), lines(v, rows))


def dots(u, v, columns, rows, radius=0.12, stagger=True):
    """Fastener field: returns (head mask, signed edge falloff) so a head lifts off the skin."""
    cell_u, cell_v = 1.0 / columns, 1.0 / rows
    column, row = min(int(u / cell_u), columns - 1), min(int(v / cell_v), rows - 1)
    shift = 0.5 * cell_u if (stagger and row % 2) else 0.0
    centre_u = (column + 0.5) * cell_u + shift
    centre_v = (row + 0.5) * cell_v
    if centre_u > 1.0:
        centre_u -= 1.0
    # Measure in texel-ish units so a round head stays round on a non-square island.
    span = max(cell_u, cell_v)
    distance = math.hypot(u - centre_u, v - centre_v) / max(radius * span * columns, 1e-6)
    mask = _smooth(1.02, 0.72, distance)
    return mask, _clamp(1.0 - distance)


def stripes(u, v, count=7, angle=0.6, width=0.5):
    """Hazard chevrons, measured in the part's own frame so they follow the surface.

    Returns 1 on the warning colour and 0 on the body colour, with a soft shoulder so a
    120-texel island never shows a staircase on the diagonal.
    """
    along = u * math.cos(angle) + v * math.sin(angle)
    band = abs((along * count) % 1.0)
    return _smooth(width + 0.06, width - 0.06, band)


def grunge(u, v, scale=6.0, seed=3, wrap=0):
    return fbm(u, v, int(scale), 3, seed, wrap)


def frost(u, v, coverage=0.45, scale=7.0, seed=5, wrap=0):
    value = fbm(u, v, int(scale), 4, seed, wrap)
    return _smooth(coverage, coverage + 0.26, value), value


# --------------------------------------------------------------------- the tile


class Tile:
    """One part's paint canvas, in its parametric space (u around / along, v profile)."""

    def __init__(self, size=120):
        self.size = size
        count = size * size
        self.albedo = [0.5] * (count * 3)
        self.emissive = [0.0] * (count * 3)
        self.height = [0.5] * count
        self.rough = [0.5] * count
        self.metal = [0.0] * count
        self.ao = [1.0] * count

    def paint(self, shader):
        for row in range(self.size):
            v = (row + 0.5) / self.size
            base = row * self.size
            for column in range(self.size):
                u = (column + 0.5) / self.size
                colour, height, rough, metal, glow, occlusion = shader(u, v)
                index = base + column
                offset = index * 3
                self.albedo[offset] = colour[0]
                self.albedo[offset + 1] = colour[1]
                self.albedo[offset + 2] = colour[2]
                self.emissive[offset] = glow[0]
                self.emissive[offset + 1] = glow[1]
                self.emissive[offset + 2] = glow[2]
                self.height[index] = height
                self.rough[index] = _clamp(rough)
                self.metal[index] = metal
                self.ao[index] = _clamp(occlusion)
        return self

    def cavity_and_wear(self, cavity=0.6, wear=0.5):
        """Grooves darken and roughen, crowns polish. One blurred height compare.

        Without contact shading every machined prop reads as flat plastic at two metres,
        which is exactly the failure the shipped environment sets were tuned against.
        """
        size = self.size
        blurred = _blur(self.height, size, radius=2, passes=2)
        for row in range(size):
            base = row * size
            for column in range(size):
                index = base + column
                offset = index * 3
                delta = self.height[index] - blurred[index]
                if delta < 0.0:
                    depth = _clamp(-delta * 3.6)
                    self.ao[index] = _clamp(self.ao[index] - depth * cavity)
                    self.rough[index] = _clamp(self.rough[index] + depth * 0.26)
                    factor = 1.0 - depth * 0.42
                    self.albedo[offset] *= factor
                    self.albedo[offset + 1] *= factor
                    self.albedo[offset + 2] *= factor
                else:
                    bright = _clamp(delta * 4.2) * wear
                    self.rough[index] = _clamp(self.rough[index] - bright * 0.14)
                    lift = bright * 0.20
                    self.albedo[offset] = _clamp(self.albedo[offset] + lift)
                    self.albedo[offset + 1] = _clamp(self.albedo[offset + 1] + lift)
                    self.albedo[offset + 2] = _clamp(self.albedo[offset + 2] + lift)
        return self

    def albedo_bytes(self):
        size = self.size
        out = bytearray(size * size * 3)
        for index in range(size * size * 3):
            out[index] = int(_clamp(self.albedo[index]) * 255.0 + 0.5)
        return bytes(out)

    def emissive_bytes(self):
        size = self.size
        out = bytearray(size * size * 3)
        for index in range(size * size * 3):
            out[index] = int(_clamp(self.emissive[index]) * 255.0 + 0.5)
        return bytes(out)

    def orm_bytes(self):
        """glTF packs occlusion in R, roughness in G and metallic in B (and nothing else)."""
        size = self.size
        out = bytearray(size * size * 3)
        for index in range(size * size):
            offset = index * 3
            out[offset] = int(_clamp(self.ao[index]) * 255.0 + 0.5)
            out[offset + 1] = int(_clamp(self.rough[index]) * 255.0 + 0.5)
            out[offset + 2] = int(_clamp(self.metal[index]) * 255.0 + 0.5)
        return bytes(out)

    def normal_bytes(self, strength=2.4):
        """Central differences of the height field; glTF hands (+X = +u, +Y = +v)."""
        size = self.size
        out = bytearray(size * size * 3)
        for row in range(size):
            for column in range(size):
                index = row * size + column
                left = self.height[row * size + column - 1] if column else self.height[index]
                right = self.height[row * size + column + 1] if column + 1 < size else self.height[index]
                above = self.height[(row - 1) * size + column] if row else self.height[index]
                below = self.height[(row + 1) * size + column] if row + 1 < size else self.height[index]
                d_x = (right - left) * strength
                d_y = (below - above) * strength
                length = math.sqrt(d_x * d_x + d_y * d_y + 1.0)
                offset = index * 3
                out[offset] = int(_clamp(0.5 - 0.5 * d_x / length) * 255.0)
                out[offset + 1] = int(_clamp(0.5 - 0.5 * d_y / length) * 255.0)
                out[offset + 2] = int(_clamp(0.5 * (1.0 / length) + 0.5) * 255.0)
        return bytes(out)

def _blur(source, size, radius=2, passes=1):
    """Separable box blur on a square tile, wrapped at the edges.

    Wrapping matters: a groove that ends at the island border must not read as a lit edge.
    """
    window = 2 * radius + 1
    current = list(source)
    for _ in range(passes):
        result = [0.0] * len(current)
        for row in range(size):
            total = 0.0
            for offset in range(-radius, radius + 1):
                total += current[row * size + _wrap(offset, size)]
            for column in range(size):
                result[row * size + column] = total / window
                total += current[row * size + _wrap(column + radius + 1, size)]
                total -= current[row * size + _wrap(column - radius, size)]
        current = result
        for column in range(size):
            total = 0.0
            for offset in range(-radius, radius + 1):
                total += current[_wrap(offset, size) * size + column]
            for row in range(size):
                result[row * size + column] = total / window
                total += current[_wrap(row + radius + 1, size) * size + column]
                total -= current[_wrap(row - radius, size) * size + column]
        current = result
    return current


def _wrap(value, size):
    return value % size
