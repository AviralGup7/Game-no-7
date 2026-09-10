"""Regression: the arena's authored world (theme, landmark, obstacle layout).

Why these pins exist
--------------------
`Arena` used to own its arena's identity as three code tables keyed by arena id *string*:

    const THEMES := { "ember_crucible": { "sun_color": Color(...), ... }, ... }
    const PANORAMA_SKIES := { "default_arena": PANORAMA_BASE + "spruit_sunrise_1k.hdr", ... }
    ArenaObstacles.layout_for() -> match String(arena_id): ... ; _: <The Pit's numbers>

and it passed one more record type around: `{"pos", "half_size", "kind"}` Dictionaries, built
by the table above and consumed with `ob.get("pos", Vector3.ZERO)` by the collision builder,
the mesh builder *and* the nav grid. Every one of those had the same failure shape: a missing
entry or a misspelt key was indistinguishable from success. A new arena .tres got the default
look, the default pillars, and (per the old `_:` arms) a default obelisk instead of its forge;
a layout entry whose key was typo'd landed at the origin, inside the landmark, still solid,
still blocking nav, still drawn nowhere. `docs/EXTENDING.md` promised "additional arenas = a
new scene + an ArenaConfig" while three files said otherwise.

The look is now `ArenaConfig.theme` (ArenaThemeConfig), the centrepiece is `ArenaConfig.landmark`
(ArenaLandmarkConfig) and the interior is `ArenaConfig.obstacle_layout`
(Array[ArenaObstaclePlacement]) — validated resources referenced by path, not by id, with the
geometry crossing API boundaries as AABBs.

Like the hazard and status suites, the point is not "some numbers moved": a weak design is
*pinned out* so it cannot come back quietly, and the shipped values are audited so a "cleanup"
that changes what a player sees has to be a deliberate edit to this file. Each check was
verified to fail when the matching regression was injected into a scratch copy of the repo.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

ARENA_GD = "scripts/arena/arena.gd"
OBSTACLES_GD = "scripts/arena/arena_obstacles.gd"
PLACEMENT_GD = "scripts/arena/arena_obstacle_placement.gd"
THEME_GD = "scripts/arena/arena_theme_config.gd"
LANDMARK_GD = "scripts/arena/arena_landmark_config.gd"
BUILDER_GD = "scripts/arena/arena_landmark.gd"
CONFIG_GD = "scripts/arena/arena_config.gd"
NAV_GD = "scripts/arena/arena_nav_grid.gd"
DECOR_GD = "scripts/arena/arena_decorator.gd"

ARENAS = ("default_arena", "ember_crucible", "frost_hollow")
INTERIOR_HALF = 12.0
AXIS_SPAWNS = ((11.0, 0.0), (-11.0, 0.0), (0.0, 11.0), (0.0, -11.0))
# Spawn jitter (1.2 m) + the safety margin SpawnManager adds (0.5 m). An obstacle closer than
# foot + this to a spawn marker can be touched by a legal jittered spawn, which is the bug the
# ember ring used to have at 8.5 m.
SPAWN_CLEARANCE = 1.7


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code(rel: str) -> str:
    """Source without comment lines. These files deliberately name the designs they ban in
    prose (`{"pos", "half_size"}`, `match String(arena_id)`, `_:`), so a token ban has to
    scan code, not documentation."""
    return "\n".join(l for l in read(rel).splitlines() if not l.lstrip().startswith("#"))


def resource_block(path: pathlib.Path) -> dict[str, str]:
    out: dict[str, str] = {}
    inside = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("[resource]"):
            inside = True
            continue
        if inside and line.startswith("["):
            break
        if inside and "=" in line:
            key, value = line.split("=", 1)
            out[key.strip()] = value.strip()
    return out


def numbers(raw: str | None) -> tuple[float, ...]:
    """The numeric arguments of Color(...) / Vector3(...) / a bare float literal.

    The arguments, not every digit: a .tres value line carries its type name, and matching
    digits naively reads the 3 in `Vector3` as a component (which is how this helper first
    reported a landmark footprint of (3.0, 0.55, 2.3, 0.55))."""
    if raw is None:
        return ()
    text = raw.strip()
    if "(" in text and ")" in text:
        text = text[text.index("(") + 1:text.rindex(")")]
    return tuple(float(t) for t in re.findall(r"-?\d+\.?\d*(?:[eE][+-]?\d+)?", text))


def theme_file(arena_id: str) -> dict[str, str]:
    return resource_block(ROOT / "data" / "arena_themes" / f"{arena_id}.tres")


def landmark_file(arena_id: str) -> dict[str, str]:
    text = read(f"data/arenas/{arena_id}.tres")
    m = re.search(r'landmark = ExtResource\("([^"]+)"\)', text)
    assert m, f"{arena_id} authors no landmark reference"
    path = re.search(r'id="%s"\]' % re.escape(m.group(1)), text)
    assert path, f"{arena_id}: landmark ExtResource {m.group(1)} is not declared"
    ext = re.search(r'\[ext_resource type="Resource" path="([^"]+)" id="%s"\]' % re.escape(m.group(1)), text)
    assert ext, f"{arena_id}: landmark reference has no path"
    return resource_block(ROOT / ext.group(1).replace("res://", ""))


def expanded_obstacles(arena_id: str) -> list[tuple[float, float, float, float, float, float]]:
    """(x, z, half_x, half_y, half_z, index) per *placed* obstacle, mirrors expanded, in the
    order ArenaObstacles.expand() produces them."""
    text = read(f"data/arenas/{arena_id}.tres")
    layout = re.search(r"obstacle_layout = Array\[ArenaObstaclePlacement\]\(\[(.*?)\]\)", text, re.S)
    assert layout is not None, f"{arena_id}.tres authors no obstacle_layout"
    out = []
    for rid in re.findall(r'SubResource\("([^"]+)"\)', layout.group(1)):
        block = re.search(r'\[sub_resource type="Resource" id="%s"\]\n(.*?)(?=\n\[|\Z)' % re.escape(rid),
                          text, re.S)
        assert block is not None, f"{arena_id}: obstacle placement {rid} referenced but undefined"
        body = block.group(1)
        x, _y, z = numbers(re.search(r"position = Vector3\(([^)]*)\)", body).group(1))
        hx = numbers(re.search(r"half_size_x = (.*)", body).group(1))[0]
        hy = numbers(re.search(r"half_size_y = (.*)", body).group(1))[0]
        hz = numbers(re.search(r"half_size_z = (.*)", body).group(1))[0]
        mirror_m = re.search(r'mirror = &"(\w+)"', body)
        mirror = mirror_m.group(1) if mirror_m else "none"
        points = [(x, z)]
        if mirror in ("x", "both", "rot180"):
            points.append((-x, z))
        if mirror in ("z", "both", "rot180"):
            points.append((x, -z))
        if mirror == "both":
            points.append((-x, -z))
        counts = {"none": 1, "x": 2, "z": 2, "rot180": 2, "both": 4}
        assert len(points) == counts[mirror], f"{arena_id}/{rid}: mirror expansion disagrees with GDScript"
        for i, (px, pz) in enumerate(points):
            out.append((px, pz, hx, hy, hz, float(i)))
    return out


# --------------------------------------------------------------------------------
# The shipped look, transcribed from the deleted tables. This is the fidelity contract:
# moving authorship into data was only allowed because every number below stayed put.
# --------------------------------------------------------------------------------

SHIPPED_LOOK = {
    "ember_crucible": {
        "sky_top": (0.12, 0.03, 0.02), "sky_horizon": (0.85, 0.28, 0.08),
        "ground_horizon": (0.35, 0.12, 0.05), "fog_color": (0.62, 0.26, 0.1),
        "sun_color": (1.0, 0.5, 0.2), "ambient_color": (0.85, 0.45, 0.28),
        "floor_tint": (0.88, 0.6, 0.46), "wall_tint": (0.78, 0.5, 0.38),
        "fog_density": 0.02, "sun_energy": 1.7, "brightness": 1.0, "contrast": 1.1,
        "panorama": "venice_sunset_1k.hdr",
    },
    "frost_hollow": {
        "sky_top": (0.18, 0.28, 0.48), "sky_horizon": (0.82, 0.9, 1.0),
        "ground_horizon": (0.42, 0.58, 0.78), "fog_color": (0.62, 0.72, 0.9),
        "sun_color": (0.7, 0.8, 1.0), "ambient_color": (0.68, 0.8, 1.0),
        "floor_tint": (0.72, 0.8, 0.9), "wall_tint": (0.6, 0.7, 0.84),
        "fog_density": 0.017, "sun_energy": 1.35, "brightness": 0.98, "contrast": 1.08,
        "panorama": "moonless_golf_1k.hdr",
    },
    "default_arena": {
        "sky_top": (0.22, 0.42, 0.68), "sky_horizon": (0.72, 0.82, 0.92),
        "ground_horizon": (0.38, 0.42, 0.48), "fog_color": (0.66, 0.68, 0.72),
        "sun_color": (1.0, 0.92, 0.78), "ambient_color": (0.7, 0.73, 0.8),
        "floor_tint": (0.66, 0.64, 0.6), "wall_tint": (0.72, 0.7, 0.68),
        "fog_density": 0.011, "sun_energy": 1.2, "brightness": 1.02, "contrast": 1.06,
        "panorama": "spruit_sunrise_1k.hdr",
    },
}
# The environment numbers every arena shared and `apply_theme` welded into code
# (ambient energy, the glow triple, fog-sky-affect). They are authored per theme now, which
# is the point — so they have to be *listed* here to prove nothing drifted.
SHARED_LOOK = {"ambient_energy": 0.85, "glow_intensity": 0.55, "glow_bloom": 0.05,
               "glow_hdr_threshold": 1.1, "fog_sky_affect": 0.25}
# Per-arena landmark: (kind, shape, footprint half, accent, emissive energy, light energy,
# light range, light y). The first three reproduce the collision body AND the nav footprint,
# which were two hand-kept numbers before this type existed.
SHIPPED_LANDMARKS = {
    "default_arena": ("obelisk", "box", (0.55, 2.3, 0.55), (0.85, 0.75, 0.45), 1.2, 1.1, 6.0, 2.0),
    "ember_crucible": ("forge", "cylinder", (1.9, 0.7, 1.9), (1.0, 0.42, 0.1), 4.5, 2.2, 8.0, 1.2),
    "frost_hollow": ("crystal", "cylinder", (1.4, 1.6, 1.4), (0.45, 0.75, 1.0), 1.8, 1.8, 7.0, 1.5),
}
# The landmark body materials as they were hard-coded per kind.
SHIPPED_LANDMARK_MATERIALS = {
    "default_arena": ((0.6, 0.56, 0.5), 0.78),
    "ember_crucible": ((0.32, 0.26, 0.24), 0.8),
    "frost_hollow": ((0.75, 0.85, 1.0, 0.9), 0.15),
}
# The full placed set of each arena, exactly as the deleted `match String(arena_id)` table
# emitted it (positions already mirrored out, in table order). 6 / 8 / 8 obstacles.
SHIPPED_OBSTACLES = {
    "default_arena": (
        (6.5, 6.5, 0.8, 1.5, 0.8), (-6.5, 6.5, 0.8, 1.5, 0.8),
        (6.5, -6.5, 0.8, 1.5, 0.8), (-6.5, -6.5, 0.8, 1.5, 0.8),
        (3.6, 0.0, 0.7, 1.15, 0.7), (-3.6, 0.0, 0.7, 1.15, 0.7),
    ),
    "ember_crucible": (
        (8.0, 0.0, 0.8, 1.5, 0.8), (-8.0, 0.0, 0.8, 1.5, 0.8),
        (0.0, 8.0, 0.8, 1.5, 0.8), (0.0, -8.0, 0.8, 1.5, 0.8),
        (8.0, 8.0, 0.7, 1.15, 0.7), (-8.0, 8.0, 0.7, 1.15, 0.7),
        (8.0, -8.0, 0.7, 1.15, 0.7), (-8.0, -8.0, 0.7, 1.15, 0.7),
    ),
    "frost_hollow": (
        (7.5, 7.5, 0.8, 1.5, 0.8), (-7.5, 7.5, 0.8, 1.5, 0.8),
        (7.5, -7.5, 0.8, 1.5, 0.8), (-7.5, -7.5, 0.8, 1.5, 0.8),
        (4.5, 7.5, 0.7, 1.15, 0.7), (-4.5, 7.5, 0.7, 1.15, 0.7),
        (4.5, -7.5, 0.7, 1.15, 0.7), (-4.5, -7.5, 0.7, 1.15, 0.7),
    ),
}
# The clearance `ArenaConfig.validate()` allows between a placement centre and the landmark box
# before calling it buried. Kept here so both sides are checked against the same number.
LANDMARK_CLEARANCE = 0.25


def close(a: float, b: float) -> bool:
    return abs(a - b) < 1e-5


class IdTablesAreGoneTests(unittest.TestCase):
    """The design itself is what gets pinned: no arena id may select behaviour in code."""

    def test_arena_holds_no_theme_or_panorama_table(self):
        src = code(ARENA_GD)
        for banned in ("THEMES :=", "PANORAMA_SKIES", "PANORAMA_BASE", "preset.get(", "float(preset",
                       'get("sun_energy"', 'get("floor_tint"', 'get("landmark"'):
            self.assertNotIn(banned, src, f"the id-keyed table is back in arena.gd: {banned}")
        self.assertNotIn("match String(arena_id)", src, "arena.gd must not branch on an arena id")

    def test_no_arena_id_literals_outside_the_default(self):
        """`arena_id`'s own export default is fine; naming *other* arenas is not."""
        for rel in (ARENA_GD, OBSTACLES_GD, NAV_GD, CONFIG_GD, BUILDER_GD, THEME_GD, LANDMARK_GD):
            src = code(rel)
            for other in ("ember_crucible", "frost_hollow"):
                self.assertNotIn(f'"{other}"', src, f"{rel} still hard-codes the arena '{other}'")
            self.assertNotIn('"default_arena":', src, f"{rel} still keys a table by arena id")

    def test_obstacle_layout_is_read_from_the_config_not_matched_on_id(self):
        src = code(OBSTACLES_GD)
        self.assertNotIn("match String(arena_id)", src, "ArenaObstacles went back to an id table")
        self.assertIn("static func layout_for(config: ArenaConfig, half: float)", src,
                      "layout_for must take the authored config; an id argument invites a table")
        self.assertIn("config.obstacle_layout", src)
        body = src[src.index("static func layout_for"):].split("\nstatic func ")[0]
        self.assertIn("expand(fallback_layout(half))", body,
                      "the fallback must go through the same mirror expansion an authored layout "
                      "gets, or an arena with no layout gets two obstacles where it should get six")
        self.assertIn("expand(config.obstacle_layout)", body)
        expand_body = src[src.index("static func expand"):].split("\nstatic func ")[0]
        self.assertIn("out.append(p.duplicate_at(pos))", expand_body,
                      "expansion must copy before positioning: writing through a shared authored "
                      "resource leaves every quadrant of the mirror at the last position")

    def test_the_landmark_refuses_an_unknown_kind_instead_of_defaulting(self):
        self.assertIn("if kind not in VALID_KINDS:", code(LANDMARK_GD),
                      "validate() stopped refusing ids, so the builder's refusal is now the only check")
        builder = code(BUILDER_GD)
        self.assertIn('push_error("ArenaLandmark: kind', builder,
                      "the silent `_:` obelisk is back: an unbuildable kind must say so")
        self.assertIn("return", builder[builder.index("push_error"):builder.index("push_error") + 240],
                      "after refusing, the builder must return without building or blocking")
        for kind in ("KIND_FORGE", "KIND_CRYSTAL", "KIND_OBELISK"):
            self.assertIn(kind, builder, f"the {kind} silhouette is gone from the builder")
        self.assertNotIn("_hd_marble_mat", read(BUILDER_GD),
                         "the dead marble helper was not resurrected along with the rest")
        # Accessors nothing calls are worse than no accessors: they invite a second source of
        # truth for a number that has one on purpose.
        cfg_src = code(LANDMARK_GD)
        self.assertNotIn("func is_none()", cfg_src,
                         "`none` is not a valid kind, so a helper for it would offer a lie")
        self.assertNotIn("func collision_offset_y", cfg_src,
                         "the body's vertical offset is derived from footprint_half in ArenaLandmark only")
        self.assertIn("func footprint() -> AABB:", cfg_src, "footprint() is the single geometry accessor")

    def test_node_identity_is_authored_not_sniffed_from_names(self):
        src = code(ARENA_GD)
        self.assertNotIn('name == &"Floor"', src, "floor identity is back to node-name sniffing")
        self.assertIn("theme.floor_node_path", src)
        self.assertIn("theme.wall_node_prefix", src)
        self.assertIn('@export var floor_node_path: NodePath', code(THEME_GD))

    def test_decorator_is_the_one_documented_id_branch(self):
        """The decor scatter is seeded from the arena id, so re-keying it to data would move
        every prop in a shipped arena. That needs a visual sign-off this repository cannot get
        without an engine, so the branch stays -- bounded, counted, and named in the docs."""
        src = code(DECOR_GD)
        self.assertEqual(src.count("match String(arena_id)"), 1,
                         "the decor branch may stay exactly one; a second one means the tables are back")
        self.assertIn("per-arena", read("docs/EXTENDING.md").lower(),
                      "the exception has to be discoverable where a modder reads it")


