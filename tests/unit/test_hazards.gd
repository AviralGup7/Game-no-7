extends RefCounted

## Headless unit tests for the rebuilt hazard subsystem: authored data (HazardConfig /
## HazardPlacement / HazardModeLayout), per-placement state (HazardInstance) and the
## spatial index that replaces the per-hazard full-arena scan.
##
## Pure phase: no scene tree, no physics. The tests that need live victims (damage,
## throttling, heal integration, markers) are in test_hazards_live.gd.
##
## The layout checks here are the pin that makes the data migration honest: the expected
## positions are the set the old `match String(arena_id)` block produced, so if anybody
## re-authors an arena layout by hand and breaks its symmetry, this fails.

static func suite() -> Array:
	var results: Array = []
	_validate_rejects_misauthored(results)
	_authored_data_is_valid(results)
	_arena_layouts_match_legacy_positions(results)
	_mode_layouts_are_data(results)
	_mirror_math(results)
	_geometry_single_source(results)
	_cooldown_runs_on_game_time(results)
	_burst_clock(results)
	_orbit_stays_inside_the_arena(results)
	_index_matches_bruteforce(results)
	_index_reports_its_own_work(results)
	_snapshots(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _vent() -> HazardConfig:
	return HazardConfig.resolve(&"fire_vent")


static func _plate() -> HazardConfig:
	return HazardConfig.resolve(&"pressure_plate")


static func _mover() -> HazardConfig:
	return HazardConfig.resolve(&"ember_mover")


# ---------------------------------------------------------------- authoring


static func _validate_rejects_misauthored(results: Array) -> void:
	var bare := HazardConfig.new()
	var base := HazardConfig.new()
	base.hazard_id = &"probe"
	base.mechanic = HazardConfig.MECHANIC_PULSE
	base.period = 4.0
	base.telegraph = 1.0
	base.radius = 2.0
	base.affects_enemies = true
	# Positive control first: if the template itself did not validate, every rejection
	# below would pass for the wrong reason.
	_check(results, "a minimal well-formed pulse hazard validates clean", base.validate().is_empty(),
		str(base.validate()))
	# The bug class this whole type exists to close: a config that loads, validates and
	# then does NOTHING because the system has no branch for it.
	_check(results, "a hazard with no id is refused", not bare.validate().is_empty()
		and String(bare.validate()[0]).contains("hazard_id"))
	var bad_mechanic := base.duplicate() as HazardConfig
	bad_mechanic.hazard_id = &"probe"
	bad_mechanic.mechanic = &"lava_geyser"
	_check(results, "an unknown mechanic is an authoring error, not a silent no-op",
		_bad(bad_mechanic, "mechanic"))
	var bad_trigger := base.duplicate() as HazardConfig
	bad_trigger.hazard_id = &"probe"
	bad_trigger.trigger = &"when_i_feel_like_it"
	_check(results, "an unknown trigger is refused", _bad(bad_trigger, "trigger"))
	var always_on := base.duplicate() as HazardConfig
	always_on.hazard_id = &"probe"
	always_on.trigger = HazardConfig.TRIGGER_PROXIMITY
	always_on.fire_cooldown = 0.0
	_check(results, "a proximity pulse without a re-arm would detonate every tick", _bad(always_on, "fire_cooldown"))
	var infinite_warning := base.duplicate() as HazardConfig
	infinite_warning.hazard_id = &"probe"
	infinite_warning.telegraph = 9.0
	_check(results, "telegraph must end before the burst", _bad(infinite_warning, "telegraph"))
	var nobody := base.duplicate() as HazardConfig
	nobody.hazard_id = &"probe"
	nobody.affects_enemies = false
	# Both halves: a hazard that reaches enemies only is legal, and the rule is about reaching nothing.
	nobody.affects_player = false
	_check(results, "a hazard that targets nobody is refused", _bad(nobody, "can never affect anything"))
	var kind_but_hurts := base.duplicate() as HazardConfig
	kind_but_hurts.hazard_id = &"probe"
	kind_but_hurts.is_beneficial = true
	kind_but_hurts.damage = 12.0
	_check(results, "a beneficial hazard may not also deal damage", _bad(kind_but_hurts, "beneficial"))
	var invisible := base.duplicate() as HazardConfig
	invisible.hazard_id = &"probe"
	invisible.marker_color = Color(1, 0, 0, 0.0)
	_check(results, "a fully transparent marker on a live hazard is refused", _bad(invisible, "transparent"))
	var padded := base.duplicate() as HazardConfig
	padded.hazard_id = &"probe"
	padded.radius = 2.0
	padded.trigger_radius = 5.0
	_check(results, "a trigger wider than the effect is refused", _bad(padded, "trigger_radius"))
	var nan_period := base.duplicate() as HazardConfig
	nan_period.hazard_id = &"probe"
	nan_period.period = NAN
	_check(results, "a non-finite period cannot reach a tick loop", _bad(nan_period, "finite"))


static func _bad(config: HazardConfig, needle: String) -> bool:
	var problems := config.validate()
	if problems.is_empty():
		return false
	for problem in problems:
		if String(problem).contains(needle):
			return true
	return false


static func _authored_data_is_valid(results: Array) -> void:
	var ids: Array[StringName] = [&"fire_vent", &"pressure_plate", &"spike_bed", &"heal_ward", &"ichor_pool", &"ember_mover"]
	var all_ok := true
	var mechanics := {}
	var first_problem := ""
	for id in ids:
		var config := HazardConfig.resolve(id)
		if config == null:
			all_ok = false
			first_problem = "%s missing" % String(id)
			continue
		var problems := config.validate()
		if not problems.is_empty():
			all_ok = false
			first_problem = "%s: %s" % [String(id), problems[0]]
		mechanics[config.mechanic] = true
	_check(results, "all six authored hazards load and validate", all_ok, first_problem)
	_check(results, "six hazards are driven by two mechanics", mechanics.size() == 2,
		"got %d mechanics" % mechanics.size())
	# Slow-in-a-pool used to be a bare 2.8 in two places, and the plate blast a +1.5 in the
	# tick. Both must now be fields, so the visual and the hitbox cannot drift apart.
	var pool := HazardConfig.resolve(&"ichor_pool")
	var plate := _plate()
	var pool_ok := pool != null and pool.radius > 2.0 and pool.radius < 4.0
	_check(results, "the pool's gameplay radius is authored, not hardcoded in a tick",
		pool_ok, "radius=%s" % (str(pool.radius) if pool != null else "missing"))
	var plate_ok := plate != null and plate.radius > plate.trigger_radius and plate.contact_radius() < plate.radius
	_check(results, "a plate's tread and its blast are two separate numbers", plate_ok,
		"blast=%s tread=%s" % [str(plate.radius), str(plate.contact_radius())] if plate != null else "missing")
	# The pool throttles its status stamp; the loader rule is that the status must outlive
	# the throttle, so check the pair here (the registry is not loaded in this phase).
	var slow: StatusEffectConfig = null
	if ResourceLoader.exists("res://data/status/slow.tres"):
		slow = load("res://data/status/slow.tres") as StatusEffectConfig
	var throttle_ok := pool != null and slow != null and (pool.victim_cooldown <= 0.0 or slow.duration > pool.victim_cooldown)
	_check(results, "a throttled field re-stamps before its status lapses", throttle_ok,
		"cooldown=%s duration=%s" % [str(pool.victim_cooldown), str(slow.duration)] if pool != null and slow != null else "missing")


## The exact hazard positions the deleted `_layout_defaults()` produced, per arena.
static func _arena_layouts_match_legacy_positions(results: Array) -> void:
	var legacy := {
		"default_arena": [
			"6_0", "-6_0", "0_6", "0_-6", "4_4", "-4_-4", "3_-3", "-3_3", "0_0", "0_-6", "0_6",
		],
		"ember_crucible": [
			"5_5", "-5_-5", "-5_5", "5_-5", "0_7", "0_-7", "0_0", "6_0", "7_7",
		],
		"frost_hollow": [
			"4_0", "-4_0", "0_5", "0_-5", "6_6", "-6_-6", "0_4", "0_-4", "0_0", "0_7",
		],
	}
	for id in legacy.keys():
		var arena: ArenaConfig = null
		if ResourceLoader.exists("res://data/arenas/%s.tres" % id):
			arena = load("res://data/arenas/%s.tres" % id) as ArenaConfig
		if arena == null:
			_check(results, "%s: arena config with a hazard layout loads" % id, false, "could not load")
			continue
		var found: Array = []
		var problems: Array = []
		for placement in arena.hazard_layout:
			if placement == null:
				problems.append("null placement")
				continue
			problems.append_array(placement.validate())
			for at in placement.mirrored_positions():
				found.append("%d_%d" % [int(round(at.x)), int(round(at.z))])
		found.sort()
		var expected: Array = legacy[id].duplicate()
		expected.sort()
		_check(results, "%s: layout data reproduces the hand-tuned hazard set" % id,
			found == expected and problems.is_empty(),
			"found %s want %s %s" % [str(found), str(expected), str(problems)])
	# The mechanical guarantee lives in tests/python/test_regress_hazard_subsystem.py
	# ("no arena id may appear in the hazard system"). Here we only assert the fallback the
	# other half of that claim depends on: an arena with no authored layout still gets the
	# four compass vents, exactly like ArenaObstacles' safe default.
	_check(results, "an unauthored arena falls back to four compass vents",
		ArenaHazards.fallback_layout_positions(12.0).size() == 4)


static func _mode_layouts_are_data(results: Array) -> void:
	var checked := 0
	var ok := true
	for mode_id in ["boss_rush", "challenge", "survival", "campaign"]:
		var path := "res://data/hazard_modes/%s.tres" % mode_id
		if not ResourceLoader.exists(path):
			ok = false
			continue
		var layout := load(path) as HazardModeLayout
		if layout == null or String(layout.mode_id) != mode_id or not layout.validate().is_empty():
			ok = false
			continue
		checked += layout.extra_placements.size()
	_check(results, "the four modes that add pressure do it with typed placements", ok and checked == 7,
			"placements=%d ok=%s" % [checked, str(ok)])


# ---------------------------------------------------------------- placements


static func _mirror_math(results: Array) -> void:
	var placement := HazardPlacement.new()
	placement.config = _vent()
	placement.position = Vector3(3, 0.05, 4)
	placement.mirror = HazardPlacement.MIRROR_NONE
	_check(results, "mirror none is one hazard", placement.mirrored_positions().size() == 1)
	placement.mirror = HazardPlacement.MIRROR_X
	_check(results, "mirror x negates x only", _has(placement.mirrored_positions(), -3.0, 4.0))
	placement.mirror = HazardPlacement.MIRROR_Z
	_check(results, "mirror z negates z only", _has(placement.mirrored_positions(), 3.0, -4.0))
	placement.mirror = HazardPlacement.MIRROR_ROT180
	_check(results, "rot180 gives a point-symmetric pair",
		placement.mirrored_positions().size() == 2 and _has(placement.mirrored_positions(), -3.0, -4.0))
	placement.mirror = HazardPlacement.MIRROR_BOTH
	_check(results, "both fills four quadrants", placement.mirrored_positions().size() == 4)
	placement.mirror = &"octagonal"
	_check(results, "an unknown mirror is refused at validate()", not placement.validate().is_empty())
	placement.mirror = HazardPlacement.MIRROR_NONE
	var no_config := HazardPlacement.new()
	no_config.position = Vector3.ONE
	_check(results, "a placement without a config is refused", not no_config.validate().is_empty())
	var copy := placement.duplicate_entry()
	_check(results, "duplicate_entry copies every field",
		copy.config == placement.config and copy.position == placement.position and copy.mirror == placement.mirror
			and copy.radius_override == placement.radius_override and copy.phase_jitter == placement.phase_jitter)


static func _has(positions: Array[Vector3], x: float, z: float) -> bool:
	for at in positions:
		if is_equal_approx(at.x, x) and is_equal_approx(at.z, z):
			return true
	return false


static func _geometry_single_source(results: Array) -> void:
	var vent := _vent()
	var instance := HazardInstance.build(vent, 0, Vector3(2, 0.05, 2), vent.radius, vent.period)
	_check(results, "radius and radius-squared agree", is_equal_approx(instance.radius_squared, vent.radius * vent.radius))
	_check(results, "covers() is a squared-distance test at the authored radius",
		instance.covers(instance.position + Vector3(vent.radius * 0.5, 0, 0), 0.0)
			and not instance.covers(instance.position + Vector3(vent.radius * 1.5, 0, 0), 0.0))
	# Victim bodies are padded, exactly as AreaDamage pads them; a hazard must never hit
	# someone its own query refused to report.
	_check(results, "a padded body at the rim is still covered",
		instance.covers(instance.position + Vector3(vent.radius + 0.4, 0, 0), 0.4)
			and not instance.covers(instance.position + Vector3(vent.radius + 0.9, 0, 0), 0.4))
	var shrunk := HazardInstance.build(vent, 1, Vector3.ZERO, 1.0, vent.period)
	_check(results, "a placement radius override moves the detection circle with it",
		shrunk.contact_radius > 0.0 and shrunk.contact_radius <= 1.0, "contact=%s" % str(shrunk.contact_radius))
	var plate := _plate()
	var plate_instance := HazardInstance.build(plate, 2, Vector3.ZERO, plate.radius, plate.period)
	_check(results, "a tread smaller than the blast is honoured",
		is_equal_approx(plate_instance.contact_radius, plate.trigger_radius)
			and is_equal_approx(plate_instance.radius, plate.radius))
	# A non-finite centre used to push NaN knockback into every body in range.
	var broken := HazardInstance.build(vent, 3, Vector3.ZERO, vent.radius, vent.period)
	broken.position = Vector3(NAN, 0.0, 0.0)
	_check(results, "a broken epicentre is detected before it can spread", not broken.position_is_sane())


static func _cooldown_runs_on_game_time(results: Array) -> void:
	var spikes := HazardConfig.resolve(&"spike_bed")
	var instance := HazardInstance.build(spikes, 0, Vector3.ZERO, spikes.radius, 0.0)
	instance.stamp_victim(42, 10.0)
	_check(results, "a stepped-on victim is on cooldown", not instance.victim_ready(42, 10.5))
	_check(results, "the cooldown expires in GAME seconds, not wall seconds",
		instance.victim_ready(42, 10.0 + spikes.victim_cooldown))
	_check(results, "a victim nobody has touched is ready", instance.victim_ready(7, 10.0))
	# Hitstop used to eat the cooldown: Engine.time_scale 0.05 means 50 ms of real time is
	# 2.5 ms of game time, so a wall-clock cooldown expired during the freeze.
	var accumulated := 0.0
	while accumulated < spikes.victim_cooldown - 0.0001:
		accumulated += 0.05
	_check(results, "one second of accumulated delta is one second of immunity",
		is_equal_approx(accumulated, spikes.victim_cooldown), "accumulated=%s" % str(accumulated))
	for i in range(200):
		instance.stamp_victim(1000 + i, 0.0)
	# After the last stamp's own next-sweep time (`stamp_victim(42, 10.0)` scheduled one at 11.0):
	# game time only moves forward, and the sweep is throttled to once per second, so pruning at 5.0
	# here would be the throttle doing its job rather than the sweep failing to run.
	instance.prune(12.0)
	_check(results, "expired cooldowns are swept so a long run does not leak entries",
		instance.debug_snapshot()["throttled"] == 0, str(instance.debug_snapshot()["throttled"]))


static func _burst_clock(results: Array) -> void:
	var vent := _vent()
	var instance := HazardInstance.build(vent, 0, Vector3.ZERO, vent.radius, vent.period)
	instance.timer = 0.0
	_check(results, "no telegraph at the start of a cycle", is_equal_approx(instance.telegraph_level(), 0.0))
	instance.timer = vent.period - vent.telegraph * 0.5
	_check(results, "the telegraph ramps over its own window",
		instance.telegraph_level() > 0.4 and instance.telegraph_level() < 0.6, str(instance.telegraph_level()))
	instance.timer = vent.period - 0.001
	_check(results, "a burst is not due before the period elapses", not instance.burst_due())
	instance.timer = vent.period
	_check(results, "a burst is due at the period, and the clock resets",
		instance.burst_due() and is_equal_approx(instance.timer, 0.0))
	var idle := HazardInstance.build(vent, 1, Vector3.ZERO, vent.radius, vent.period)
	for _i in 200:
		idle.advance(0.05)
	_check(results, "a hazard that never gets a victim does not let its clock run away",
		idle.timer <= vent.period + 0.0001, "timer=%s" % str(idle.timer))
	var field := HazardInstance.build(HazardConfig.resolve(&"heal_ward"), 2, Vector3.ZERO, 2.5, 0.0)
	field.advance(0.05)
	field.advance(0.05)
	_check(results, "a field integrates the time it actually covered",
		is_equal_approx(field.begin_scan(), 0.1), "covered=%s" % str(field.scanned_delta))


static func _orbit_stays_inside_the_arena(results: Array) -> void:
	var mover := _mover()
	# Authored at the arena centre: the circle can use the full authored reach.
	var center := HazardInstance.build(mover, 0, Vector3.ZERO, mover.radius, 0.0)
	var radius := center.orbit_radius(12.0)
	_check(results, "an orbiting hazard circles at the arena-scaled radius",
		radius >= mover.orbit_radius_min and radius <= mover.orbit_radius_max, str(radius))
	var steps := 0
	var max_reach := 0.0
	while steps < 400:
		center.advance_orbit(0.05, 12.0)
		max_reach = maxf(max_reach, absf(center.position.x) + center.radius)
		max_reach = maxf(max_reach, absf(center.position.z) + center.radius)
		steps += 1
	_check(results, "a full orbit never leaves the floor", max_reach <= 12.0, "reach=%s" % str(max_reach))
	_check(results, "the orbit position travels (it is not the authored origin)",
		not is_equal_approx(center.position.distance_to(center.origin), 0.0))
	# Near a wall the circle has to shrink; too near it, the hazard stops instead of
	# clipping through the arena boundary (the old code orbited the arena centre and
	# ignored the authored position entirely).
	var pinned := HazardInstance.build(mover, 1, Vector3(11.4, 0.05, 0.0), mover.radius, 0.0)
	pinned.advance_orbit(0.05, 12.0)
	_check(results, "a mover with no room to circle stays where it was put",
		is_equal_approx(pinned.position.x, 11.4) and is_equal_approx(pinned.orbit_radius(12.0), 0.0),
		"pos=%s" % str(pinned.position))
	var static_hazard := HazardInstance.build(_vent(), 2, Vector3(4, 0.05, 4), 2.2, 4.0)
	static_hazard.advance_orbit(0.5, 12.0)
	_check(results, "a hazard with no orbit never moves",
		is_equal_approx(static_hazard.position.x, 4.0) and is_equal_approx(static_hazard.position.z, 4.0))


# ---------------------------------------------------------------- index


static func _index_matches_bruteforce(results: Array) -> void:
	var index := RadiusSpatialIndex.new()
	index.setup(Vector3.ZERO, 12.0, 1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var pads := PackedFloat32Array()
	var flags := PackedInt32Array()
	for i in range(40):
		var x := rng.randf_range(-11.0, 11.0)
		var z := rng.randf_range(-11.0, 11.0)
		xs.append(x)
		zs.append(z)
		pads.append(0.4 if i % 3 == 0 else 0.0)
		flags.append(RadiusSpatialIndex.FLAG_ENEMY if i % 4 else RadiusSpatialIndex.FLAG_PLAYER)
		index.insert(Vector3(x, 0.0, z), flags[i], pads[i])
	_check(results, "the index holds what it was given", index.element_count() == 40, str(index.element_count()))
	var mismatches := 0
	var team_mismatches := 0
	for q in range(60):
		var center := Vector3(rng.randf_range(-12.0, 12.0), 0.0, rng.randf_range(-12.0, 12.0))
		var radius := rng.randf_range(0.8, 3.6)
		var mask := RadiusSpatialIndex.FLAG_ENEMY if q % 2 == 0 else RadiusSpatialIndex.FLAG_PLAYER
		var found := index.query(center, radius, mask)
		var seen := {}
		for at in range(found):
			seen[index.result_index(at)] = true
		var brute := {}
		for probe_idx in range(40):
			if (flags[probe_idx] & mask) == 0:
				continue
			var dx := xs[probe_idx] - center.x
			var dz := zs[probe_idx] - center.z
			var allowed := radius + pads[probe_idx]
			if dx * dx + dz * dz <= allowed * allowed:
				brute[probe_idx] = true
		if seen.size() != brute.size():
			mismatches += 1
		else:
			for key in brute.keys():
				if not seen.has(key):
					team_mismatches += 1
	_check(results, "the grid returns exactly the brute-force answer, team filter included",
		mismatches == 0 and team_mismatches == 0, "count=%d membership=%d" % [mismatches, team_mismatches])
	var empty := RadiusSpatialIndex.new()
	empty.setup(Vector3.ZERO, 12.0, 2.0)
	_check(results, "an empty index reports nothing instead of crashing", empty.query(Vector3.ZERO, 3.0, 0) == 0)
	_check(results, "a zero-radius query finds nobody", index.query(Vector3.ZERO, 0.0, 0) == 0)
	# A victim launched outside the arena must still be findable, not dropped by the grid.
	var outside := RadiusSpatialIndex.new()
	outside.setup(Vector3.ZERO, 4.0, 2.0)
	outside.insert(Vector3(99.0, 0.0, 99.0), 0, 0.0)
	_check(results, "an element outside the region is clamped into the border cell, not lost",
		outside.element_count() == 1)


static func _index_reports_its_own_work(results: Array) -> void:
	var index := RadiusSpatialIndex.new()
	index.setup(Vector3.ZERO, 12.0, 1.2)
	_check(results, "cells are derived from the query radius and stay bounded",
		index.cells_x >= 4 and index.cells_x <= 17, "cells=%d" % index.cells_x)
	# Spread across the arena: at 0.2 m apart all forty bodies land in the same pair of cells, and a
	# query that reads every one of them is correct, not a broken index. The check is "the grid narrows
	# the work", which needs the work to be spread in the first place.
	for i in range(40):
		index.insert(Vector3(-11.0 + float(i % 8) * 3.0, 0.0, -11.0 + int(i / 8.0) * 3.0), 0, 0.0)
	var before := index.visited
	for q in range(10):
		index.query(Vector3(-11.0 + float(q % 5) * 0.2, 0.0, -11.0 + float(int(q / 5.0)) * 0.2), 1.2, 0)
	var work_per_query := float(index.visited - before) / 10.0
	_check(results, "a query visits a fraction of the arena instead of all of it",
		work_per_query < 40.0 * 0.6, "visited/query=%s (brute force would be 40)" % str(work_per_query))
	var snapshot := index.debug_snapshot()
	_check(results, "the index reports its own counters for the debug overlay",
		snapshot.has("elements") and snapshot.has("queries") and snapshot.has("cell_size"))
	var tiny := RadiusSpatialIndex.new()
	tiny.setup(Vector3.ZERO, 2.0, 1.0)
	var overflow_before := tiny.overflow_count
	for i in range(RadiusSpatialIndex.MAX_ELEMENTS + 8):
		tiny.insert(Vector3(float(i) * 0.01, 0.0, 0.0), 0, 0.0)
	_check(results, "overflowing the index is counted, never silent",
		tiny.overflow_count == overflow_before + 8, str(tiny.overflow_count))
	_check(results, "capacity covers a full arena of enemies plus the player",
		RadiusSpatialIndex.MAX_ELEMENTS >= 48, str(RadiusSpatialIndex.MAX_ELEMENTS))


static func _snapshots(results: Array) -> void:
	var hazards := ArenaHazards.new()
	hazards.configure(&"default_arena", 12.0, 1234)
	var first := hazards.hazard_count()
	hazards.free()
	var again := ArenaHazards.new()
	again.configure(&"default_arena", 12.0, 1234)
	var second := again.hazard_count()
	again.free()
	_check(results, "the same (arena, seed) builds the same layout twice",
		first == 11 and second == 11, "%d vs %d" % [first, second])
	var seeded := ArenaHazards.new()
	seeded.configure(&"default_arena", 12.0, 99)
	var snapshot := seeded.get_debug_snapshot()
	var kinds: Array = snapshot["kinds"]
	var same_kind_count := 0
	for kind in kinds:
		if String(kind) == "fire_vent":
			same_kind_count += 1
	_check(results, "debug snapshot keeps count + kinds and adds the clock",
		snapshot.has("count") and snapshot.has("kinds") and snapshot.has("game_time") and snapshot.has("index")
			and int(snapshot["count"]) == 11 and same_kind_count == 2, str(snapshot["count"]))
	seeded.configure(&"default_arena", 12.0, 1234)
	_check(results, "re-configuring replaces the layout instead of appending to it",
		seeded.hazard_count() == 11, str(seeded.hazard_count()))
	seeded.ignite_pulses()
	var armed := 0
	for instance in seeded.instances():
		if instance.armed:
			armed += 1
	_check(results, "ignite_pulses arms every periodic hazard", armed == 2, "armed=%d" % armed)
	seeded.free()
	var unauthored := ArenaHazards.new()
	unauthored.configure(&"no_such_arena", 12.0, 5)
	# Unauthored arena ids get the safe default rather than an empty arena, so "drop in a
	# scene + a .tres" really is enough to have hazards on wave one.
	_check(results, "an unknown arena id still gets the safe default layout",
		unauthored.hazard_count() == 4, str(unauthored.hazard_count()))
	unauthored.apply_mode_pressure(&"boss_rush")
	# boss_rush authors a plate + a mirrored spike pair = 3 more hazards.
	_check(results, "mode pressure appends authored placements without touching the arena",
		unauthored.hazard_count() == 7, str(unauthored.hazard_count()))
	unauthored.apply_mode_pressure(&"boss_rush")
	_check(results, "applying the same mode twice does not double its hazards",
		unauthored.hazard_count() == 7, str(unauthored.hazard_count()))
	unauthored.free()
