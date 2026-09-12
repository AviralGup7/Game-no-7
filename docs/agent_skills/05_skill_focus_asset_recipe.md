# Skill 05: Authoring a Verified 3D Prop Set in Pure Python (`tool/skill_forge`)

The eight skill **cast foci** are hard-surface props that sit on the arena floor where a skill was
cast, plus the 128 px icons the skill bar draws them into. They were authored, packed, textured and
verified with nothing but the Python standard library, because this repository has no `numpy`, no
Blender and no network step. This document is the recipe: what the asset contract is, which module
does what, where the seams into gameplay are, and the five bugs that a "looks fine" render hid.

Read `03_3d_asset_pipeline_from_ai_images.md` first for the texture/packing background; this skill is
the *geometry-first* counterpart, where the model is the primary artefact and the textures are derived
from it.

---

## 1. The contract every focus must satisfy

`tool/build_skill_foci.py` fails closed on all of these; do not relax them to make a design fit,
simplify the design instead.

| Promise | Value | Enforced by |
| --- | --- | --- |
| One material, one draw call | 1 `pbrMetallicRoughness` material per GLB | `assemble()` + `check_model` |
| Atlas | 512², 4×4 islands of 128², 4-texel dilation | `material.Atlas.island_for` (raises past 16) |
| Maps | albedo / normal / ORM / emission PNG | `pack.to_glb`, `check_png` |
| Map references | a slot names a `textures[]` entry, which names `images[]` + `samplers[]` | `check_model`, `test_skill_foci.py` |
| Attributes | `POSITION` (+min/max), `NORMAL`, `TANGENT`, `TEXCOORD_0`, indices | `glb.write` |
| Triangles | ≤ 4200 per prop | `assemble()` |
| Footprint | ≤ 0.60 m across, base seated at `Y = 0` | `assemble()`, `test_skill_foci.py` |
| Winding | every closed hull CCW-outward (positive signed volume), no face wound against a neighbour | `Mesh.orient_outward`, `Mesh._edge_audit` |
| Sockets | `Socket/Cast`, `Socket/Flare`, `Socket/Base` nodes | `Mesh.socket` |

A prop is a *prop*: it never owns collision, navigation or gameplay state. The deck plate is its
visual foot, which is why `aabb_min.y == 0` is asserted — a focus that floats 4 cm above the floor
reads as a bug in the physics, not in the art.

## 2. Module map

```
tool/build_skill_foci.py        the eight designs + kit helpers + atlas, GLB and report orchestration
tool/skill_forge/mesh.py        Part/Mesh containers, UV frames, weld-and-cluster shading, audits
tool/skill_forge/primitives.py  slab, lathe, tube, revolve, outline builders (airfoil, gear, fillet)
tool/skill_forge/texture.py     value-noise/fbm/stripes/dots/ribs + the four PBR channel bakers
tool/skill_forge/material.py    nine material families + the shared machined-detail pass + the atlas
tool/skill_forge/pack.py        island packing, UV remap, part flattening, GLB assembly
tool/skill_forge/glb.py         stdlib GLB reader/writer (JSON+BIN chunks, accessors, image views)
tool/skill_forge/png.py         stdlib PNG encode/decode (deflate via zlib, CRC, IHDR/IDAT/IEND)
tool/skill_forge/raster.py      the verification renderer: reads the shipped GLB and draws it
```

`tool/skill_forge/requirements.txt` is deliberately "none".

## 3. The design language (why the set reads as one set)

Every focus is assembled from the same kit — `deck` (octagonal plate, painted rim band, fastener
ring), `deck_rim`, `riser` (the machined collar), `gimbal` (a lit ring), `lit_band`, `bolt_circle`,
plus `Socket/Cast|Flare|Base` — and only the *silhouette parts* are unique to a skill. The nine
material families are shared: `plating` for decks, `alloy` for structure, `ceramic` for insulators,
`winding` for copper, `emitter` for lit hardware, `lens` for the glowing core, `frost`,
`composite` and `marking`.

Two rules keep the family coherent:

- **Accent = the skill's own effect colour.** `SKILLS[skill_id]['accent']` is the linear RGB that
  `EffectDirector.SKILL_COLORS` already uses for the cast ring, so a focus glows the same colour as
  its particles and no new palette enters the project.
- **Mass sits low, light sits high.** The deck and riser are heavy and dark; the emissive element is
  the topmost thing on the prop. At 24 px in the skill bar that silhouette difference is the only
  thing that survives, and it is also what makes the prop readable on a busy floor.

## 4. Integration seams (no GDScript was touched)

- **Drop-in scenes**: `scenes/props/skill_focus_<skill_id>.tscn` instances the shipped GLB under a
  `SkillFocus` root. Any caller can `load()` it, `add_child()` it, and place it at the cast point.
- **Scaling**: `scripts/visuals/model_visual.gd::ModelVisual.create(scene, extent)` is the existing
  normaliser — it measures the instantiated scene's AABB and re-scales, so a designer can dial the
  prop's mass without touching the model.
- **Sockets**: `Socket/Cast` is where the effect ring should be centred, `Socket/Flare` the
  outward burst origin, `Socket/Base` the floor point. They are nodes, not vertices, so an effect
  can `get_node_or_null()` them without knowing the mesh.
- **Icons**: `data/skills/*.tres` now set `icon`, which `scripts/ui/skill_bar.gd` draws at
  `icon_max_width = 24` with `expand_icon`. The icon is rendered *from the shipped GLB*, so the bar
  can never drift from the model.
- **Catalogue**: `assets/catalog.json → gameplay_skills[*]` gained `model`, `icon` and `prop_scene`
  next to the existing `texture`, so the manifest stays the single index of what art a skill uses.