class RecordTypesAreGoneTests(unittest.TestCase):
    """No {"pos","half_size","kind"} bags, no key lookups with defaults, on either side."""

    def test_no_dictionary_obstacle_records(self):
        for rel in (ARENA_GD, OBSTACLES_GD, NAV_GD, PLACEMENT_GD):
            src = code(rel)
            for banned in ('.get("pos"', '.get("half_size"', '["pos"]', '["half_size"]', '["kind"]',
                           '{"pos":', 'ob.get('):
                self.assertNotIn(banned, src, f"{rel} reads obstacle fields out of a Dictionary again: {banned}")
        self.assertIn("var _obstacles: Array[ArenaObstaclePlacement]", code(ARENA_GD))

    def test_nav_grid_takes_typed_boxes(self):
        src = code(NAV_GD)
        self.assertIn("func build(half_extent: float, cell_size_value: float, blockers: Array[AABB]) -> void:", src,
                      "ArenaNavGrid.build went back to an untyped Array of records")
        self.assertNotIn("raw is Dictionary", src, "the grid must not accept a key-bag")
        # The guard that makes an authored NaN a no-op instead of a poisoned grid.
        self.assertIn("is_finite(p.x) and is_finite(p.z) and is_finite(s.x) and is_finite(s.z)", src)
        arena = code(ARENA_GD)
        self.assertIn("ArenaObstacles.footprints(_obstacles)", arena,
                      "the nav blockers must come from the same typed placements as the bodies")
        self.assertIn("ArenaObstacles.blocks_nav(landmark_box)", arena,
                      "a landmark that was refused must not block cells it does not occupy")

    def test_the_one_nav_block_rule_and_no_invented_engine_members(self):
        # `.has_area()` is a Rect2 member; on an `AABB` the engine spells it `has_volume()`. Asking an
        # AABB for the wrong one is not a runtime miss but a *parse* error, and it sat in this tree for
        # two passes because while another script in the dependency chain failed to parse, the compiler
        # stopped resolving types here and reported nothing. The question now has one named answer that
        # both nav callers ask, and the member it replaced is banned from coming back.
        obstacles = code(OBSTACLES_GD)
        self.assertIn("static func blocks_nav(box: AABB) -> bool:", obstacles)
        self.assertIn("return box.size.x > 0.0 and box.size.z > 0.0", obstacles)
        arena = code(ARENA_GD)
        self.assertEqual(arena.count("ArenaObstacles.blocks_nav("), 2,
                         "the landmark and the decoration props must ask the same function")
        for rel in (ARENA_GD, OBSTACLES_GD, BUILDER_GD, NAV_GD):
            self.assertNotIn(".has_area(", code(rel),
                             f"{rel} asks an AABB for the Rect2 member again")
        suite = code("tests/unit/test_arena_world.gd")
        self.assertNotIn(".has_area(", suite, "the suite invented the same member")
        # A suite that cannot compile used to contribute zero cases and zero failures.
        runner = code("tests/run_tests.gd")
        self.assertIn("if script.reload_failed:", runner)
        self.assertIn("Suite ran no cases", runner)

    def test_the_geometry_derivation_lives_on_the_type(self):
        """One derivation of "the box this object occupies", used by nav and by the grid."""
        src = code(PLACEMENT_GD)
        body = src[src.index("func footprint()"):].split("\nfunc ")[0]
        self.assertIn("position - hs", body, "footprint() must centre the box on the authored position")
        self.assertIn("hs * 2.0", body)
        obstacles = code(OBSTACLES_GD)
        nav_block = obstacles[obstacles.index("static func footprints"):].split("\nstatic func ")[0]
        self.assertIn("e.footprint()", nav_block,
                      "footprints() must delegate to the placement instead of re-deriving the box")

    def test_build_nodes_sizes_come_from_the_placement(self):
        src = code(OBSTACLES_GD)
        self.assertIn("var hs := ob.half_extents()", src)
        self.assertIn("box.size = hs * 2.0", src)
        self.assertIn("bm.size = hs * 2.0", src,
                      "the mesh and the collision shape must be the same box, from the same field")
        self.assertIn("body.position = Vector3(ob.position.x, hs.y, ob.position.z)", src,
                      "y is the half height so the box rests on the floor")


