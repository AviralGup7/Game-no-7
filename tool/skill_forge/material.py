"""Material families + atlas packing for the skill focus recipe (authoring only).

Nine authored families cover the whole focus set. Each is a *shader*: a pure function of the
part's parametric (u, v) returning albedo, height, roughness, metallic and emissive. A
single composer then applies the marks every machined part in the set shares — band
ribs, fastener fields, panel splits, hazard chevrons, contact darkening — so a bolt ring
and a reactor collar speak the same language of highlights and grime instead of each
inventing its own.

`Atlas` packs one island per *unique* shader: eight identical bolts cost one tile because
the tile is keyed on (family, detail, options). Islands sit on a fixed grid inside a 512²
sheet with a 4-texel dilated border, which keeps the mip chain clean and pins each prop to
one material, one draw call and four 512² maps — the mobile budget the rest of the project
holds itself to.

Units here are texels and 0..1 colour floats; nothing outside the standard library is used.
"""
from __future__ import annotations

import math

from .texture import _clamp, _smooth, dots, fbm, grid_lines, noise, ribs, stripes

TWO_PI = math.tau


def mix_colour(a, b, t):
    t = _clamp(t)
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def scale_colour(colour, factor):
    return tuple(_clamp(channel * factor) for channel in colour)


def add_colour(base, overlay, weight):
    return tuple(_clamp(base[i] + overlay[i] * weight) for i in range(3))


# --------------------------------------------------------------------- families


def family_alloy(u, v, spec):
    """Machined housing: brushed along the profile, faint grain across it."""
    wrap = spec.get('wrap', 0)
    brushed = noise(u, v * spec.get('brush', 14.0), 20, 7, 0) * 0.55 + noise(u, v * 40.0, 8, 11, wrap) * 0.45
    grain = fbm(u, v, spec.get('grain', 6), 2, 13, wrap)
    colour = scale_colour(spec['colour'], 0.86 + 0.20 * brushed + 0.07 * grain)
    return colour, 0.5 + 0.012 * brushed, 0.30 + 0.24 * (1.0 - brushed) + 0.05 * grain, 1.0, (0.0, 0.0, 0.0)


def family_ceramic(u, v, spec):
    """Sintered shell: dielectric, near-white, cast seams at even intervals."""
    speckle = fbm(u, v, 10, 3, 17, spec.get('wrap', 0))
    seams = _smooth(0.02, 0.0, abs(((v * spec.get('segments', 6)) % 1.0) - 0.5) - 0.455)
    colour = scale_colour(spec['colour'], 0.90 + 0.13 * speckle)
    return colour, 0.52 - 0.05 * speckle - 0.10 * seams, 0.20 + 0.22 * speckle, 0.0, (0.0, 0.0, 0.0)


def family_emitter(u, v, spec):
    """Lit band inside a dark housing: the pulse cores, coil throats and slits."""
    housing, accent = spec['colour'], spec['accent']
    lit = _smooth(1.0, 0.15, abs(v - spec.get('band', 0.5)) / max(spec.get('band_width', 0.22), 1e-6))
    flicker = fbm(u, v, 8, 3, 23, spec.get('wrap', 0))
    hot = _smooth(0.35, 1.0, flicker * 0.5 + lit * 0.9)
    ridge = ribs(v, spec.get('ribs', 0), 0.0, 0.6) if spec.get('ribs') else 0.0
    colour = add_colour(scale_colour(housing, 1.0 - 0.55 * (1.0 - lit)), accent, hot * 0.30)
    glow = scale_colour(accent, hot * (0.30 + 0.70 * lit) * spec.get('glow', 1.0))
    return colour, 0.5 - 0.06 * lit + 0.03 * ridge, 0.55 - 0.32 * lit, 1.0 - 0.75 * lit, glow


def family_winding(u, v, spec):
    """Enamelled copper: tight wire with varnish between the turns and oxidised crowns."""
    copper, dark = spec['colour'], spec.get('shadow', (0.05, 0.045, 0.05))
    wire = _smooth(-0.25, 0.55, math.sin(v * spec.get('ribs', 46) * TWO_PI))
    oxidation = fbm(u, v, 12, 2, 29, spec.get('wrap', 0))
    colour = mix_colour(dark, scale_colour(copper, 0.70 + 0.55 * oxidation), wire)
    return colour, 0.30 + 0.42 * wire, _lerp(0.62, 0.24, wire) + 0.08 * oxidation, 1.0, \
        scale_colour(spec.get('accent', copper), wire * 0.05)


