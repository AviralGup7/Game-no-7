#!/usr/bin/env python3
"""Builds the eight skill cast foci: geometry, PBR atlases, GLBs, icons, renders.

The skills folder shipped as pure data — eight `SkillConfig` resources with behaviour,
cooldowns, status hooks and *no visual asset at all* (`icon` was never set, and the
catalogue's `gameplay_skills` entries all pointed at one shared `ring.png`). This recipe
gives every skill the 3D object its new name already implies: a casting focus, and its own
rendered silhouette as the skill-bar icon.

Run:      python3 tool/build_skill_foci.py [skill_id ...]
Writes:   data/models/skills/<skill_id>/focus.glb
          data/models/skills/<skill_id>/textures/Focus_<Name>_{albedo,normal,ORM,emission}.png
          data/models/skills/<skill_id>/focus_render.png     (software-rasterized proof)
          data/models/skills/<skill_id>/focus_front.png      (silhouette elevation)
          data/models/skills/icons/<skill_id>.png            (skill-bar icon, RGBA)
          data/models/skills/skill_showcase.png              (the set, one sheet)
          data/models/skills/build_report.json               (SHA-256 provenance lock)

Everything is authored here from `math`, `struct`, `json` and `zlib` — no NumPy, no trimesh,
no Blender, no download — because `docs/agent_skills/04` §2 requires the recipe to run in a
bare sandbox and the report locks the result byte for byte. Determinism is therefore a hard
constraint: integer-hash noise, fixed iteration order, no `random`.

Design intent, per `docs/agent_skills/02`: one family language across all eight (octagonal
deck plate, gimbal collar, lit core, ceramic crown) so the set reads as issued hardware,
then a silhouette that departs from the others enough to be recognised at a glance across an
arena. Accent colours are the ones `EffectDirector.SKILL_COLORS` already casts with, so the
prop, the ground ring and the burst are the same light.
"""
from __future__ import annotations

from pathlib import Path
import hashlib
import json
import math
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))

from skill_forge import pack, png, raster                                        # noqa: E402
from skill_forge import primitives as P                                          # noqa: E402
from skill_forge.mesh import Mesh, transform                                     # noqa: E402

ATLAS = 512
TILE = 128
BORDER = 4
OUT = ROOT / 'data/models/skills'
TRIANGLE_BUDGET = 4200
ICON_SIZE = 128
HERO_SIZE = 512
SILHOUETTE_SIZE = 320
RECIPE_FILES = ['tool/build_skill_foci.py', 'tool/skill_forge/mesh.py', 'tool/skill_forge/primitives.py',
                'tool/skill_forge/texture.py', 'tool/skill_forge/material.py', 'tool/skill_forge/glb.py',
                'tool/skill_forge/pack.py', 'tool/skill_forge/raster.py', 'tool/skill_forge/png.py']

STEEL = (0.30, 0.325, 0.365)
DARK_STEEL = (0.145, 0.155, 0.18)
TITANIUM = (0.52, 0.55, 0.58)
CERAMIC = (0.78, 0.81, 0.84)
IVORY = (0.86, 0.86, 0.80)
COPPER = (0.62, 0.33, 0.18)
RUBBER = (0.055, 0.06, 0.075)
CONCRETE = (0.185, 0.195, 0.215)
BRASS = (0.62, 0.48, 0.20)

# Accent per skill, taken from the cast colours EffectDirector already uses, so a prop on the
# dais and the ring under the caster are unmistakably the same ability.
SKILLS = {
    'seismic_slam': {'display': 'Graviton Pulse', 'accent': (0.82, 0.48, 0.18), 'glow': 1.5},
    'bladestorm': {'display': 'EMP Burst', 'accent': (0.88, 0.62, 0.18), 'glow': 1.4},
    'phantom_rush': {'display': 'Phase Dash', 'accent': (0.64, 0.42, 1.0), 'glow': 1.45},
    'shatterwave': {'display': 'Sonic Disruptor', 'accent': (0.78, 0.68, 1.0), 'glow': 1.35},
    'chain_lightning': {'display': 'Tesla Arc', 'accent': (0.52, 0.74, 1.0), 'glow': 1.6},
    'frost_nova_skill': {'display': 'Cryo Pulse', 'accent': (0.42, 0.76, 1.0), 'glow': 1.4},
    'mending_light': {'display': 'Repair Field', 'accent': (0.48, 1.0, 0.58), 'glow': 1.3},
    'warcry_skill': {'display': 'Overclock', 'accent': (1.0, 0.42, 0.22), 'glow': 1.55},
}

TAU = math.tau


# --------------------------------------------------------------------- kit helpers
#
# All eight foci are built from the same kit — deck plate, rim, collar, gimbal, fastener
# ring, lit band, floating pips — and only the silhouette parts unique to a skill are
# authored per design. That is what makes nine-part props look like one product line rather
# than eight one-offs.


def deck(mesh, accent, radius=0.196, height=0.050, sides=8):
    """The octagonal deck plate every focus is bolted to (and its visual foot)."""
    part = mesh.part('deck', 'plating',
                     {'colour': CONCRETE, 'paint': 0.14,
                      'paint_colour': tuple(value * 0.52 + 0.03 for value in accent)},
                     {'fasteners': (10, 1, 0.16), 'panel': (3, 1, 0.014), 'accent': accent,
                      'cavity': 0.72, 'wear': 0.34})
    P.slab(part, P.round_corners(P.regular(sides, radius, rotation=math.pi / sides), radius * 0.16, 2),
           0.0, height, bevel=height * 0.30)
    return part


def deck_rim(mesh, accent, radius=0.166, height=0.050, sides=8):
    part = mesh.part('deck_rim', 'alloy', {'colour': DARK_STEEL, 'grain': 8, 'wrap': sides * 4},
                     {'bands': (0.06,), 'cavity': 0.5})
    P.slab(part, P.regular(sides, radius, rotation=math.pi / sides), height * 0.80, height * 1.30,
           bevel=height * 0.16)
    return part