class TypeContractTests(unittest.TestCase):
    def test_configs_are_validated_at_load(self):
        for rel in (THEME_GD, LANDMARK_GD):
            src = read(rel)
            self.assertIn("extends ValidatedConfig", src,
                          f"{rel} is not validated at load, so an authored mistake ships")
            self.assertIn("func validate() -> Array[String]:", src)
        placement = read(PLACEMENT_GD)
        self.assertIn("extends Resource", placement,
                      "a placement is a nested entry, not a registry row: it is validated by its owner")
        self.assertIn("func validate() -> Array[String]:", placement)
        self.assertIn("problems.append_array(theme.validate())", code(CONFIG_GD),
                      "ArenaConfig must reach its theme's rules: the theme is not in any registry table")
        self.assertIn("problems.append_array(landmark.validate())", code(CONFIG_GD))
        self.assertIn("_obstacle_landmark_overlap(landmark)", code(CONFIG_GD))

    def test_validate_rule_messages_are_pinned_verbatim(self):
        """A rule count is not a guard: deleting a rule keeps the count honest only until
        someone notices. The messages are the load-bearing half, so each is pinned as text."""
        rules = {
            THEME_GD: ["theme_id is empty", "would hide the far half of the arena",
                       "must be a res:// path", "must name an .hdr", "has a non-finite channel",
                       "floor_node_path is empty", "wall_node_prefix is empty"],
            LANDMARK_GD: ["landmark_id is empty", "unknown landmark kind", "unknown landmark collision shape",
                          "an obelisk is a box", "it is scenery", "must sit on the floor", "needs a range"],
            PLACEMENT_GD: ["unknown obstacle mirror", "half extents must be > 0.05",
                           "an obstacle geometry number is not finite"],
        }
        for rel, needles in rules.items():
            src = read(rel)
            for needle in needles:
                self.assertIn(needle, src, f"{rel} lost the rule that says: {needle}")

    def test_every_ambient_colour_is_audited(self):
        """The validator sweeps a fixed list of colour fields. If a designer adds a Color
        export and the list is not widened, that field can carry a NaN into Environment
        unchecked -- so the list and the exports are compared here, where it is cheap."""
        for rel, extra in ((THEME_GD, 0), (LANDMARK_GD, 0)):
            src = read(rel)
            exported = set(re.findall(r"@export var (\w+): Color", src))
            listed = re.search(r"const COLOR_FIELDS := \[(.*?)\]", src, re.S)
            self.assertIsNotNone(listed, f"{rel}: the colour audit list is gone, so NaN colours ship unchecked")
            audited = set(re.findall(r'"(\w+)"', listed.group(1)))
            self.assertEqual(exported, audited,
                             f"{rel}: exported Colours {sorted(exported)} and audited {sorted(audited)} disagree")

    def test_numbers_have_editor_ranges(self):
        """@export_range is the other half of validation: the inspector must not be able to
        drag fog density to 3.0 or an obstacle flat to a plane in the first place. Vector3 /
        bool / StringName / Color exports are exempt because the hint does not apply to them —
        they are covered by validate() rules instead."""
        for rel, minimum in ((THEME_GD, 9), (LANDMARK_GD, 6), (PLACEMENT_GD, 3)):
            src = read(rel)
            ranged = set(re.findall(r"@export_range\([^)]*\) var (\w+): float", src))
            bare = set(re.findall(r"@export var (\w+): float", src))
            self.assertFalse(bare, f"{rel} exports floats with no range: {sorted(bare)}")
            self.assertGreaterEqual(len(ranged), minimum,
                                    f"{rel}: only {len(ranged)} range-enforced numbers (was {minimum}); "
                                    "a field whose hint was deleted stops being undraggable")
            for field in ranged:
                self.assertRegex(src, r"@export_range\([^)]*\) var %s: float" % field)

    def test_mirror_vocabulary_is_shared_with_hazards(self):
        """One arena reads as one coordinate system. The mirror ids an obstacle accepts must
        be the ids a hazard accepts, or the same .tres ends up with two spellings for 'x'."""
        def consts(rel: str) -> set[str]:
            return set(re.findall(r'const MIRROR_\w+ := &"(\w+)"', read(rel)))
        self.assertEqual(consts(PLACEMENT_GD), consts("scripts/arena/hazard_placement.gd"))

    def test_the_obsolete_kind_field_stayed_deleted(self):
        """The old records carried `kind`, which nothing read: an unread field in a validated
        type is worse than no field, because it invites an author to trust it."""
        for rel in (PLACEMENT_GD, OBSTACLES_GD):
            self.assertNotIn("KIND_PILLAR", code(rel))
            self.assertNotIn("@export var kind", code(rel))