def family_composite(u, v, spec):
    """Carbon/rubber tooling: dark, grippy, faintly woven, scuffed by use."""
    weave = 0.5 + 0.5 * math.sin(u * spec.get('weave', 34.0) * TWO_PI) * math.sin(v * spec.get('weave', 34.0) * TWO_PI)
    wear = fbm(u, v, 5, 3, 31, spec.get('wrap', 0))
    colour = scale_colour(spec['colour'], 0.80 + 0.14 * weave + 0.16 * wear)
    return colour, 0.46 + 0.05 * weave - 0.06 * _smooth(0.62, 0.95, wear), \
        0.62 - 0.16 * weave + 0.12 * wear, 0.05, (0.0, 0.0, 0.0)


def family_lens(u, v, spec):
    """Cast optical window: polished dielectric with a faint internal caustic."""
    accent, tint = spec.get('accent', (0.6, 0.8, 1.0)), spec['colour']
    swirl = fbm(u + 0.12 * math.sin(v * 5.0), v, 4, 3, 37, spec.get('wrap', 0))
    caustic = _smooth(0.45, 0.95, swirl)
    colour = mix_colour(tint, accent, 0.35 * caustic)
    return colour, 0.55 + 0.05 * caustic, 0.10 + 0.10 * (1.0 - caustic), 0.0, \
        scale_colour(accent, 0.28 + 0.62 * caustic)


def family_frost(u, v, spec):
    """Ice creep: a cold rime that thickens along an fbm threshold and glints on facets."""
    crystals = fbm(u, v, spec.get('scale', 7), 4, 41, spec.get('wrap', 0))
    coverage_value = spec.get('coverage', 0.40)
    coverage = _smooth(coverage_value, coverage_value + 0.24, crystals)
    facets = _smooth(0.4, 1.0, abs(math.sin((u * 9.0 + v * 5.0) * math.pi)))
    accent = spec.get('accent', (0.55, 0.8, 1.0))
    colour = add_colour(mix_colour(spec['colour'], (0.94, 0.98, 1.0), coverage), accent, coverage * 0.14)
    glow = scale_colour(accent, coverage * 0.20 * spec.get('glow', 1.0))
    return colour, 0.44 + 0.30 * coverage + 0.05 * facets * coverage, _lerp(0.34, 0.66, coverage), \
        _lerp(0.85, 0.05, coverage), glow


def family_plating(u, v, spec):
    """Deck plate and pedestal metal: heavy grunge, scratches, a painted edge band."""
    grime = fbm(u, v, 5, 4, 43, spec.get('wrap', 0))
    scratches = _smooth(0.86, 1.0, noise(u, v * 34.0, 40, 47, 0))
    paint_line = spec.get('paint', 0.0)
    paint = 1.0 if (paint_line and v > 1.0 - paint_line) else 0.0
    colour = mix_colour(scale_colour(spec['colour'], 0.64 + 0.52 * grime),
                        spec.get('paint_colour', spec['colour']), paint)
    height = 0.42 + 0.10 * grime - 0.06 * _smooth(0.55, 0.9, grime) + 0.02 * paint
    rough = 0.52 + 0.30 * (1.0 - grime) - 0.12 * scratches
    return colour, height, rough, 0.9 - 0.5 * paint, (0.0, 0.0, 0.0)


def family_marking(u, v, spec):
    """Data plate: serial ticks and an accent chevron band that tags the skill."""
    accent, base = spec.get('accent', (0.6, 0.8, 1.0)), spec['colour']
    row_band = 1.0 - _smooth(0.10, 0.16, abs(v - 0.34))
    ticks = 1.0 if int(u * spec.get('ticks', 26)) % 3 == 0 else 0.0
    band = 1.0 - _smooth(0.03, 0.06, abs(v - 0.66))
    colour = mix_colour(scale_colour(base, 0.92), (0.05, 0.05, 0.06), row_band * ticks)
    height = 0.5 - 0.08 * row_band * ticks - 0.03 * band
    glow = scale_colour(accent, band * spec.get('glow', 0.9))
    return colour, height, 0.42, 0.2, glow


FAMILIES = {
    'alloy': family_alloy,
    'ceramic': family_ceramic,
    'emitter': family_emitter,
    'winding': family_winding,
    'composite': family_composite,
    'lens': family_lens,
    'frost': family_frost,
    'plating': family_plating,
    'marking': family_marking,
}


def _lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------- composer