Deliberately **not** wired: instantiating the prop inside `EffectDirector._on_skill_cast` or adding
it to `scripts/arena/arena_decorator.gd`. Both are pool/placement systems with their own tests and
typed-architectural guards; a cosmetic prop that no gameplay code needs would have meant editing
pooled-scene caps and prop-count tests for zero behavioural gain. The scenes are the seam: when the
director wants one, `ModelVisual.create(load(path), extent)` is the whole call.

## 5. Verification — what "checked" means here

```bash
python3 tool/build_skill_foci.py                  # all eight, ~5 min; or pass skill ids
python3 tool/build_skill_foci.py seismic_slam     # one, while iterating on a design
python3 tool/validate_assets.py                   # 128 models incl. every focus.glb, re-parsed
                                                    # (resolves every material slot through textures[])
python3 tool/validate_resources.py                # scenes/resources incl. the 8 prop scenes
python3 -m unittest discover -s tests/python -p "test_*.py"
```

There is no Godot binary in this environment, so "verified" means: the GLB is re-read from disk and
**rendered by `tool/skill_forge/raster.py`**, which consumes the same accessors, the same embedded
PNGs and the same material the engine will. The hero shot, the elevation shot and the icon in
`data/models/skills/<skill_id>/` are all produced from those bytes — a texture wired to the wrong
index, a stride off by four bytes or a flipped tangent shows up as a visibly wrong image rather than
as a clean exit code.

`data/models/skills/build_report.json` closes the loop: the SHA-256 of all nine recipe source files,
of every output, and the measured triangle/vertex/island counts per prop. `test_skill_foci.py`
re-hashes the files on disk against it, so a hand-edit to one PNG cannot pass as "generated".

For a visual pass, `tool/serve_art.py` also serves `data/` and `tool/` under the preview host, and
`tool/skill_preview.html` spins the shipped `focus.glb` bytes with three.js and lists the set from
`build_report.json`, so the viewer cannot drift from what the generator wrote.

## 6. Six bugs that a plausible render hid (read this before writing a new generator)

1. **Winding convention.** `slab` extrudes a CCW outline into quads whose *shared* ring edge a cap
   fan must traverse the opposite way. A cap that guesses the rule instead of reading the wall makes
   a hull that is locally consistent enough to pass an edge audit while half of every cap shades
   from the inside. Fix: `_cap_fan` asks the wall which way it runs along the ring (`_wall_runs_forward`)
   and winds against it; `Mesh.orient_outward` then decides *outward* from the signed volume.
2. **Chamfer inset arithmetic.** Offsetting a profile by walking an angle bisector divides by an
   angle that goes to zero at the near-straight vertices a fillet leaves behind, so those points
   never move, the ring folds over, and every cap fanned off it alternates in sign. Fix: offset each
   *edge* and intersect the offset lines — exact for a convex outline, stable at a straight vertex.
3. **Single-sided "shells".** A lathe sleeve with `cap=False` is a surface, not a solid: looked at
   from above, the player sees the *far interior* of the prop. `wall=0.006` returns the profile on
   itself, which is the difference between a machined collar and a paper lantern. Budget for it:
   it roughly doubles a lathe, and `Tesla Arc` needed its toroid profile dropped from 12 to 8 to
   stay under 4200 triangles.
4. **Position welding is not smoothing groups.** Welding by coincident position makes a flat deck
   cap average its normal with a 45° chamfer, and the plate renders as a pinwheel of shading wedges.
   Generator caps are tagged into their own shading group (`Part.hard`), exactly as a DCC's
   hard-edge split would; curved surfaces still smooth across their quads.
5. **Dangling texture indirection.** `pbrMetallicRoughness.baseColorTexture.index` is an index into
   `textures`, and only that entry points at `images` and `samplers`. Writing image indices straight
   into the slots produces a file whose numbers all look in range, whose maps are embedded and
   correct, and that *renders* perfectly in a previewer that reads `images` — because the previewer
   repeats the writer's mistake. `godot --import` is the first thing to refuse it, in CI. Fix: emit
   `textures[]` per map, resolve the hop in the previewer too, and teach `check_model` to walk
   slot → texture → image for every model in the project. The general lesson: **a validator that
   mirrors the generator's assumptions verifies the assumptions, not the format** — read the spec's
   indirection, or better, the engine's own importer.
6. **Float noise is not a UV violation.** A bbox-normalised planar cap lands at `-1e-16` instead of
   `0.0`, which is a *generator rounding* problem, not an authoring error: `Part.vertex` clamps into
   the frame rather than leaving the pack check to fail on the last bit of a mantissa.

Two smaller traps worth naming: the shadow map must be **normal-offset** (a 192² map over a 3.2 m
span resolves 17 mm a texel, and an un-offset depth test paints acne on every curved surface), and
the preview camera must be **solved from the bbox and the FOV** (`framed()`), because a hard-coded eye
crops the tall props and hides the sockets the render exists to prove.

## 7. Adding a ninth focus

1. Add the skill's entry to `SKILLS` (display name, accent taken from `EffectDirector.SKILL_COLORS`,
   emissive strength) and a `design_<name>` function to `DESIGNS`.
2. Author silhouette parts only; reuse the kit for anything the other eight already have.
3. Run `python3 tool/build_skill_foci.py <skill_id>`, look at `focus_render.png` **and**
   `focus_front.png` and the 128 px icon, and iterate until the silhouette is identifiable at all
   three sizes.
4. Add the id to `FOCI` in `tests/python/test_skill_foci.py`, wire `data/skills/<id>.tres`,
   `assets/catalog.json` and `scenes/props/skill_focus_<id>.tscn`, then run every gate in §5.