class ShippedDataFidelityTests(unittest.TestCase):
    """Every number the deleted tables held is re-read from the .tres files the game loads."""

    def test_arenas_author_their_whole_world(self):
        for arena_id in ARENAS:
            text = read(f"data/arenas/{arena_id}.tres")
            for field in ("theme", "landmark", "obstacle_layout"):
                self.assertIn(f"{field} = ", text, f"{arena_id} does not author {field}")
            for m in re.finditer(r'(theme|landmark) = ExtResource\("([^"]+)"\)', text):
                ext = re.search(r'path="([^"]+)" id="%s"\]' % re.escape(m.group(2)), text)
                self.assertIsNotNone(ext, f"{arena_id}: {m.group(1)} reference is not declared")
                target = ROOT / ext.group(1).replace("res://", "")
                self.assertTrue(target.exists(), f"{arena_id}: {m.group(1)} points at a missing file {ext.group(1)}")
                # The loader keys tables by id; these two are referenced by path, so the file
                # name is the only identity left to keep true -- and a mismatch is how a copied
                # .tres ships pretending to be the arena it was copied from.
                fields = resource_block(target)
                key = "theme_id" if m.group(1) == "theme" else "landmark_id"
                want = "&" + '"' + target.stem + '"'
                if m.group(1) == "theme":
                    self.assertEqual(fields.get(key), f'&"{arena_id}"',
                                     f"{m.group(1)} file {target.name} declares {fields.get(key)}")
                else:
                    self.assertEqual(fields.get(key), want,
                                     f"{m.group(1)} file {target.name} declares {fields.get(key)}")
                self.assertTrue(0 < len(target.read_text(encoding="utf-8")) < 4000,
                                f"{m.group(1)} file is not a small authored resource")

    def test_theme_numbers_match_the_deleted_table(self):
        for arena_id, look in SHIPPED_LOOK.items():
            fields = theme_file(arena_id)
            self.assertEqual(fields.get("theme_id"), f'&"{arena_id}"',
                             f"{arena_id} must own its theme (the file-name rule is the only 'key' left)")
            for key in ("sky_top", "sky_horizon", "ground_horizon", "fog_color", "sun_color",
                        "ambient_color", "floor_tint", "wall_tint"):
                got = numbers(fields.get(key))
                want = look[key]
                self.assertEqual(len(got), len(want), f"{arena_id}.{key}: not a full Color literal")
                for g, w in zip(got, want):
                    self.assertTrue(close(g, w), f"{arena_id}.{key}: {got} != {want}")
            for key in ("fog_density", "sun_energy", "brightness", "contrast"):
                self.assertTrue(close(numbers(fields.get(key))[0], look[key]),
                                f"{arena_id}.{key} moved: {fields.get(key)} != {look[key]}")
            for key, want in SHARED_LOOK.items():
                self.assertTrue(close(numbers(fields.get(key))[0], want),
                                f"{arena_id}.{key} moved: {fields.get(key)} != {want}")
            self.assertIn(look["panorama"], fields.get("panorama_path", ""),
                          f"{arena_id} lost its real sky")

    def test_themes_are_distinct_and_their_skis_exist(self):
        skies = {}
        for arena_id in ARENAS:
            path = theme_file(arena_id).get("panorama_path", "").strip('"')
            self.assertTrue(path.startswith("res://assets/textures/panorama/"),
                            f"{arena_id} panorama must come from the locked HDRI folder: {path}")
            self.assertTrue((ROOT / path.replace("res://", "")).exists(), f"{path} is not in the repository")
            skies[arena_id] = path
        self.assertEqual(len(set(skies.values())), 3, "the three arenas share a sky")

    def test_landmark_numbers_match_the_deleted_shapes(self):
        for arena_id, (kind, shape, half, accent, emissive, energy, rng, offy) in SHIPPED_LANDMARKS.items():
            fields = landmark_file(arena_id)
            self.assertEqual(fields.get("kind"), f'&"{kind}"', f"{arena_id} lost its landmark kind")
            self.assertEqual(fields.get("shape"), f'&"{shape}"', f"{arena_id} changed its collision shape")
            got_half = numbers(fields.get("footprint_half"))
            for g, w in zip(got_half, half):
                self.assertTrue(close(g, w), f"{arena_id} footprint {got_half} != {half}")
            self.assertTrue(close(numbers(fields.get("emissive_energy"))[0], emissive))
            self.assertTrue(close(numbers(fields.get("light_energy"))[0], energy))
            self.assertTrue(close(numbers(fields.get("light_range"))[0], rng))
            self.assertTrue(close(numbers(fields.get("light_offset_y"))[0], offy))
            self.assertEqual(numbers(fields.get("accent_color"))[:3], accent,
                             f"{arena_id} accent moved: {fields.get('accent_color')}")
            tint, rough = SHIPPED_LANDMARK_MATERIALS[arena_id]
            self.assertEqual(numbers(fields.get("material_tint"))[:len(tint)], tint,
                             f"{arena_id} landmark material tint moved")
            self.assertTrue(close(numbers(fields.get("material_roughness"))[0], rough))
            # A landmark stands on the floor: position 0, and the nav box is the authored half
            # extents, not a second number kept by hand.
            self.assertEqual(numbers(fields.get("position")), (0.0, 0.0, 0.0),
                             f"{arena_id}'s landmark is off the floor")

    def test_obstacle_layouts_are_the_placed_set_that_shipped(self):
        for arena_id, want in SHIPPED_OBSTACLES.items():
            got = expanded_obstacles(arena_id)
            self.assertEqual(len(got), len(want),
                             f"{arena_id}: {len(got)} placed obstacles, expected {len(want)}")
            for (x, z, hx, hy, hz, _i), (wx, wz, whx, why, whz) in zip(got, want):
                self.assertTrue(close(x, wx) and close(z, wz),
                                f"{arena_id}: obstacle at ({x}, {z}) != ({wx}, {wz})")
                self.assertTrue(close(hx, whx) and close(hy, why) and close(hz, whz),
                                f"{arena_id}: obstacle size ({hx}, {hy}, {hz}) != ({whx}, {why}, {whz})")

    def test_fallback_is_the_pit_layout_and_shares_its_numbers(self):
        """The fallback exists for arenas that author nothing; it is only defensible while it
        is the same geometry The Pit ships, scaled by the floor size."""
        src = code(OBSTACLES_GD)
        self.assertIn("Vector3(6.5 * s, 0.0, 6.5 * s)", src, "the fallback's corner ring moved")
        self.assertIn("Vector3(3.6 * s, 0.0, 0.0)", src, "the fallback's gate moved")
        self.assertIn("PILLAR_HALF * s", src)
        self.assertIn("BLOCK_HALF * s", src)
        self.assertIn("clampf(half / FALLBACK_REFERENCE_HALF, FALLBACK_MIN_SCALE, FALLBACK_MAX_SCALE)", src)
        for name, value in (("PILLAR_HALF", (0.8, 1.5, 0.8)), ("BLOCK_HALF", (0.7, 1.15, 0.7))):
            got = numbers(re.search(r"const %s := Vector3\(([^)]*)\)" % name, src).group(1))
            self.assertEqual(got, value, f"the fallback's {name} drifted from the authored size")
        placed = [tuple(o[:5]) for o in expanded_obstacles("default_arena")]
        self.assertEqual(placed, list(SHIPPED_OBSTACLES["default_arena"]),
                         "The Pit no longer authors what the fallback generates")

    def test_shipped_layouts_respect_their_arena_bounds(self):
        """ArenaConfig cannot check this (the interior half-extent lives on the scene), so the
        data side is checked here: an obstacle authored through a wall is a mistake, and one
        too close to a spawn marker can be clipped by jitter."""
        for arena_id, placed in ((a, expanded_obstacles(a)) for a in ARENAS):
            for (x, z, hx, _hy, hz, _i) in placed:
                foot = max(hx, hz)
                self.assertLessEqual(abs(x) + foot, INTERIOR_HALF - 1.0,
                                     f"{arena_id}: obstacle at ({x}, {z}) is inside a wall")
                self.assertLessEqual(abs(z) + foot, INTERIOR_HALF - 1.0,
                                     f"{arena_id}: obstacle at ({x}, {z}) is inside a wall")
                for (sx, sz) in AXIS_SPAWNS:
                    gap = ((x - sx) ** 2 + (z - sz) ** 2) ** 0.5
                    self.assertGreater(gap, foot + SPAWN_CLEARANCE,
                                       f"{arena_id}: obstacle at ({x}, {z}) touches spawn ({sx}, {sz})")

    def test_no_shipped_obstacle_is_buried_in_its_landmark(self):
        """Same rule as ArenaConfig._obstacle_landmark_overlap, run from the data side, so a
        shipped layout is proven to satisfy the rule before the rule can halt startup."""
        for arena_id in ARENAS:
            fields = landmark_file(arena_id)
            half = numbers(fields.get("footprint_half"))
            scale = numbers(fields.get("scale"))[0]
            origin = numbers(fields.get("position"))
            for (x, z, _hx, _hy, _hz, _i) in expanded_obstacles(arena_id):
                buried = (abs(x - origin[0]) < half[0] * scale + LANDMARK_CLEARANCE
                          and abs(z - origin[2]) < half[2] * scale + LANDMARK_CLEARANCE)
                self.assertFalse(buried, f"{arena_id}: obstacle at ({x}, {z}) sits inside the landmark box")