def riser(mesh, accent, radius, height, at_y=0.050, colour=STEEL, detail=None):
    """The collar between the deck and the body: every focus has one, sized to its mass."""
    part = mesh.part('riser', 'alloy', {'colour': colour, 'brush': 18.0, 'wrap': 24},
                     detail or {'bands': (0.18, 0.82), 'fasteners': (6, 1, 0.18), 'cavity': 0.62})
    P.lathe(part, [(radius * 1.10, at_y), (radius, at_y + height * 0.18), (radius, at_y + height * 0.82),
                   (radius * 1.08, at_y + height)], segments=28, cap=True)
    return part


def gimbal(mesh, accent, radius, at_y, height=0.026, thickness=0.014, segments=36):
    """Open retaining ring around the body: the shared "issued hardware" signature."""
    part = mesh.part('gimbal', 'alloy', {'colour': TITANIUM, 'brush': 22.0, 'wrap': 36},
                     {'ribs': 2, 'cavity': 0.55, 'glow_trim': 0.8})
    loop = [(-thickness, -height / 2.0), (thickness, -height / 2.0),
            (thickness, height / 2.0), (-thickness, height / 2.0)]
    P.revolve(part, loop, radius, segments=segments, at=(0.0, at_y, 0.0))
    return part


def lit_band(mesh, name, accent, radius, at_y, half_height=0.020, segments=32):
    """The emissive collar. `emitter` paints a hot band inside a dark housing, so the glow has
    a physical source instead of being brushed over the whole prop."""
    part = mesh.part(name, 'emitter', {'colour': DARK_STEEL, 'accent': accent, 'band': 0.5,
                                       'band_width': 0.36, 'glow': 2.2, 'wrap': segments},
                     {'ribs': 3, 'cavity': 0.35})
    P.lathe(part, [(radius, at_y - half_height), (radius * 1.02, at_y - half_height * 0.35),
                    (radius * 1.02, at_y + half_height * 0.35), (radius, at_y + half_height)],
            segments=segments, cap=False, wall=0.006)
    return part


def bolt_circle(mesh, name, radius, at_y, count=8, size=0.018, colour=TITANIUM):
    """A ring of hex fastener heads: the detail that sells a prop as assembled hardware."""
    source = mesh.part(name + '_source', 'alloy', {'colour': colour, 'grain': 10})
    P.slab(source, P.regular(6, size), 0.0, size * 0.62, bevel=size * 0.22, at=(radius, at_y, 0.0))
    mesh.array(name, source, count, phase=math.pi / count)


def hose(mesh, name, points, radii, colour=RUBBER, detail=None):
    part = mesh.part(name, 'composite', {'colour': colour, 'weave': 26.0, 'wrap': 12},
                     detail or {'bands': (0.22, 0.78), 'cavity': 0.5})
    P.tube(part, points, radii, segments=10, squash=0.9)
    return part