def build_shader(family, spec, detail):
    """Wrap a family shader with the shared machined detail pass.

    `detail` is authored per part by the recipe — band positions, rib counts, fastener
    fields, panel splits, hazard chevrons — and every mark is placed in the part's own
    parametric space, so a bolt ring follows a lathe's circumference instead of sliding
    across it. Returns the (u, v) -> channels function `Tile.paint` expects.
    """
    painter = FAMILIES[family]
    band_positions = tuple(detail.get('bands', ()))
    band_width = detail.get('band_width', 0.030)
    rib_count = detail.get('ribs', 0)
    fasteners = detail.get('fasteners')
    panel = detail.get('panel')
    hazard = detail.get('hazard', 0)
    hazard_band = detail.get('hazard_band', 0.0)
    accent = tuple(detail.get('accent', (0.4, 0.7, 1.0)))
    glow_trim = detail.get('glow_trim', 1.0)

    def shader(u, v):
        colour, height, rough, metal, glow = painter(u, v, spec)
        for position in band_positions:
            shape = _smooth(band_width, 0.0, abs(v - position))
            height += 0.085 * shape
            rough = _clamp(rough - 0.10 * shape)
            colour = add_colour(colour, (0.16, 0.16, 0.17), shape * 0.30)
        if rib_count:
            ridge = ribs(v, rib_count, 0.0, 0.6)
            height += 0.055 * ridge
            rough = _clamp(rough - 0.08 * ridge)
            colour = scale_colour(colour, 1.0 + 0.10 * ridge)
        if fasteners:
            columns, rows, radius = fasteners
            head, lift = dots(u, v, columns, rows, radius)
            height = height * (1.0 - head) + (0.66 + 0.07 * lift) * head
            rough = _lerp(rough, 0.34, head)
            colour = mix_colour(colour, scale_colour(colour, 1.22), head)
        if panel:
            columns, rows, width = panel
            groove = grid_lines(u, v, columns, rows, width)
            height -= 0.075 * groove
            rough = _clamp(rough + 0.10 * groove)
            colour = scale_colour(colour, 1.0 - 0.26 * groove)
        if hazard:
            chevron = stripes(u, v, hazard, 0.75, 0.5)
            if hazard_band:
                # Chevrons only near the rim: painted across a whole plate they read as a
                # striped pancake, as a border they read as hazard marking on a deck edge.
                chevron *= _smooth(0.5 - hazard_band, 0.46, math.hypot(u - 0.5, v - 0.5))
            colour = mix_colour(colour, accent, chevron * 0.80)
            rough = _clamp(rough - 0.10 * chevron)
            glow = add_colour(glow, accent, chevron * 0.08)
        return colour, _clamp(height, 0.0, 1.0), _clamp(rough), metal, scale_colour(glow, glow_trim), 1.0

    return shader


# ----------------------------------------------------------------------- atlas


class Atlas:
    """Fixed-grid PBR atlas: one sheet, `grid × grid` islands, four 8-bit maps."""

    def __init__(self, size=512, tile=128, border=4, inner=120):
        self.size = size
        self.tile = tile
        self.border = border
        self.inner = inner
        self.grid = size // tile
        self.slots = {}
        self.used = 0
        self.maps = {name: bytearray(size * size * 3) for name in ('albedo', 'normal', 'orm', 'emissive')}

    def island_for(self, key):
        """Reserve (or re-use) an island for a material key. Fails closed when full."""
        slot = self.slots.get(key)
        if slot is not None:
            return slot
        if self.used >= self.grid * self.grid:
            raise ValueError(f"atlas is full: more than {self.grid * self.grid} unique islands")
        slot = (self.used % self.grid, self.used // self.grid)
        self.slots[key] = slot
        self.used += 1
        return slot

    def blit(self, slot, tile):
        """Copy one painted tile into its island, then dilate its border outward.

        The dilation is the point: padding alone still lets a 4x4-mip island sample a
        neighbour's colours, while an replicated edge degenerates to the part's own rim.
        """
        size, border, inner = self.size, self.border, tile.size
        origin_x = slot[0] * self.tile + border
        origin_y = slot[1] * self.tile + border
        planes = ((tile.albedo_bytes(), 'albedo'), (tile.normal_bytes(strength=1.35), 'normal'),
                  (tile.orm_bytes(), 'orm'), (tile.emissive_bytes(), 'emissive'))
        for row in range(-border, inner + border):
            target_y = origin_y + row
            if not 0 <= target_y < size:
                continue
            source_row = min(max(row, 0), inner - 1)
            for column in range(-border, inner + border):
                target_x = origin_x + column
                if not 0 <= target_x < size:
                    continue
                source_column = min(max(column, 0), inner - 1)
                source_offset = (source_row * inner + source_column) * 3
                target_offset = (target_y * size + target_x) * 3
                for plane, name in planes:
                    channel = self.maps[name]
                    channel[target_offset] = plane[source_offset]
                    channel[target_offset + 1] = plane[source_offset + 1]
                    channel[target_offset + 2] = plane[source_offset + 2]

    def uv_rect(self, slot):
        """(u0, v0, u1, v1) of the painted interior inside the atlas."""
        first = (slot[0] * self.tile + self.border) / self.size
        last = (slot[0] * self.tile + self.border + self.inner) / self.size
        bottom = (slot[1] * self.tile + self.border) / self.size
        top = (slot[1] * self.tile + self.border + self.inner) / self.size
        return first, bottom, last, top