class ConsumerWiringTests(unittest.TestCase):
    def test_arena_resolves_one_config_and_reads_it(self):
        src = code(ARENA_GD)
        self.assertIn("func apply_theme() -> void:", src,
                      "apply_theme went back to taking an arena id (which is how a table miss became invisible)")
        self.assertIn("_config = _resolve_config(_resolve_arena_id())", src)
        self.assertIn("func _resolve_config(", src)
        self.assertIn("ContentRegistry != null", src, "registry must be consulted first: it is already validated")
        self.assertIn('ResourceLoader.exists(path)', src, "the disk fallback must not load() a missing path")
        self.assertIn("return load(path) as ArenaConfig", src)
        self.assertIn("_obstacles = ArenaObstacles.layout_for(_config, interior_half)", src)
        self.assertIn("ArenaLandmark.spawn(self, cfg)", src,
                      "arena.gd is not allowed to build landmark geometry itself any more")
        self.assertNotIn("config_path", read(ARENA_GD),
                         "the dead config_path export must not come back: it was read by nothing")

    def test_theme_null_is_a_real_choice(self):
        src = code(ARENA_GD)
        body = src[src.index("func apply_theme()"):].split("\nfunc ")[0]
        self.assertIn("if _config.theme != null:", body,
                      "a null theme must keep the scene look rather than applying an empty Environment")
        self.assertIn("if _config == null:", body)
        self.assertIn("_spawn_landmark(_config.landmark)", body)
        self.assertIn("_rebuild_navigation_floor()", body,
                      "swapping the centrepiece must refresh the shared nav grid")

    def test_the_dead_look_is_reported(self):
        snap = code(ARENA_GD)
        self.assertIn('"theme":', snap, "an unapplied theme has to be visible somewhere: that is the whole bug")
        self.assertIn('"landmark":', snap)
        self.assertIn('"obstacles": _obstacles.size()', snap)

    def test_landmark_builder_reads_its_config(self):
        src = code(BUILDER_GD)
        self.assertIn("func spawn(parent: Node3D, cfg: ArenaLandmarkConfig) -> ArenaLandmark:", src)
        for field in ("cfg.material_tint", "cfg.accent_color", "cfg.emissive_energy",
                      "cfg.light_color", "cfg.light_energy", "cfg.light_range", "cfg.light_offset_y",
                      "cfg.footprint_half", "cfg.rotation_degrees", "cfg.scale"):
            self.assertIn(field, src, f"the builder no longer reads {field}: it is welded into code again")
        self.assertNotIn("func _apply_theme", src)
        self.assertIn("CylinderShape3D", src)
        self.assertIn("BoxShape3D", src)


