"""Regression pins for the rebuilt arena-hazard subsystem.

The hazard system used to be the one place in this project where content was code: arena
layouts lived in a `match String(arena_id)` inside ArenaHazards, every live hazard was an
untyped Dictionary record, per-victim cooldowns were node metadata, and two of the four
timers ran on `Time.get_ticks_msec()` — the wall clock — while the game ran on a scaled
one.

These tests pin the *contract* of the rebuild so it cannot quietly rot back:

  * layouts and tuning numbers are authored data (.tres), never code;
  * hazard state is typed (HazardInstance), never a Dictionary record;
  * gameplay timing accumulates delta, so hitstop and pause behave;
  * node metadata carries no gameplay state;
  * every mechanic a config may name is implemented, and an unknown one is an error;
  * the per-tick work is a shared snapshot + a grid query, not N hazards x M victims.

Like the other suites here, this file reads source text: it can see what CI cannot run
without a Godot binary, and the GDScript-side behaviour tests live in
tests/unit/test_hazards.gd and tests/unit/test_hazards_live.gd.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

HAZARD_SCRIPTS = [
    "scripts/arena/arena_hazards.gd",
    "scripts/arena/hazard_config.gd",
    "scripts/arena/hazard_placement.gd",
    "scripts/arena/hazard_instance.gd",
    "scripts/arena/hazard_marker.gd",
    "scripts/arena/hazard_mode_layout.gd",
    "scripts/utilities/radius_spatial_index.gd",
]

ARENA_IDS = ("default_arena", "ember_crucible", "frost_hollow")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def code(rel: str) -> str:
    """Source with the comment lines stripped.

    Half of what makes this subsystem legible is prose that names the bad old design (it
    explains WHY a guard exists), so a "must not contain" assertion has to look at code
    only. Positive pins still read the whole file.
    """
    out = []
    for line in read(rel).splitlines():
        if line.lstrip().startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def hazard_source() -> str:
    return read("scripts/arena/arena_hazards.gd")


class LayoutsAreDataTests(unittest.TestCase):
    def test_hazard_system_names_no_arena(self):
        """The point of the rebuild: the hazard system is arena-agnostic."""
        text = hazard_source()
        for arena_id in ARENA_IDS:
            self.assertNotIn(arena_id, text,
                             f"hazard code must not branch on the arena id {arena_id}")
        self.assertNotIn("match String(arena_id)", text, "per-arena match arms must stay gone")
        self.assertNotIn("_layout_defaults", text, "the hardcoded layout function must stay gone")
        self.assertNotIn("layout_for(arena_id", text)

    def test_arenas_carry_their_own_hazard_layout(self):
        """Every shipped arena authors its layout, with its hazards as hard references."""
        for arena_id in ARENA_IDS:
            text = read(f"data/arenas/{arena_id}.tres")
            match = re.search(r"hazard_layout = Array\[HazardPlacement\]\(\[(.*?)\]\)", text, re.S)
            self.assertIsNotNone(match, f"{arena_id}.tres must author a hazard_layout")
            refs = re.findall(r'SubResource\("([^"]+)"\)', match.group(1))
            self.assertGreaterEqual(len(refs), 5,
                                    f"{arena_id}: expected >=5 authored placements, got {len(refs)}")
            for rid in refs:
                self.assertIn(f'[sub_resource type="Resource" id="{rid}"]', text,
                              f"{arena_id}: placement {rid} is referenced but not defined")
            configs = re.findall(r'config = ExtResource\("([^"]+)"\)', text)
            self.assertTrue(configs, f"{arena_id}: placements must reference a HazardConfig")
            for cid in set(configs):
                self.assertIn(f'path="res://data/hazards/', text,
                              f"{arena_id}: placement config {cid} is not a data/hazards file")

    def test_placement_expansion_keeps_the_shipped_hazard_counts(self):
        """Mirror expansion is the only reason the .tres files are shorter than the old
        hand-listed layouts: 6/5/6 authored placements still build 11/9/10 hazards.

        The mirrors are read from the placement blocks the hazard_layout line actually
        references, not from the whole file. The first version of this check scanned every
        `mirror = &"…"` line in the arena and so started counting a hazard for every *obstacle*
        the moment `ArenaConfig.obstacle_layout` moved into the same file (it read 17 for an
        11-hazard arena). A data test that cannot tell one authored layout from another is not
        a guard: scope it to the reference list.
        """
        expected = {"default_arena": 11, "ember_crucible": 9, "frost_hollow": 10}
        expansion = {"none": 1, "x": 2, "z": 2, "rot180": 2, "both": 4}
        for arena_id, wanted in expected.items():
            text = read(f"data/arenas/{arena_id}.tres")
            refs = re.search(r"hazard_layout = Array\[HazardPlacement\]\(\[(.*?)\]\)", text, re.S)
            self.assertIsNotNone(refs, f"{arena_id}.tres must author a hazard_layout")
            total = 0
            for rid in re.findall(r'SubResource\("([^"]+)"\)', refs.group(1)):
                block = re.search(
                    r'\[sub_resource type="Resource" id="%s"\]\n(.*?)(?=\n\[|\Z)' % re.escape(rid),
                    text, re.S)
                self.assertIsNotNone(block, f"{arena_id}: hazard placement {rid} is referenced but undefined")
                mirror = re.search(r'mirror = &"(\w+)"', block.group(1))
                total += expansion[mirror.group(1) if mirror else "none"]
            self.assertEqual(total, wanted,
                             f"{arena_id}: placements expand to {total} hazards, expected {wanted}")

    def test_mode_pressure_is_data_too(self):
        body = hazard_source()
        start = body.index("func apply_mode_pressure")
        block = body[start:]
        block = block[:block.index("\nfunc ")]
        self.assertNotIn("GameMode.MODE_", block,
                         "a mode's hazard pressure must come from its HazardModeLayout file")
        self.assertNotIn("Vector3(", block, "mode pressure must not hand-place hazards in code")
        self.assertIn("_mode_layout(mode_id)", block)

    def test_every_mode_that_adds_pressure_has_a_file(self):
        authored = {p.stem for p in (ROOT / "data/hazard_modes").glob("*.tres")}
        self.assertEqual(authored, {"boss_rush", "challenge", "survival", "campaign"},
                         "modes with no pressure file are the other four; see docs")
        for mode_id in sorted(authored):
            text = read(f"data/hazard_modes/{mode_id}.tres")
            self.assertIn(f'mode_id = &"{mode_id}"', text,
                          f"{mode_id}.tres must key itself by its file name (the loader indexes by mode_id)")
            self.assertIn("extra_placements = Array[HazardPlacement]([", text)


class TypedRecordsTests(unittest.TestCase):
    def test_no_untyped_hazard_records(self):
        text = hazard_source()
        self.assertIn("var _instances: Array[HazardInstance] = []", text)
        self.assertNotIn("var _hazards", text, "the Dictionary-record list must stay gone")
        for rel in HAZARD_SCRIPTS:
            src = read(rel)
            self.assertNotIn('["kind"]', src, f"{rel} still reads a Dictionary record")
            self.assertNotIn('h["', src, f"{rel} still indexes a hazard by string key")
            self.assertNotIn("h.get(", src, f"{rel} still reads optional record keys")

    def test_no_node_metadata_carries_gameplay_state(self):
        """set_meta/get_meta are scene annotations, and they were measurably slow."""
        for rel in HAZARD_SCRIPTS:
            src = code(rel)
            for needle in ("set_meta(", "get_meta(", "has_meta(", "remove_meta("):
                self.assertNotIn(needle, src, f"{rel} must not use node metadata ({needle})")

    def test_every_mechanic_is_implemented(self):
        """The failure mode this closes: a config names a mechanic nothing handles, the
        match arm falls through, and the hazard silently does nothing forever."""
        config = read("scripts/arena/hazard_config.gd")
        declared = set(value.lower() for _name, value in re.findall(r'const MECHANIC_([A-Z_]+) := &"([a-z_]+)"', config))
        self.assertEqual(declared, {"pulse", "field"},
                         "the mechanic vocabulary is two mechanics; a third needs a design conversation")
        listed = re.search(r"const VALID_MECHANICS := \[(.*?)\]", config, re.S)
        self.assertIsNotNone(listed, "VALID_MECHANICS must list every mechanic")
        values = re.findall(r"MECHANIC_([A-Z_]+)", listed.group(1))
        self.assertEqual(sorted(v.lower() for v in values), ["field", "pulse"])
        text = hazard_source()
        for name in values:
            self.assertIn(f"HazardConfig.MECHANIC_{name.upper()}:", text,
                          f"mechanic {name} is authored-legal but has no branch in the tick")
        # And the fall-through is loud, not silent.
        arms = text[text.index("match instance.config.mechanic:"):]
        self.assertIn("push_error", arms[:900], "an unknown mechanic must be reported at runtime")

    def test_hazard_validation_covers_the_authoring_traps(self):
        """Each rule below is a mistake a .tres can make that would otherwise only show up
        as a hazard that does nothing, hurts invisibly, or never stops hurting."""
        config = read("scripts/arena/hazard_config.gd")
        body = config[config.index("func validate()"):]
        for needle, why in (
            ("hazard_id is empty", "the loader keys the table by hazard_id"),
            ("not in VALID_MECHANICS", "an unhandled mechanic must fail at load, not at runtime"),
            ("not in VALID_TRIGGERS", "a typo'd trigger would leave a pulse unarmed forever"),
            ("telegraph must be in [0, period)", "a telegraph longer than the period never bursts"),
            ("fire_cooldown > 0", "a proximity pulse with no re-arm detonates every tick"),
            ("can never affect anything", "a hazard that targets nobody is dead data"),
            ("beneficial hazard must not deal damage", "a ward that also hurts is mis-authored"),
            ("is fully transparent", "an invisible disc still damages, which is not fair"),
            ("must be finite", "a NaN number reaches a tick loop and then every body nearby"),
            ("trigger_radius must not exceed radius", "a victim would be hit before being detected"),
            ("status_stacks must be >= 1", "zero stacks applies nothing"),
        ):
            self.assertIn(needle, body, why)

    def test_config_is_editor_friendly_and_self_checking(self):
        config = read("scripts/arena/hazard_config.gd")
        self.assertIn("extends ValidatedConfig", config,
                      "a hazard config that does not extend ValidatedConfig is never validated at load")
        self.assertIn("func validate() -> Array[String]:", config)
        self.assertGreaterEqual(config.count("@export_range"), 12,
                                "authored gameplay numbers need inspector bounds, per the guard contract")
        placement = read("scripts/arena/hazard_placement.gd")
        self.assertIn("func validate() -> Array[String]:", placement)
        self.assertIn("func duplicate_entry() -> HazardPlacement:", placement,
                      "nested entry resources follow WaveSpawnEntry's shape")


class ClockTests(unittest.TestCase):
    def test_no_wall_clock_in_hazard_gameplay(self):
        for rel in HAZARD_SCRIPTS:
            src = code(rel)
            for needle in ("Time.get_ticks_msec()", "Time.get_ticks_usec()", "Engine.get_physics_frames()"):
                self.assertNotIn(needle, src, f"{rel} must not drive gameplay from a wall/raw clock")

    def test_hazard_time_accumulates_delta(self):
        text = hazard_source()
        self.assertIn("\t_game_time += delta", text)
        self.assertIn("instance.advance(delta)", text)
        instance = read("scripts/arena/hazard_instance.gd")
        self.assertIn("func advance(delta: float) -> void:", instance)
        self.assertIn("\tscan_timer += delta", instance)
        # Cooldown stamps are measured on the same clock the world is scaled on.
        self.assertIn("instance.victim_ready(key, _game_time)", text)
        self.assertIn("instance.stamp_victim(key, _game_time)", text)

    def test_heal_is_integrated_not_per_frame(self):
        text = hazard_source()
        self.assertIn("var amount := instance.config.heal_per_second * covered", text)
        self.assertIn("func begin_scan() -> float:", read("scripts/arena/hazard_instance.gd"))


class HotPathTests(unittest.TestCase):
    def test_one_snapshot_shared_by_every_hazard(self):
        text = hazard_source()
        body = text[text.index("func _physics_process"):text.index("func _tick_pulse")]
        self.assertEqual(body.count("_gather_victims()"), 0,
                         "the tick must not gather directly; it goes through _require_victims()")
        self.assertIn("\t_snapshot_ready = false", body)
        gate = text[text.index("func _require_victims"):text.index("func _gather_victims")]
        self.assertIn("if not _snapshot_ready:", gate,
                      "one snapshot per tick, however many hazards want victims")
        self.assertIn("return _victims_this_tick > 0", gate)
        # The identifier the gate returns has to be a member of the file, not a name the reader
        # assumes: an undeclared one is a parse error, and the arena's hazard layer is what breaks.
        self.assertIn("var _victims_this_tick: int = 0", text,
                      "the gate returns an identifier the file never declares")
        # Nobody in the arena => no snapshot work at all, and no hazard may gather first.
        self.assertEqual(text.count("if not _require_victims():"), 3,
                         "exactly the three victim-hungry paths may ask for a snapshot")
        gather = text[text.index("func _gather_victims"):text.index("func _add_victim")]
        self.assertNotIn(".filter(", gather, "no per-tick lambda filter over the victim list")
        self.assertNotIn("append_array", gather, "no per-tick Array reallocation")

    def test_hazards_query_the_grid_instead_of_scanning_the_arena(self):
        text = hazard_source()
        for func in ("_trigger_pressed", "_tick_field", "_detonate"):
            block = text[text.index(f"func {func}("):]
            block = block[:block.index("\n\n\n")] if "\n\n\n" in block else block
            self.assertIn("_index.query(", block, f"{func} must query the spatial index")
        self.assertNotIn("_hazards.find(", text,
                         "O(n) record lookups per victim must stay gone")
        # Every AoE call must be fed the small candidate list. Asserting on the shape of
        # one call is not enough: the day one of them goes back to handing AreaDamage the
        # whole victim array, that hazard is O(arena) again.
        fed = re.findall(r"AreaDamage\.apply_radial\(\s*\n?\s*(\w+)", text)
        self.assertTrue(fed, "hazards should route damage through AreaDamage")
        self.assertEqual(sorted(set(fed)), ["_candidate_scratch"],
                         f"an AoE call is fed {sorted(set(fed))} instead of the queried candidates")
        scan_side = text[text.index("func _tick_field"):text.index("func _gather_victims")]
        self.assertNotIn('is_in_group("enemies")', scan_side,
                         "no hazard may re-scan the enemies group; the snapshot already did")

    def test_status_no_longer_rescans_for_the_stamp(self):
        text = hazard_source()
        stamp = text[text.index("func _stamp_status"):]
        stamp = stamp[:stamp.index("\n\n\n")]
        self.assertIn("for victim in victims:", stamp,
                      "the stamp must iterate the candidates the burst already found")
        self.assertNotIn("_inside(", stamp)
        self.assertNotIn("get_node_or_null(", stamp,
                         "components come from the typed Damageable seam, not a node path")

    def test_scan_cadence_is_authored(self):
        config = read("scripts/arena/hazard_config.gd")
        self.assertIn("var scan_interval", config)
        instance = read("scripts/arena/hazard_instance.gd")
        self.assertIn("func scan_due() -> bool:", instance)
        self.assertIn("if not instance.scan_due():", hazard_source())

    def test_index_is_a_rebuilt_grid_with_no_per_tick_allocation(self):
        """The index earns its keep only if a rebuild writes ints into arrays that already
        exist. A Dictionary of per-cell Arrays, or a resize per insert, would put the
        allocation cost back into the tick loop."""
        text = code("scripts/utilities/radius_spatial_index.gd")
        self.assertIn("_heads: PackedInt32Array", text)
        self.assertIn("_next: PackedInt32Array", text)
        self.assertNotIn("append(", text, "buckets are indexed slots, not per-cell arrays")
        field_block = text[:text.index("func setup")]
        self.assertNotIn("Dictionary", field_block, "the buckets must not be a hash of lists")
        self.assertNotIn("Array[", field_block, "no per-cell container, only packed arrays")
        setup = text[text.index("func setup"):text.index("func begin_update")]
        self.assertIn("_heads.resize(cells)", setup)
        self.assertIn("_heads.fill(-1)", setup)
        begin = text[text.index("func begin_update"):text.index("func insert")]
        self.assertIn("_heads.fill(-1)", begin,
                      "a rebuild must refill heads in place, never reallocate the buckets")
        # The store is allocated in setup() and reused; if any other method reassigns it,
        # the zero-allocation rebuild is gone. Only setup() is excluded — a rebuild that
        # swaps the array out (the usual "just make it a dict of lists" retreat) is exactly
        # what this catches.
        self.assertNotIn("_heads =", text.replace(setup, ""))
        insert = text[text.index("func insert"):text.index("func query")]
        self.assertNotIn("resize(", insert, "insert must not grow arrays per element")
        self.assertIn("overflow_count += 1", insert,
                      "a full index must report the drop rather than lose a victim silently")


class SeamsTests(unittest.TestCase):
    def test_content_loader_registers_the_hazard_tables(self):
        loader = read("scripts/core/content_loader.gd")
        self.assertIn('_load_typed(&"res://data/hazards", &"hazards", tables, errors)', loader)
        self.assertIn('_load_typed(&"res://data/hazard_modes", &"hazard_modes", tables, errors)', loader)
        # Modes live in a sibling directory because the loader scans recursively: nesting
        # them under data/hazards would load every HazardModeLayout as a HazardConfig.
        self.assertFalse((ROOT / "data/hazards/modes").exists(),
                         "data/hazards must contain only HazardConfig files")
        self.assertIn("Not a HazardConfig", loader)
        self.assertIn("hazard %s references unknown status", loader)
        self.assertIn("no HazardConfig resources under res://data/hazards", loader,
                      "an empty hazard table must be a load error, not a quiet arena")

    def test_registry_exposes_hazard_lookups(self):
        registry = read("scripts/core/content_registry.gd")
        for needle in ("func get_hazard(hazard_id: StringName) -> HazardConfig:",
                       "func get_hazard_mode_layout(mode_id: StringName) -> HazardModeLayout:",
                       "_hazards = tables[&\"hazards\"]", "_hazard_modes = tables[&\"hazard_modes\"]"):
            self.assertIn(needle, registry)

    def test_every_hazard_config_file_is_keyed_by_its_own_id(self):
        for path in sorted((ROOT / "data/hazards").glob("*.tres")):
            text = path.read_text(encoding="utf-8")
            self.assertIn(f'hazard_id = &"{path.stem}"', text,
                          f"{path.name}: the loader keys by hazard_id, so the file name must match")

    def test_hazards_use_the_damageable_seams(self):
        """The subsystem resolves status/health components through typed virtuals instead
        of get_node_or_null("StatusManager") on the hot path."""
        text = hazard_source()
        self.assertIn("damageable.get_status_manager()", text)
        self.assertIn("damageable.get_health_component()", text)
        self.assertNotIn('get_node_or_null("StatusManager")', text)
        self.assertNotIn('get_node_or_null("HealthComponent")', text)
        damageable = read("scripts/combat/damageable.gd")
        for needle in ("func get_status_manager() -> StatusManager:",
                       "func get_health_component() -> HealthComponent:",
                       "func get_hit_radius() -> float:"):
            self.assertIn(needle, damageable, "the seam has to exist on the protocol, not the caller")
        area = read("scripts/combat/area_damage.gd")
        self.assertIn("damageable.get_hit_radius()", area,
                      "AreaDamage and the hazard query must pad bodies identically")

    def test_debug_surface_reports_the_new_work(self):
        text = hazard_source()
        for key in ("victims_last_tick", "queries_last_tick", '"index": _index.debug_snapshot()'):
            self.assertIn(key, text)
        snapshot = read("scripts/utilities/radius_spatial_index.gd")
        for key in ("visited", "queries", "overflow"):
            self.assertIn(key, snapshot)


class HarnessRegistrationTests(unittest.TestCase):
    def test_both_godot_suites_are_registered(self):
        text = read("tests/run_tests.gd")
        self.assertIn('"res://tests/unit/test_hazards.gd"', text)
        self.assertIn('"res://tests/unit/test_hazards_live.gd"', text)
        unit = text[text.index("const UNIT_SUITES"):text.index("const NODE_SUITES")]
        node = text[text.index("const NODE_SUITES"):text.index("const INTEGRATION_STAGES")]
        self.assertIn("test_hazards.gd", unit, "the pure suite must run in the synchronous phase")
        self.assertIn("test_hazards_live.gd", node,
                      "the fixture suite must run deferred, when global_position is real")

    def test_the_runner_stays_free_of_game_classes(self):
        text = read("tests/run_tests.gd")
        self.assertNotIn("ArenaHazards", text)
        self.assertNotIn("HazardConfig", text)

    def test_hazard_layouts_stay_clear_of_obstacles(self):
        """The obstacle layout used to be hand-tuned against a function in the hazard
        system. Both sides must now be checkable from the arena data (test_nav_grid.gd),
        so pin that the nav-grid suite reads the .tres rather than a copied list."""
        text = read("tests/unit/test_nav_grid.gd")
        self.assertIn("_hazard_centers(", text)
        self.assertIn("res://data/arenas/", text)
        self.assertNotIn("mirrored from ArenaHazards", text,
                        "a hand-copied mirror of the layout drifts and stops testing anything")


class ValidationReachabilityTests(unittest.TestCase):
    """ContentLoader validates a config only when it *is* a ValidatedConfig, which is why
    ArenaConfig now extends it: authored layouts are worthless if nothing checks them."""

    def test_arena_config_is_validated_at_load(self):
        self.assertIn("extends ValidatedConfig", read("scripts/arena/arena_config.gd"))
        loader = read("scripts/core/content_loader.gd")
        self.assertIn("var cfg := res as ValidatedConfig", loader)
        self.assertIn("for problem in cfg.validate():", loader)
        self.assertIn('tables[&"arenas"], StringName(arena.arena_id)', loader.replace(" ", " ").replace("\t", " "))

    def test_unvalidated_config_types_are_a_known_list_not_a_growing_one(self):
        """Four config types still extend Resource, so their validate() only runs in the CI
        harness — never at load. That is a known gap, deliberately listed: entries may only
        be removed after the shipped .tres files for that table are proven to pass, because
        ContentRegistry HALTS startup on a validation error. A new config type with a
        validate() must either join ValidatedConfig or appear here.

        StatusEffectConfig left this list in the status rebuild: no Godot binary exists in CI,
        so the proof was built differently — tests/python/test_regress_status_hot_path.py
        mirrors its validate() rules in python and audits every data/status/*.tres with the
        class's own defaults. ArenaConfig had no such mirror when it converted, because a
        hazard layout is only reachable through a scene that a run would exercise anyway."""
        offenders = set()
        for path in sorted((ROOT / "scripts").rglob("*_config.gd")):
            text = path.read_text(encoding="utf-8")
            if "func validate()" not in text:
                continue
            if "extends ValidatedConfig" in text:
                continue
            offenders.add(str(path.relative_to(ROOT)))
        offenders.discard("scripts/core/validated_config.gd")  # the base class itself
        # A SUBSET check on purpose: converting one of these to ValidatedConfig is progress
        # and must not break this test; adding one is the regression it guards.
        self.assertLessEqual(offenders, {
            "scripts/audio/audio_config.gd",
            "scripts/enemies/boss_phase_config.gd",
            "scripts/skills/skill_config.gd",
            "scripts/weapons/weapon_config.gd",
        }, "a new config type with validate() must extend ValidatedConfig (or be added here, "
           "with the shipped .tres files proven to pass in a real run)")


if __name__ == "__main__":
    unittest.main()