def stamp(mesh, name, source, at=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    """Copy a source part under a rigid transform (author once, place many times)."""
    return mesh.copy(name, source, transform(translation=at, rotation=rot, scale=scale))


def torus_profile(width, height, segments=12):
    """Closed elliptical loop for `revolve`: toroids, O-rings, donut top loads."""
    return [(math.cos(TAU * index / segments) * width, math.sin(TAU * index / segments) * height)
            for index in range(segments)]


# ------------------------------------------------------------------- the designs


def design_graviton_pulse(mesh, accent):
    """Slam: an impact anvil holding a crush core off the deck on four hydraulic rams."""
    riser(mesh, accent, 0.138, 0.115,
          detail={'bands': (0.14, 0.86), 'fasteners': (8, 1, 0.2), 'cavity': 0.66})
    for index in range(4):
        angle = math.pi / 4 + index * TAU / 4
        ram = mesh.part(f'ram_{index}', 'alloy', {'colour': TITANIUM, 'brush': 26.0, 'wrap': 16},
                        {'ribs': 6, 'cavity': 0.6})
        base = (math.cos(angle) * 0.128, 0.105, math.sin(angle) * 0.128)
        top = (math.cos(angle) * 0.098, 0.330, math.sin(angle) * 0.098)
        middle = (base[0] * 0.5 + top[0] * 0.5, 0.212, base[2] * 0.5 + top[2] * 0.5)
        P.tube(ram, [base, middle, top], [0.028, 0.024, 0.020], segments=12)
        # The ram finishes in a lit contact ring on the collar rather than a plate: a flat cap
        # buried inside the collar silhouette read as a hole punched in the model.
        tip = mesh.part(f'ram_tip_{index}', 'emitter',
                        {'colour': DARK_STEEL, 'accent': accent, 'band': 0.62, 'band_width': 0.30,
                         'glow': 2.2, 'wrap': 12}, {'cavity': 0.4})
        P.lathe(tip, [(0.020, 0.326), (0.034, 0.334), (0.036, 0.350), (0.026, 0.358)], segments=14,
                cap=False, wall=0.006, at=(top[0], 0.0, top[2]))
    collar = mesh.part('compression_collar', 'alloy', {'colour': STEEL, 'brush': 20.0, 'wrap': 32},
                       {'bands': (0.22, 0.5, 0.78), 'fasteners': (10, 1, 0.16), 'cavity': 0.6})
    P.lathe(collar, [(0.085, 0.300), (0.112, 0.322), (0.116, 0.372), (0.104, 0.412), (0.086, 0.428)],
            segments=32, cap=False, wall=0.006)
    # The core is an oblate crush lens seated *inside* the collar mouth and pinched by four
    # emitter clamps, so it reads as held under load rather than as a ball hovering overhead.
    core = mesh.part('crush_core', 'lens', {'colour': (0.10, 0.09, 0.08), 'accent': accent},
                     {'cavity': 0.2, 'glow_trim': 1.7})
    P.sphere(core, (0.0, 0.436, 0.0), 0.066, segments=20, rings=11)
    core.scale_from(0, (0.0, 0.436, 0.0), (1.0, 0.80, 1.0))
    clamp = mesh.part('core_clamp_source', 'emitter',
                      {'colour': DARK_STEEL, 'accent': accent, 'band': 0.90, 'band_width': 0.10, 'glow': 2.2})
    P.slab(clamp, [(0.0, -0.018), (0.030, -0.013), (0.040, 0.002), (0.028, 0.016), (0.0, 0.016)],
           -0.008, 0.008, bevel=0.003)
    for index in range(4):
        angle = index * TAU / 4 + math.pi / 4
        stamp(mesh, f'core_clamp_{index}', clamp, at=(math.cos(angle) * 0.078, 0.452, math.sin(angle) * 0.078),
              rot=(0.0, angle, 0.0))
    mesh.parts.remove(clamp)
    halo = mesh.part('crush_halo', 'emitter', {'colour': (0.04, 0.04, 0.05), 'accent': accent,
                                               'band': 0.34, 'band_width': 0.30, 'glow': 3.6, 'wrap': 40},
                     {'cavity': 0.2})
    P.revolve(halo, torus_profile(0.010, 0.015, 8), 0.100, segments=36, at=(0.0, 0.436, 0.0))
    vane = mesh.part('strake_source', 'alloy', {'colour': DARK_STEEL, 'brush': 16.0},
                     {'panel': (2, 1, 0.02), 'cavity': 0.7})
    P.slab(vane, P.airfoil(0.115, 0.030, camber=0.02, rows=6), 0.165, 0.300, bevel=0.006)
    for index in range(4):
        angle = index * TAU / 4
        stamp(mesh, f'strake_{index}', vane, at=(math.cos(angle) * 0.138, 0.0, math.sin(angle) * 0.138),
              rot=(0.0, angle, 0.0))
    mesh.parts.remove(vane)
    return {'cast': (0.0, 0.496, 0.0), 'flare': (0.0, 0.612, 0.0)}


def design_emp_burst(mesh, accent):
    """Whirl: five free blades around a spined hub, wrapped in a toroidal EMP winding."""
    hub = mesh.part('hub', 'alloy', {'colour': STEEL, 'brush': 20.0, 'wrap': 28},
                    {'ribs': 5, 'fasteners': (8, 1, 0.18), 'cavity': 0.66})
    P.lathe(hub, [(0.055, 0.112), (0.100, 0.145), (0.108, 0.235), (0.082, 0.285), (0.050, 0.300),
                   (0.0, 0.335)], segments=28)
    winding = mesh.part('emp_winding', 'winding',
                        {'colour': COPPER, 'ribs': 54, 'shadow': (0.045, 0.04, 0.045), 'accent': accent, 'wrap': 36},
                        {'cavity': 0.8, 'glow_trim': 0.5})
    P.revolve(winding, [(-0.026, -0.030), (0.026, -0.030), (0.026, 0.030), (-0.026, 0.030)], 0.150,
              segments=48, at=(0.0, 0.225, 0.0))
    cage = mesh.part('blade_cage', 'alloy', {'colour': TITANIUM, 'brush': 24.0, 'wrap': 40},
                     {'bands': (0.5,), 'cavity': 0.55})
    P.revolve(cage, [(-0.013, -0.050), (0.013, -0.050), (0.013, 0.050), (-0.013, 0.050)], 0.206,
              segments=44, at=(0.0, 0.225, 0.0))
    blade = mesh.part('blade_source', 'alloy', {'colour': (0.60, 0.63, 0.66), 'brush': 30.0},
                      {'panel': (3, 1, 0.018), 'cavity': 0.68, 'wear': 0.72})
    P.slab(blade, [(0.0, -0.016), (0.090, -0.028), (0.126, 0.002), (0.100, 0.030), (0.0, 0.018)],
           -0.010, 0.010, bevel=0.004, at=(0.0, 0.240, 0.0))
    mesh.array('blade', blade, 5, radius=0.138, phase=math.pi / 5)
    for index in range(5):
        angle = math.pi / 5 + index * TAU / 5
        prong = mesh.part(f'emp_prong_{index}', 'emitter',
                          {'colour': DARK_STEEL, 'accent': accent, 'band': 0.72, 'band_width': 0.42,
                           'glow': 3.0, 'wrap': 10}, {'cavity': 0.4})
        P.tube(prong, [(math.cos(angle) * 0.128, 0.300, math.sin(angle) * 0.128),
                       (math.cos(angle) * 0.176, 0.355, math.sin(angle) * 0.176),
                       (math.cos(angle) * 0.152, 0.415, math.sin(angle) * 0.152)],
               [0.010, 0.008, 0.004], segments=9)
    crown = mesh.part('crown', 'ceramic', {'colour': IVORY, 'segments': 7},
                      {'bands': (0.42,), 'cavity': 0.42})
    P.lathe(crown, [(0.052, 0.300), (0.072, 0.335), (0.062, 0.375), (0.030, 0.400), (0.0, 0.412)],
            segments=24)
    lens = mesh.part('burst_lens', 'lens', {'colour': (0.12, 0.11, 0.09), 'accent': accent},
                     {'glow_trim': 1.5, 'cavity': 0.2})
    P.sphere(lens, (0.0, 0.225, 0.0), 0.046, segments=18, rings=10)
    bolt_circle(mesh, 'hub_bolt', 0.075, 0.118, count=6, size=0.012)
    return {'cast': (0.0, 0.225, 0.0), 'flare': (0.0, 0.440, 0.0)}


def design_phase_dash(mesh, accent):
    """Dash strike: a phase spar aimed forward, straked, with twin venturi ducts."""
    spar = mesh.part('phase_spar', 'alloy', {'colour': STEEL, 'brush': 26.0, 'wrap': 20},
                     {'bands': (0.24, 0.66), 'panel': (2, 3, 0.016), 'cavity': 0.62})
    # A forged dash pylon: pointed on the leading edge (+-Z here), tapering as it rises, then
    # canting the whole spar forward so the silhouette carries the skill's own vector.
    section = [(-0.042, -0.052), (0.0, -0.170), (0.042, -0.052),
               (0.036, 0.068), (0.0, 0.124), (-0.036, 0.068)]
    P.slab(spar, section, 0.132, 0.458, bevel=0.011, taper=0.30)
    mesh.transform_part('phase_spar', transform(rotation=(-0.15, 0.0, 0.0)))
    spine = mesh.part('phase_spine', 'emitter',
                      {'colour': (0.05, 0.05, 0.07), 'accent': accent, 'band': 0.55, 'band_width': 0.30,
                       'glow': 3.1, 'wrap': 12}, {'cavity': 0.3})
    P.tube(spine, [(0.0, 0.142, -0.146), (0.0, 0.264, -0.192), (0.0, 0.386, -0.170),
                  (0.0, 0.452, -0.118)], [0.013, 0.014, 0.011, 0.005], segments=10)
    for sign, name in ((-1, 'port'), (1, 'starboard')):
        duct = mesh.part(f'{name}_duct', 'alloy', {'colour': DARK_STEEL, 'brush': 18.0, 'wrap': 18},
                         {'ribs': 9, 'cavity': 0.7})
        P.tube(duct, [(sign * 0.086, 0.170, -0.020), (sign * 0.104, 0.248, -0.004),
                      (sign * 0.090, 0.326, 0.062)], [0.032, 0.036, 0.027], segments=14, squash=0.85)
        throat = mesh.part(f'{name}_throat', 'emitter',
                           {'colour': (0.04, 0.04, 0.05), 'accent': accent, 'band': 0.30, 'band_width': 0.28,
                            'glow': 2.6, 'wrap': 18}, {'cavity': 0.35})
        P.lathe(throat, [(0.020, 0.154), (0.032, 0.166), (0.032, 0.188), (0.020, 0.200)], segments=16,
                cap=False, wall=0.006, at=(sign * 0.086, 0.0, -0.030))
    # Trailing fins bolted to the spar's back face: the afterimage idea, but structurally
    # part of the prop instead of three plates hovering in the air behind it.
    fin = mesh.part('wake_source', 'ceramic', {'colour': (0.55, 0.56, 0.62), 'segments': 4},
                    {'panel': (2, 1, 0.03), 'cavity': 0.5})
    P.slab(fin, [(-0.086, 0.0), (-0.020, -0.044), (0.020, -0.044), (0.086, 0.0),
                 (0.030, 0.030), (-0.030, 0.030)], -0.004, 0.004, bevel=0.0015)
    # Two ground marks on the deck instead of plates in mid-air: the wake stays attached to
    # something, which is what a hard-surface prop needs to read at 24 px as well as at 1 m.
    for index, factor in enumerate((1.0, 0.74)):
        stamp(mesh, f'wake_mark_{index}', fin, at=(0.0, 0.052, 0.052 + index * 0.070),
              rot=(0.0, 0.0, 0.0), scale=(factor, factor, 1.0))
    mesh.parts.remove(fin)
    gimbal(mesh, accent, 0.128, 0.268, height=0.030, thickness=0.016, segments=32)
    riser(mesh, accent, 0.100, 0.085,
           detail={'bands': (0.5,), 'fasteners': (6, 1, 0.2), 'cavity': 0.6}, colour=DARK_STEEL)
    injector = mesh.part('injector', 'emitter',
                         {'colour': DARK_STEEL, 'accent': accent, 'band': 0.5, 'band_width': 0.34,
                          'glow': 2.5, 'wrap': 24}, {'cavity': 0.4})
    P.lathe(injector, [(0.055, 0.104), (0.072, 0.118), (0.072, 0.152), (0.055, 0.166)], segments=24, cap=False, wall=0.006)
    return {'cast': (0.0, 0.300, -0.150), 'flare': (0.0, 0.300, -0.320)}


def design_sonic_disruptor(mesh, accent):
    """Shockwave: a flared resonator horn with five tuning vanes across its mouth."""
    horn = mesh.part('resonator', 'alloy', {'colour': STEEL, 'brush': 24.0, 'wrap': 36},
                     {'ribs': 7, 'bands': (0.06, 0.94), 'cavity': 0.66})
    P.lathe(horn, [(0.042, 0.175), (0.056, 0.215), (0.082, 0.275), (0.118, 0.345), (0.150, 0.404),
                   (0.156, 0.424)], segments=40, cap=False, wall=0.006)
    throat = mesh.part('horn_throat', 'winding', {'colour': COPPER, 'ribs': 26, 'accent': accent, 'wrap': 32},
                       {'cavity': 0.75, 'glow_trim': 0.45})
    P.lathe(throat, [(0.036, 0.168), (0.046, 0.200), (0.046, 0.235), (0.036, 0.260)], segments=24, cap=False, wall=0.006)
    mouth = mesh.part('horn_mouth', 'emitter',
                      {'colour': (0.045, 0.05, 0.06), 'accent': accent, 'band': 0.5, 'band_width': 0.42,
                       'glow': 3.0, 'wrap': 44}, {'cavity': 0.25})
    P.lathe(mouth, [(0.148, 0.404), (0.158, 0.416), (0.158, 0.434), (0.148, 0.446)], segments=44, cap=False, wall=0.006)
    vane = mesh.part('vane_source', 'ceramic', {'colour': (0.70, 0.74, 0.78), 'segments': 3},
                     {'panel': (1, 2, 0.03), 'cavity': 0.5, 'wear': 0.6})
    P.slab(vane, P.round_corners([(-0.055, -0.014), (0.055, -0.010), (0.055, 0.010), (-0.055, 0.014)],
                                 0.008, 1), -0.030, 0.030, bevel=0.004)
    for index in range(5):
        swing = (index - 2) * 0.30
        stamp(mesh, f'vane_{index}', vane, at=(0.0, 0.408, 0.0), rot=(0.0, math.pi / 2.0 + swing, 0.0),
              scale=(1.0 + 0.18 * abs(index - 2), 1.0, 1.0))
    mesh.parts.remove(vane)
    bracket = mesh.part('horn_bracket', 'alloy', {'colour': DARK_STEEL, 'brush': 16.0},
                        {'fasteners': (4, 1, 0.22), 'panel': (2, 1, 0.02), 'cavity': 0.7})
    P.slab(bracket, P.round_corners([(-0.085, -0.050), (0.085, -0.050), (0.085, 0.050), (-0.085, 0.050)],
                                    0.020, 2), 0.150, 0.200, bevel=0.008)
    riser(mesh, accent, 0.098, 0.095, detail={'bands': (0.5,), 'fasteners': (6, 1, 0.18), 'cavity': 0.6})
    gimbal(mesh, accent, 0.104, 0.280, height=0.024, thickness=0.012, segments=36)
    hose(mesh, 'coolant_loop', [(0.100, 0.200, -0.020), (0.146, 0.256, -0.052), (0.132, 0.326, 0.020),
                               (0.090, 0.345, 0.062)], [0.014, 0.013, 0.012, 0.010])
    return {'cast': (0.0, 0.408, 0.0), 'flare': (0.0, 0.300, 0.0)}


def design_tesla_arc(mesh, accent):
    """Chain lightning: an insulator stack under a toroid top load with five arc prongs."""
    coil = mesh.part('primary_coil', 'winding',
                    {'colour': COPPER, 'ribs': 62, 'shadow': (0.04, 0.038, 0.042), 'accent': accent, 'wrap': 40},
                    {'cavity': 0.78, 'glow_trim': 0.4})
    P.lathe(coil, [(0.078, 0.150), (0.092, 0.165), (0.092, 0.270), (0.078, 0.285)], segments=28,
            cap=False, wall=0.006)
    for index, (radius, height) in enumerate(((0.116, 0.126), (0.130, 0.152), (0.130, 0.288), (0.116, 0.314))):
        skirt = mesh.part(f'insulator_{index}', 'ceramic', {'colour': CERAMIC, 'segments': 8},
                          {'bands': (0.5,), 'cavity': 0.5})
        flip = -1.0 if index >= 2 else 1.0
        P.lathe(skirt, [(radius * 0.52, height), (radius, height + 0.018 * flip),
                         (radius * 0.86, height + 0.040 * flip)], segments=24, cap=False, wall=0.006)
    top = mesh.part('top_load', 'alloy', {'colour': TITANIUM, 'brush': 30.0, 'wrap': 48},
                    {'ribs': 2, 'cavity': 0.42, 'wear': 0.75})
    P.revolve(top, torus_profile(0.034, 0.024, 8), 0.126, segments=32, at=(0.0, 0.352, 0.0))
    for index in range(5):
        angle = index * TAU / 5
        prong = mesh.part(f'arc_prong_{index}', 'emitter',
                          {'colour': DARK_STEEL, 'accent': accent, 'band': 0.78, 'band_width': 0.34,
                           'glow': 3.4, 'wrap': 10}, {'cavity': 0.3})
        P.tube(prong, [(math.cos(angle) * 0.146, 0.358, math.sin(angle) * 0.146),
                       (math.cos(angle) * 0.182, 0.400, math.sin(angle) * 0.182),
                       (math.cos(angle) * 0.174, 0.446, math.sin(angle) * 0.174)],
               [0.011, 0.009, 0.004], segments=9)
    globe = mesh.part('arc_sphere', 'lens', {'colour': (0.10, 0.12, 0.16), 'accent': accent},
                      {'glow_trim': 1.8, 'cavity': 0.2})
    P.sphere(globe, (0.0, 0.402, 0.0), 0.036, segments=18, rings=10)
    rod = mesh.part('discharge_rod', 'alloy', {'colour': TITANIUM, 'brush': 22.0, 'wrap': 16},
                    {'ribs': 4, 'cavity': 0.5})
    P.lathe(rod, [(0.014, 0.300), (0.016, 0.332), (0.012, 0.352)], segments=14, cap=True)
    riser(mesh, accent, 0.108, 0.115, detail={'bands': (0.2, 0.8), 'fasteners': (8, 1, 0.18), 'cavity': 0.64})
    bolt_circle(mesh, 'base_bolt', 0.090, 0.124, count=8, size=0.013)
    return {'cast': (0.0, 0.352, 0.0), 'flare': (0.0, 0.460, 0.0)}


def design_cryo_pulse(mesh, accent):
    """Frost nova: six radial frost vanes around a chilled core, rimed from the base up."""
    housing = mesh.part('cryo_housing', 'frost',
                        {'colour': (0.34, 0.40, 0.48), 'accent': accent, 'coverage': 0.34, 'scale': 8,
                         'wrap': 32, 'glow': 1.1},
                        {'bands': (0.16, 0.84), 'fasteners': (6, 1, 0.2), 'cavity': 0.58})
    P.lathe(housing, [(0.086, 0.118), (0.108, 0.150), (0.112, 0.245), (0.092, 0.288), (0.060, 0.305),
                      (0.0, 0.322)], segments=32)
    core = mesh.part('cryo_core', 'lens', {'colour': (0.16, 0.30, 0.44), 'accent': accent},
                     {'glow_trim': 1.9, 'cavity': 0.15})
    P.sphere(core, (0.0, 0.252, 0.0), 0.058, segments=20, rings=11)
    fin = mesh.part('fin_source', 'frost', {'colour': (0.42, 0.50, 0.58), 'accent': accent, 'coverage': 0.52,
                                            'scale': 9, 'glow': 0.8},
                    {'panel': (3, 1, 0.02), 'cavity': 0.62, 'wear': 0.6})
    P.slab(fin, P.airfoil(0.170, 0.030, camber=0.018, rows=7), -0.005, 0.005, bevel=0.0018,
           at=(0.128, 0.252, 0.0))
    mesh.array('cryo_fin', fin, 6, phase=math.pi / 6)
    for index in range(3):
        angle = index * TAU / 3 + 0.4
        feed = mesh.part(f'cryo_feed_{index}', 'composite',
                         {'colour': (0.10, 0.12, 0.15), 'weave': 24.0, 'wrap': 10}, {'bands': (0.4, 0.72), 'cavity': 0.6})
        P.tube(feed, [(math.cos(angle) * 0.062, 0.132, math.sin(angle) * 0.062),
                      (math.cos(angle) * 0.118, 0.175, math.sin(angle) * 0.118),
                      (math.cos(angle) * 0.140, 0.235, math.sin(angle) * 0.140)],
               [0.013, 0.012, 0.010], segments=9)
    crown = mesh.part('cryo_crown', 'ceramic', {'colour': (0.84, 0.90, 0.96), 'segments': 6},
                      {'bands': (0.35, 0.75), 'cavity': 0.45})
    P.lathe(crown, [(0.052, 0.306), (0.066, 0.330), (0.050, 0.356), (0.024, 0.372), (0.0, 0.380)],
            segments=24)
    lit_band(mesh, 'cryo_band', accent, 0.101, 0.196, half_height=0.018, segments=36)
    bolt_circle(mesh, 'cryo_bolt', 0.084, 0.130, count=6, size=0.012, colour=(0.66, 0.72, 0.80))
    return {'cast': (0.0, 0.252, 0.0), 'flare': (0.0, 0.400, 0.0)}


def design_repair_field(mesh, accent):
    """Heal surge: a hovering service drone over a magnetic stator, on three articulated arms."""
    stator = mesh.part('levitation_stator', 'emitter',
                       {'colour': DARK_STEEL, 'accent': accent, 'band': 0.5, 'band_width': 0.30, 'glow': 2.8,
                        'wrap': 36}, {'ribs': 4, 'cavity': 0.4})
    P.lathe(stator, [(0.082, 0.116), (0.116, 0.132), (0.118, 0.168), (0.086, 0.184)], segments=36, cap=False, wall=0.006)
    shell = mesh.part('drone_shell', 'ceramic', {'colour': IVORY, 'segments': 6},
                      {'bands': (0.18, 0.58, 0.86), 'fasteners': (7, 1, 0.18), 'cavity': 0.44})
    P.lathe(shell, [(0.0, 0.262), (0.072, 0.286), (0.104, 0.345), (0.100, 0.410), (0.066, 0.452),
                    (0.0, 0.470)], segments=30)
    visor = mesh.part('drone_visor', 'lens', {'colour': (0.10, 0.16, 0.13), 'accent': accent},
                      {'glow_trim': 1.7, 'cavity': 0.2})
    P.lathe(visor, [(0.086, 0.330), (0.096, 0.360), (0.086, 0.392)], segments=26, cap=False, wall=0.006)
    heart = mesh.part('medi_core', 'emitter', {'colour': (0.05, 0.06, 0.05), 'accent': accent,
                                               'band': 0.5, 'band_width': 0.5, 'glow': 3.4, 'wrap': 16},
                      {'cavity': 0.25})
    P.sphere(heart, (0.0, 0.246, 0.0), 0.036, segments=16, rings=9)
    for index in range(3):
        angle = index * TAU / 3
        shoulder = mesh.part(f'arm_shoulder_{index}', 'alloy', {'colour': TITANIUM, 'brush': 24.0},
                             {'fasteners': (3, 1, 0.3), 'cavity': 0.6})
        P.slab(shoulder, P.regular(6, 0.030, rotation=math.pi / 6), 0.280, 0.320, bevel=0.006,
               at=(math.cos(angle) * 0.118, 0.0, math.sin(angle) * 0.118))
        arm = mesh.part(f'arm_{index}', 'alloy', {'colour': STEEL, 'brush': 20.0, 'wrap': 12},
                        {'ribs': 5, 'cavity': 0.62})
        P.tube(arm, [(math.cos(angle) * 0.118, 0.296, math.sin(angle) * 0.118),
                     (math.cos(angle) * 0.176, 0.236, math.sin(angle) * 0.176),
                     (math.cos(angle) * 0.176, 0.172, math.sin(angle) * 0.176)],
               [0.019, 0.016, 0.013], segments=11)
        tip = mesh.part(f'arm_tip_{index}', 'emitter',
                        {'colour': DARK_STEEL, 'accent': accent, 'band': 0.55, 'band_width': 0.42, 'glow': 3.0},
                        {'cavity': 0.3})
        P.sphere(tip, (math.cos(angle) * 0.176, 0.152, math.sin(angle) * 0.176), 0.022, segments=14, rings=8)
    for index in range(8):
        angle = index * TAU / 8
        optic = mesh.part(f'micro_optic_{index}', 'lens', {'colour': (0.14, 0.20, 0.16), 'accent': accent},
                          {'glow_trim': 1.4})
        P.sphere(optic, (math.cos(angle) * 0.072, 0.452, math.sin(angle) * 0.072), 0.014, segments=10, rings=6)
    gimbal(mesh, accent, 0.128, 0.372, height=0.022, thickness=0.011, segments=40)
    return {'cast': (0.0, 0.345, 0.0), 'flare': (0.0, 0.520, 0.0)}


def design_overclock(mesh, accent):
    """War cry: an overdriven piston block under a split ram-horn resonator, with a drive cog."""
    block = mesh.part('piston_block', 'alloy', {'colour': STEEL, 'brush': 22.0, 'wrap': 32},
                      {'bands': (0.14, 0.5, 0.86), 'fasteners': (8, 1, 0.18), 'panel': (4, 1, 0.016),
                       'cavity': 0.68})
    P.lathe(block, [(0.106, 0.116), (0.126, 0.145), (0.128, 0.248), (0.112, 0.282), (0.076, 0.296)],
            segments=32, cap=False, wall=0.006)
    crown = mesh.part('piston_crown', 'emitter',
                      {'colour': (0.07, 0.05, 0.045), 'accent': accent, 'band': 0.42, 'band_width': 0.40,
                       'glow': 3.2, 'wrap': 28}, {'ribs': 3, 'cavity': 0.35})
    P.lathe(crown, [(0.062, 0.288), (0.082, 0.305), (0.084, 0.330), (0.062, 0.344)], segments=28, cap=False, wall=0.006)
    for sign in (-1, 1):
        horn = mesh.part(f'ram_horn_{sign}', 'alloy', {'colour': TITANIUM, 'brush': 26.0, 'wrap': 14},
                         {'ribs': 8, 'cavity': 0.6, 'wear': 0.7})
        P.tube(horn, [(sign * 0.060, 0.330, -0.012), (sign * 0.118, 0.386, -0.026),
                      (sign * 0.150, 0.446, 0.004), (sign * 0.142, 0.488, 0.046)],
               [0.030, 0.038, 0.036, 0.026], segments=14, squash=0.78)
        tip = mesh.part(f'horn_tip_{sign}', 'emitter', {'colour': (0.06, 0.045, 0.04), 'accent': accent,
                                                        'band': 0.5, 'band_width': 0.45, 'glow': 3.0},
                         {'cavity': 0.3})
        P.lathe(tip, [(0.016, 0.486), (0.032, 0.496), (0.032, 0.514), (0.018, 0.524)], segments=14,
                cap=False, wall=0.006, at=(sign * 0.142, 0.0, 0.046))
    cog = mesh.part('drive_cog', 'alloy', {'colour': BRASS, 'brush': 18.0, 'wrap': 26},
                    {'cavity': 0.72, 'wear': 0.6})
    P.slab(cog, P.gear_outline(13, 0.082, 0.100), 0.196, 0.226, bevel=0.005)
    shaft = mesh.part('drive_shaft', 'alloy', {'colour': DARK_STEEL, 'brush': 24.0, 'wrap': 12},
                      {'ribs': 3, 'cavity': 0.6})
    P.lathe(shaft, [(0.026, 0.150), (0.030, 0.240), (0.026, 0.300)], segments=16, cap=True)
    throttle = mesh.part('throttle_collar', 'emitter',
                         {'colour': DARK_STEEL, 'accent': accent, 'band': 0.5, 'band_width': 0.30, 'glow': 2.4,
                          'wrap': 32}, {'hazard': 7, 'accent': accent, 'cavity': 0.5})
    P.lathe(throttle, [(0.122, 0.150), (0.130, 0.164), (0.130, 0.186), (0.122, 0.200)], segments=32, cap=False, wall=0.006)
    riser(mesh, accent, 0.112, 0.105, colour=DARK_STEEL,
           detail={'bands': (0.5,), 'fasteners': (6, 1, 0.2), 'cavity': 0.62})
    return {'cast': (0.0, 0.322, 0.0), 'flare': (0.0, 0.524, 0.0)}


DESIGNS = {
    'seismic_slam': design_graviton_pulse,
    'bladestorm': design_emp_burst,
    'phantom_rush': design_phase_dash,
    'shatterwave': design_sonic_disruptor,
    'chain_lightning': design_tesla_arc,
    'frost_nova_skill': design_cryo_pulse,
    'mending_light': design_repair_field,
    'warcry_skill': design_overclock,
}


# ------------------------------------------------------------------- assembly


def assemble(skill_id):
    """Author one focus: shared kit, the skill's own silhouette, then shaded and checked."""
    spec = SKILLS[skill_id]
    accent = spec['accent']
    mesh = Mesh(skill_id, atlas=ATLAS, tile=TILE)
    deck(mesh, accent)
    deck_rim(mesh, accent)
    sockets = DESIGNS[skill_id](mesh, accent)
    mesh.socket('Socket/Cast', sockets['cast'])
    mesh.socket('Socket/Flare', sockets['flare'])
    mesh.socket('Socket/Base', (0.0, 0.0, 0.0))
    mesh.orient_outward()
    mesh.shade()
    problems = mesh.validate()
    triangles = mesh.triangle_count()
    if triangles > TRIANGLE_BUDGET:
        problems.append(f'{skill_id}: {triangles} triangles exceeds the {TRIANGLE_BUDGET} prop budget')
    islands = len({mesh.island_key(part) for part in mesh.parts})
    if islands > (ATLAS // TILE) ** 2:
        problems.append(f'{skill_id}: {islands} material islands exceed the {ATLAS}² atlas grid')
    if problems:
        raise ValueError('; '.join(problems))
    return mesh, {'skill_id': skill_id, 'display_name': spec['display'], 'slug': skill_id,
                  'accent': accent, 'emissive_strength': spec['glow']}


def framed(scene, direction, fov, margin=1.34):
    """An eye placed on a direction, far enough that the whole prop is inside the frame.

    Hard-coding a camera position crops a 0.52 m focus and hides the very sockets the render is
    there to prove, so the distance is solved from the bbox and the field of view instead.
    """
    centre = scene.centre
    reach = max(scene.high[axis] - scene.low[axis] for axis in range(3))
    span = max(reach, (scene.high[1] - scene.low[1]) / math.cos(math.radians(18.0)))
    distance = max(1.2, span * 0.5 / math.tan(math.radians(fov) * 0.5) * margin)
    unit = math.sqrt(sum(value * value for value in direction))
    offset = tuple(value / unit * distance for value in direction)
    return centre[0] + offset[0], centre[1] + offset[1], centre[2] + offset[2]


def render_views(blob):
    """Verification renders from the shipped GLB: lit three-quarter hero, elevation, icon."""
    scene = raster.FocusScene(blob)
    centre = scene.centre
    hero = raster.render(scene, width=HERO_SIZE, height=HERO_SIZE, fov=24.0, samples=2,
                         eye=framed(scene, (0.78, 0.62, 0.92), 24.0), bloom=0.9, exposure=1.05)
    front = raster.render(scene, width=SILHOUETTE_SIZE, height=SILHOUETTE_SIZE, fov=20.0, samples=1,
                          eye=framed(scene, (0.02, 0.06, 1.0), 20.0, margin=1.10), floor=False,
                          bloom=0.5, exposure=0.95, background=(0.030, 0.045, 0.062))
    icon = raster.render(scene, width=ICON_SIZE, height=ICON_SIZE, fov=30.0, samples=2,
                         eye=framed(scene, (0.62, 0.70, 0.76), 30.0, margin=1.16), floor=False,
                         bloom=1.2, exposure=1.30, background=(0.0, 0.0, 0.0))
    return hero, front, icon


def build(write_renders=True, only=None):
    """Author, pack, render and lock every focus. Deterministic end to end."""
    started = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    outputs = []
    summaries = []
    hero_tiles = []
    for skill_id in SKILLS:
        if only and skill_id not in only:
            continue
        mesh, meta = assemble(skill_id)
        atlas, _tiles = pack.bake(mesh)
        maps = {name: png.encode(atlas.size, atlas.size, buffer) for name, buffer in atlas.maps.items()}
        blob = pack.to_glb(mesh, atlas, maps, meta)
        directory = OUT / skill_id
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'focus.glb').write_bytes(blob)
        outputs.append(directory / 'focus.glb')
        textures = directory / 'textures'
        textures.mkdir(exist_ok=True)
        prefix = 'Focus_' + ''.join(word.title() for word in skill_id.split('_'))
        for name, suffix in (('albedo', 'albedo'), ('normal', 'normal'), ('orm', 'ORM'), ('emissive', 'emission')):
            path = textures / f'{prefix}_{suffix}.png'
            path.write_bytes(maps[name])
            outputs.append(path)
        hero = None
        if write_renders:
            hero, front, icon = render_views(blob)
            (directory / 'focus_render.png').write_bytes(png.encode(hero['width'], hero['height'], hero['rgb']))
            (directory / 'focus_front.png').write_bytes(png.encode(front['width'], front['height'], front['rgb']))
            icons = OUT / 'icons'
            icons.mkdir(exist_ok=True)
            (icons / f'{skill_id}.png').write_bytes(
                png.encode(icon['width'], icon['height'], icon['rgb'] + icon['alpha'], channels=4))
            for path in (directory / 'focus_render.png', directory / 'focus_front.png', icons / f'{skill_id}.png'):
                outputs.append(path)
            hero_tiles.append((skill_id, hero))
        low, high = mesh.bounds()
        summaries.append({'skill_id': skill_id, 'display_name': meta['display_name'],
                          'parts': len(mesh.parts), 'triangles': mesh.triangle_count(),
                          'vertices': mesh.vertex_count(), 'islands': atlas.used, 'bytes': len(blob),
                          'atlas': ATLAS,
                          'size_metres': [round(high[axis] - low[axis], 4) for axis in range(3)],
                          'accent': [round(value, 3) for value in SKILLS[skill_id]['accent']],
                          'emissive_strength': SKILLS[skill_id]['glow']})
    if write_renders and len(hero_tiles) == len(SKILLS):
        write_showcase(hero_tiles)
        outputs.append(OUT / 'skill_showcase.png')
    report = {
        'schema_version': 1,
        'recipe': 'skill_focus_v1',
        'generator': 'tool/build_skill_foci.py',
        'license_notice': 'ASSET_LICENSES/skill-foci.md',
        'authoring': ('Project-authored hard-surface geometry with procedurally painted PBR atlases '
                      'and software-rasterized verification renders. Pure Python: no downloads, no '
                      'third-party art, no third-party motion.'),
        'budget': {'triangles_per_prop': TRIANGLE_BUDGET, 'atlas': ATLAS, 'island': TILE, 'icon': ICON_SIZE},
        'recipe_files': [{'path': path, 'sha256': hashlib.sha256((ROOT / path).read_bytes()).hexdigest()}
                         for path in RECIPE_FILES],
        'models': summaries,
        'files': [{'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size,
                   'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                  for path in sorted(set(outputs))],
    }
    (OUT / 'build_report.json').write_text(json.dumps(report, indent=2) + '\n')
    total = sum(entry['bytes'] for entry in report['files'])
    print(f'Built {len(summaries)} skill foci: {total:,} bytes in {time.time() - started:.1f}s')
    for entry in summaries:
        print(f"  {entry['skill_id']:<18} {entry['triangles']:>5} tri  {entry['parts']:>3} parts  "
              f"{entry['islands']:>2} islands  {entry['bytes']:>8,} B  "
              f"{entry['size_metres'][0]:.2f}x{entry['size_metres'][1]:.2f}x{entry['size_metres'][2]:.2f} m")
    return report


def write_showcase(tiles):
    """One contact sheet of the hero renders, so the set is judged as a set."""
    size = HERO_SIZE
    columns, rows, gap = 4, 2, 8
    width = columns * size + (columns + 1) * gap
    height = rows * size + (rows + 1) * gap
    canvas = bytearray(width * height * 3)
    for index in range(width * height):
        canvas[index * 3] = 14
        canvas[index * 3 + 1] = 19
        canvas[index * 3 + 2] = 27
    for position, (_skill_id, tile) in enumerate(tiles):
        column, row = position % columns, position // columns
        origin_x = gap + column * (size + gap)
        origin_y = gap + row * (size + gap)
        source = tile['rgb']
        for line in range(size):
            target = ((origin_y + line) * width + origin_x) * 3
            start = line * size * 3
            canvas[target:target + size * 3] = source[start:start + size * 3]
    (OUT / 'skill_showcase.png').write_bytes(png.encode(width, height, canvas))


if __name__ == '__main__':
    selected = set(sys.argv[1:])
    unknown = selected - set(SKILLS)
    if unknown:
        raise SystemExit(f'unknown skill id(s): {", ".join(sorted(unknown))}')
    build(write_renders=True, only=selected or None)