class DocsTellTheTruthTests(unittest.TestCase):
    """The docs promised "a new scene + an ArenaConfig" while three code tables disagreed.
    The promise and the exception are both pinned, so the next reader is not misled and the
    one remaining branch is not copied."""

    def test_extending_documents_the_authored_world(self):
        txt = read("docs/EXTENDING.md")
        for needle in ("ArenaThemeConfig", "ArenaLandmarkConfig", "obstacle_layout"):
            self.assertIn(needle, txt, f"docs/EXTENDING.md still does not mention {needle}")
        self.assertIn("arena_themes", txt, "the theme folder has to be findable from the guide")
        self.assertIn("arena_landmarks", txt)

    def test_architecture_owns_the_section(self):
        txt = read("docs/ARCHITECTURE.md")
        self.assertIn("The authored world", txt, "docs/ARCHITECTURE.md lost the arena-world section")
        for needle in ("footprint_half", "ArenaObstaclePlacement", "fallback_layout",
                       "Array[AABB]", "ArenaThemeConfig", "ArenaLandmarkConfig"):
            self.assertIn(needle, txt, f"docs/ARCHITECTURE.md does not explain {needle}")
        # Two claims, two rules. What the rebuild *removed* is history and stays frozen at the
        # number the pass reported; the file's *current* size is a live number and is re-derived.
        self.assertIn("shrank from 533 lines to 354", txt,
                      "the section no longer records what the rebuild deleted")
        m = re.search(r"arena\.gd`? is (\d+) lines now", txt)
        self.assertIsNotNone(m, "the section should also record how long arena.gd is today")
        self.assertEqual(int(m.group(1)), len(read(ARENA_GD).splitlines()),
                         "docs/ARCHITECTURE.md's current arena.gd size drifted from the file")
        self.assertIn("get_nav_blockers", txt,
                      "the decoration-prop nav footprints are undocumented")

    def test_handoff_stops_telling_modders_to_grep_a_table(self):
        txt = read("GODOT_HANDOFF.md")
        self.assertNotIn('ArenaObstacles.layout_for("ember_crucible"', txt,
                         "GODOT_HANDOFF still documents the deleted id table as the source of layouts")

    def test_the_new_resources_are_listed_where_content_is_listed(self):
        listed = read("docs/EXTENDING.md") + read("docs/ARCHITECTURE.md")
        for arena_id in ARENAS:
            self.assertTrue((ROOT / "data" / "arena_themes" / f"{arena_id}.tres").exists())
            self.assertIn("data/arena_themes", listed)


if __name__ == "__main__":
    unittest.main()
