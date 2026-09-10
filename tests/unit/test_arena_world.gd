extends RefCounted

## Headless unit tests for the arena's authored world: obstacle placements, the theme
## resource and the landmark resource + builder. Pure RefCounted except where a Node3D is the
## thing under test (ArenaLandmark, ArenaObstacles.build_nodes) — those are built, asserted
## and freed inside the case.
##
## Why these tests exist: an arena's world used to be three code tables keyed by arena id
## string (`Arena.THEMES`, `Arena.PANORAMA_SKIES`, `ArenaObstacles.layout_for`'s `match`), so
## "wrong for this arena" was indistinguishable from "missing from the table" and both looked
## like success. The numbers are resources now, so what needs proving is (a) the resources
## still carry the shipped values, (b) collision, mesh and nav blocker are derived from ONE
## authored vector, and (c) an unknown or impossible authored value is refused instead of
## quietly defaulting.
##
## Resources are refcounted: nothing here frees a placement/config, only the Nodes.

const ARENA_DIR := "res://data/arenas/"
const THEME_DIR := "res://data/arena_themes/"
const ARENA_IDS := ["default_arena", "ember_crucible", "frost_hollow"]
## The shipped obstacle sets as placed (mirrors expanded), from the numbers the code tables
## held before this moved to data. If a .tres is re-authored and one of these drifts, every
## consumer (collision, mesh, nav) drifts with it — which is what this pins.
const EXPECTED_LAYOUTS := {
	"default_arena": [
		[Vector3(6.5, 0.0, 6.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(-6.5, 0.0, 6.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(6.5, 0.0, -6.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(-6.5, 0.0, -6.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(3.6, 0.0, 0.0), Vector3(0.7, 1.15, 0.7)],
		[Vector3(-3.6, 0.0, 0.0), Vector3(0.7, 1.15, 0.7)],
	],
	"ember_crucible": [
		[Vector3(8.0, 0.0, 0.0), Vector3(0.8, 1.5, 0.8)],
		[Vector3(-8.0, 0.0, 0.0), Vector3(0.8, 1.5, 0.8)],
		[Vector3(0.0, 0.0, 8.0), Vector3(0.8, 1.5, 0.8)],
		[Vector3(0.0, 0.0, -8.0), Vector3(0.8, 1.5, 0.8)],
		[Vector3(8.0, 0.0, 8.0), Vector3(0.7, 1.15, 0.7)],
		[Vector3(-8.0, 0.0, 8.0), Vector3(0.7, 1.15, 0.7)],
		[Vector3(8.0, 0.0, -8.0), Vector3(0.7, 1.15, 0.7)],
		[Vector3(-8.0, 0.0, -8.0), Vector3(0.7, 1.15, 0.7)],
	],
	"frost_hollow": [
		[Vector3(7.5, 0.0, 7.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(-7.5, 0.0, 7.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(7.5, 0.0, -7.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(-7.5, 0.0, -7.5), Vector3(0.8, 1.5, 0.8)],
		[Vector3(4.5, 0.0, 7.5), Vector3(0.7, 1.15, 0.7)],
		[Vector3(-4.5, 0.0, 7.5), Vector3(0.7, 1.15, 0.7)],
		[Vector3(4.5, 0.0, -7.5), Vector3(0.7, 1.15, 0.7)],
		[Vector3(-4.5, 0.0, -7.5), Vector3(0.7, 1.15, 0.7)],
	],
}
## The look each shipped arena must keep. These are the values `THEMES` held, so a re-authored
## .tres that "improves" one number is a visible change to the game and has to be a deliberate
## one (docs/ART_STYLE.md owns the palette).
const EXPECTED_THEMES := {
	"default_arena": {"fog_density": 0.011, "sun_energy": 1.2, "brightness": 1.02, "contrast": 1.06,
		"ambient_energy": 0.85, "glow_intensity": 0.55, "glow_bloom": 0.05, "glow_hdr_threshold": 1.1,
		"fog_sky_affect": 0.25, "fog_color": Color(0.66, 0.68, 0.72), "sun_color": Color(1.0, 0.92, 0.78)},
	"ember_crucible": {"fog_density": 0.02, "sun_energy": 1.7, "brightness": 1.0, "contrast": 1.1,
		"ambient_energy": 0.85, "glow_intensity": 0.55, "glow_bloom": 0.05, "glow_hdr_threshold": 1.1,
		"fog_sky_affect": 0.25, "fog_color": Color(0.62, 0.26, 0.1), "sun_color": Color(1.0, 0.5, 0.2)},
	"frost_hollow": {"fog_density": 0.017, "sun_energy": 1.35, "brightness": 0.98, "contrast": 1.08,
		"ambient_energy": 0.85, "glow_intensity": 0.55, "glow_bloom": 0.05, "glow_hdr_threshold": 1.1,
		"fog_sky_affect": 0.25, "fog_color": Color(0.62, 0.72, 0.9), "sun_color": Color(0.7, 0.8, 1.0)},
}
## Landmark collision per arena: the half extents the old hand-written collision shape AND the
## separately hand-written nav footprint used (one number now), the shape that body uses, and
## the emissive/light numbers that defined each arena's one moving light.
const EXPECTED_LANDMARKS := {
	"default_arena": {"kind": &"obelisk", "shape": &"box", "half": Vector3(0.55, 2.3, 0.55),
		"emissive": 1.2, "light_energy": 1.1, "light_range": 6.0},
	"ember_crucible": {"kind": &"forge", "shape": &"cylinder", "half": Vector3(1.9, 0.7, 1.9),
		"emissive": 4.5, "light_energy": 2.2, "light_range": 8.0},
	"frost_hollow": {"kind": &"crystal", "shape": &"cylinder", "half": Vector3(1.4, 1.6, 1.4),
		"emissive": 1.8, "light_energy": 1.8, "light_range": 7.0},
}


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _check_has(problems: Array[String], needle: String) -> bool:
	for p in problems:
		if String(p).find(needle) >= 0:
			return true
	return false


static func _load(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


static func _arena(arena_id: String) -> ArenaConfig:
	return _load(ARENA_DIR + arena_id + ".tres") as ArenaConfig


static func suite() -> Array:
	var results: Array = []
	_mirror_expansion(results)
	_placement_geometry(results)
	_shared_resource_is_not_mutated(results)
	_fallback_layout(results)
	_shipped_layouts(results)
	_obstacle_nodes_are_the_layout(results)
	_validation_rules_theme(results)
	_validation_rules_landmark(results)
	_validation_rules_arena(results)
	_shipped_data_validates(results)
	_shipped_theme_numbers(results)
	_shipped_landmark_numbers(results)
	_landmark_builder(results)
	_refused_kind_builds_nothing(results)
	_footprint_feeds_the_grid(results)
	return results


# ---------------------------------------------------------------- placements


static func _mirror_expansion(results: Array) -> void:
	var p := ArenaObstaclePlacement.new()
	p.position = Vector3(2.0, 0.0, 3.0)
	var expected_counts := {
		ArenaObstaclePlacement.MIRROR_NONE: 1,
		ArenaObstaclePlacement.MIRROR_X: 2,
		ArenaObstaclePlacement.MIRROR_Z: 2,
		ArenaObstaclePlacement.MIRROR_ROT180: 2,
		ArenaObstaclePlacement.MIRROR_BOTH: 4,
	}
	for mode in expected_counts:
		p.mirror = mode
		var pts := p.mirrored_positions()
		_check(results, "mirror %s yields %d positions" % [String(mode), expected_counts[mode]],
				pts.size() == int(expected_counts[mode]), str(pts))
	p.mirror = ArenaObstaclePlacement.MIRROR_BOTH
	var both := p.mirrored_positions()
	_check(results, "both expands to the four quadrants in authoring order",
			both[0] == Vector3(2.0, 0.0, 3.0) and both[1] == Vector3(-2.0, 0.0, 3.0)
			and both[2] == Vector3(2.0, 0.0, -3.0) and both[3] == Vector3(-2.0, 0.0, -3.0),
			str(both))
	# The obstacle and the hazard layouts must keep speaking one coordinate language: two
	# vocabularies for "mirror on X" in the same arena file is how drift starts.
	var agree := ArenaObstaclePlacement.VALID_MIRRORS.size() == HazardPlacement.VALID_MIRRORS.size()
	for m in ArenaObstaclePlacement.VALID_MIRRORS:
		if m not in HazardPlacement.VALID_MIRRORS:
			agree = false
	_check(results, "obstacle and hazard mirror ids agree", agree,
			str(ArenaObstaclePlacement.VALID_MIRRORS))


static func _placement_geometry(results: Array) -> void:
	var p := ArenaObstaclePlacement.new()
	p.position = Vector3(4.0, 0.0, -2.0)
	p.half_size_x = 1.0
	p.half_size_y = 2.0
	p.half_size_z = 0.5
	var foot := p.footprint()
	# The one reading that matters: position is the CENTER and the AABB is the box around it.
	# The nav grid used to receive (pos, half_size) separately and misread the convention once,
	# so the derivation lives on the type and is asserted here instead of re-typed per consumer.
	_check(results, "footprint is centred on position with 2x half extents",
			foot.position.is_equal_approx(Vector3(3.0, -2.0, -2.5))
			and foot.size.is_equal_approx(Vector3(2.0, 4.0, 1.0)), str(foot))
	_check(results, "footprint centre is the authored position",
			foot.get_center().distance_to(Vector3(4.0, 0.0, -2.0)) < 0.0001, str(foot.get_center()))
	_check(results, "half_extents reports the authored triple",
			p.half_extents().is_equal_approx(Vector3(1.0, 2.0, 0.5)), str(p.half_extents()))
	_check(results, "a placement validates inside its range floor", p.validate().is_empty(),
			str(p.validate()))
	p.half_size_y = 0.02
	_check(results, "a flat box is refused (it blocks nothing and trips the shape server)",
			_check_has(p.validate(), "half extents must be > 0.05"), str(p.validate()))


static func _shared_resource_is_not_mutated(results: Array) -> void:
	# duplicate before writing: an authored placement is shared by every copy its mirror makes,
	# and writing through it would move all four quadrants onto the last position.
	var p := ArenaObstaclePlacement.new()
	p.position = Vector3(5.0, 0.0, 5.0)
	p.mirror = ArenaObstaclePlacement.MIRROR_X
	var copy := p.duplicate_at(Vector3(-5.0, 0.0, 5.0))
	_check(results, "duplicate_at moves the copy, not the authored placement",
			p.position == Vector3(5.0, 0.0, 5.0) and copy.position == Vector3(-5.0, 0.0, 5.0),
			"%s / %s" % [str(p.position), str(copy.position)])
	_check(results, "an expanded copy does not mirror again (no 2^n explosion)",
			copy.mirror == ArenaObstaclePlacement.MIRROR_NONE and copy.mirrored_positions().size() == 1,
			String(copy.mirror))
	_check(results, "the copy keeps the authored size", copy.half_extents() == p.half_extents(),
			str(copy.half_extents()))


static func _fallback_layout(results: Array) -> void:
	# `layout_for` is what Arena actually calls, and the config-less case is the one a
	# greybox scene hits: it must arrive expanded, not as two placements with mirrors on them.
	var no_config := ArenaObstacles.layout_for(null, 12.0)
	_check(results, "an arena with no config still gets the six placed fallback obstacles",
			no_config.size() == 6 and no_config[0].mirror == ArenaObstaclePlacement.MIRROR_NONE,
			str(no_config.size()))
	var authored := ArenaObstacles.fallback_layout(12.0)
	_check(results, "the fallback is two authored placements, not six hand-listed ones",
			authored.size() == 2 and authored[0].mirror == ArenaObstaclePlacement.MIRROR_BOTH,
			str(authored.size()))
	var small := ArenaObstacles.expand(authored)
	_check(results, "expanded, the fallback is the Pit's six obstacles", small.size() == 6,
			str(small.size()))
	var big := ArenaObstacles.expand(ArenaObstacles.fallback_layout(24.0))
	var scaled := big.size() == small.size()
	for i in range(mini(big.size(), small.size())):
		if big[i].position.distance_to(small[i].position * 2.0) > 0.001 \
				or not big[i].half_extents().is_equal_approx(small[i].half_extents() * 2.0):
			scaled = false
	_check(results, "the fallback scales positions AND sizes with the floor", scaled)
	var tiny := ArenaObstacles.expand(ArenaObstacles.fallback_layout(1.0))
	_check(results, "the fallback clamps its scale (never a zero-size box)",
			tiny.size() == 6 and tiny[0].half_size_x > 0.05 and tiny[0].half_size_x < 0.21,
			str(tiny[0].half_size_x))


static func _shipped_layouts(results: Array) -> void:
	for id in ARENA_IDS:
		var cfg := _arena(id)
		if cfg == null:
			_check(results, "%s: config loads" % id, false, "res://data/arenas/%s.tres missing" % id)
			continue
		var placed := ArenaObstacles.layout_for(cfg, 12.0)
		var expected: Array = EXPECTED_LAYOUTS[id]
		var ok := placed.size() == expected.size()
		var why := "placed=%d expected=%d" % [placed.size(), expected.size()]
		if ok:
			for i in range(expected.size()):
				var want_pos: Vector3 = expected[i][0]
				var want_half: Vector3 = expected[i][1]
				if placed[i].position.distance_to(want_pos) > 0.001 \
						or not placed[i].half_extents().is_equal_approx(want_half):
					ok = false
					why = "%d: %s / %s vs %s / %s" % [i, str(placed[i].position),
							str(placed[i].half_extents()), str(want_pos), str(want_half)]
					break
		_check(results, "%s: authored layout is the shipped geometry" % id, ok, why)
		_check(results, "%s: the layout is authored, not inherited from the fallback" % id,
				not cfg.obstacle_layout.is_empty(),
				"an arena deliberately riding the fallback would need its own justification here")


static func _obstacle_nodes_are_the_layout(results: Array) -> void:
	var cfg := _arena("ember_crucible")
	if cfg == null:
		_check(results, "obstacle node build: ember config available", false, "")
		return
	var placed := ArenaObstacles.layout_for(cfg, 12.0)
	var parent := Node3D.new()
	var built := ArenaObstacles.build_nodes(parent, placed, null)
	_check(results, "build_nodes creates exactly one body per placement",
			built == placed.size() and parent.get_child_count() == placed.size(),
			"built=%d children=%d" % [built, parent.get_child_count()])
	var body_ok := true
	for i in range(placed.size()):
		var body := parent.get_child(i) as StaticBody3D
		if body == null or body.collision_layer != CollisionLayers.WORLD_BODY_LAYER \
				or body.collision_mask != CollisionLayers.NO_LAYER:
			body_ok = false
			continue
		var want := placed[i].half_extents() * 2.0
		var size_ok := false
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				size_ok = ((c as CollisionShape3D).shape as BoxShape3D).size.is_equal_approx(want)
		# y is the half height, so the box rests on the floor instead of sinking through it.
		if not size_ok or not (body.position.y > 0.0):
			body_ok = false
	_check(results, "each body is on the world layer with a box matching its placement", body_ok)
	parent.free()


# ---------------------------------------------------------------- validation


static func _validation_rules_theme(results: Array) -> void:
	var t := ArenaThemeConfig.new()
	t.theme_id = &"probe_theme"
	_check(results, "a minimal authored theme validates clean", t.validate().is_empty(), str(t.validate()))
	_check(results, "a theme is not required to name a file it cannot know (no resource_path)",
			t.validate().is_empty(), "the id-vs-filename rule must skip code-built themes")
	t.fog_density = 0.19
	_check(results, "fog thick enough to hide the far half of the arena is refused",
			_check_has(t.validate(), "would hide the far half of the arena"), str(t.validate()))
	t.fog_density = 0.011
	t.panorama_path = "user://sky.hdr"
	_check(results, "a panorama outside res:// is refused (it would not load in an export)",
			_check_has(t.validate(), "must be a res:// path"), str(t.validate()))
	t.panorama_path = "res://assets/textures/panorama/sky.png"
	_check(results, "a panorama that is not an .hdr is refused",
			_check_has(t.validate(), "must name an .hdr"), str(t.validate()))
	t.panorama_path = ""
	t.fog_color = Color(NAN, 0.5, 0.5)
	_check(results, "a non-finite colour is refused (it poisons every material that reads it)",
			_check_has(t.validate(), "fog_color has a non-finite channel"), str(t.validate()))
	t.fog_color = Color(0.5, 0.5, 0.5)
	t.tint_floor_and_walls = true
	t.floor_node_path = NodePath("")
	_check(results, "tinting with no floor to tint is refused as the typo it is",
			_check_has(t.validate(), "floor_node_path is empty"), str(t.validate()))
	t.tint_floor_and_walls = false
	_check(results, "opting out of tinting needs no floor path", t.validate().is_empty(),
			str(t.validate()))
	t.theme_id = &""
	_check(results, "an unnamed theme is refused (the debug overlay would report nothing)",
			_check_has(t.validate(), "theme_id is empty"), str(t.validate()))


static func _validation_rules_landmark(results: Array) -> void:
	var cfg := _arena("default_arena")
	if cfg == null or cfg.landmark == null:
		_check(results, "landmark rules: default arena landmark available", false, "")
		return
	_check(results, "the shipped landmark validates clean", cfg.landmark.validate().is_empty(),
			str(cfg.landmark.validate()))
	var probe := ArenaLandmarkConfig.new()
	probe.landmark_id = &"probe"
	_check(results, "a code-built landmark defaults to the obelisk silhouette",
			probe.kind == ArenaLandmarkConfig.KIND_OBELISK and probe.validate().is_empty(),
			str(probe.validate()))
	probe.kind = &"lighthouse"
	_check(results, "an unknown landmark kind is refused, not defaulted",
			_check_has(probe.validate(), "unknown landmark kind"), str(probe.validate()))
	probe.kind = ArenaLandmarkConfig.KIND_OBELISK
	probe.shape = &"capsule"
	_check(results, "an unknown collision shape is refused",
			_check_has(probe.validate(), "unknown landmark collision shape"), str(probe.validate()))
	probe.shape = ArenaLandmarkConfig.SHAPE_CYLINDER
	_check(results, "a cylinder obelisk is refused (its corners would be walkable)",
			_check_has(probe.validate(), "an obelisk is a box"), str(probe.validate()))
	probe.shape = ArenaLandmarkConfig.SHAPE_BOX
	probe.footprint_half = Vector3(0.05, 2.3, 0.05)
	_check(results, "a paper-thin footprint is refused (it is scenery, not an obstacle)",
			_check_has(probe.validate(), "it is scenery"), str(probe.validate()))
	probe.footprint_half = Vector3(0.55, 2.3, 0.55)
	probe.position = Vector3(0.0, 1.5, 0.0)
	_check(results, "a floating landmark is refused (its footprint would lie about the body)",
			_check_has(probe.validate(), "must sit on the floor"), str(probe.validate()))
	probe.position = Vector3.ZERO
	probe.light_energy = 2.0
	probe.light_range = 0.2
	_check(results, "a light with energy but no reach is refused",
			_check_has(probe.validate(), "needs a range"), str(probe.validate()))
	probe.light_range = 0.0
	probe.light_energy = 0.0
	_check(results, "no light at all is a legal authored choice", probe.validate().is_empty(),
			str(probe.validate()))


static func _validation_rules_arena(results: Array) -> void:
	var cfg := _arena("default_arena")
	if cfg == null or cfg.theme == null or cfg.landmark == null:
		_check(results, "arena rules: default config with theme + landmark", false, "")
		return
	var probe := ArenaConfig.new()
	probe.arena_id = &"probe_arena"
	probe.scene = cfg.scene
	probe.theme = cfg.theme
	probe.landmark = cfg.landmark
	var ob := ArenaObstaclePlacement.new()
	ob.position = Vector3(0.4, 0.0, 0.0)
	ob.half_size_x = 0.6
	ob.half_size_y = 1.0
	ob.half_size_z = 0.6
	probe.obstacle_layout = [ob]
	# The cross-check neither half can make alone, and the old design could not express at all:
	# an obstacle authored inside the centrepiece was invisible, still solid, and blocked the
	# AI away from a wall nobody could see.
	_check(results, "an obstacle buried in the landmark is refused",
			_check_has(probe.validate(), "buried in the landmark footprint"), str(probe.validate()))
	ob.position = Vector3(6.0, 0.0, 6.0)
	# Clear of the central landmark, the same placement validates.
	_check(results, "clear of the centrepiece, the same layout validates clean",
			probe.validate().is_empty(), str(probe.validate()))
	# The offending copy must be the MIRRORED one, or the case proves nothing: duplicate the
	# landmark and stand it off-centre (never write to the loaded resource — `load()` hands out
	# one shared instance per path, and a test that edits it corrupts every later reader).
	ob.mirror = ArenaObstaclePlacement.MIRROR_X
	ob.position = Vector3(-5.9, 0.0, 1.0)
	var off_centre := cfg.landmark.duplicate(true) as ArenaLandmarkConfig
	off_centre.position = Vector3(6.0, 0.0, 0.0)
	# Stated, not inherited: the mirrored copy sits at (+5.9, 0, 1.0), and whether that is inside the
	# centrepiece depends on the footprint. An obelisk (0.55 in z, +0.25 slack) does not contain it, so
	# the check would be about the fixture's source arena rather than about mirroring.
	off_centre.footprint_half = Vector3(1.9, 0.7, 1.9)
	probe.landmark = off_centre
	_check(results, "the overlap rule sees mirrored copies, not just the authored line",
			_check_has(probe.validate(), "buried in the landmark footprint"), str(probe.validate()))
	probe.obstacle_layout = []
	probe.theme = null
	probe.landmark = null
	_check(results, "an arena with no theme and no landmark is a legal choice",
			probe.validate().is_empty(), str(probe.validate()))


static func _shipped_data_validates(results: Array) -> void:
	for id in ARENA_IDS:
		var cfg := _arena(id)
		if cfg == null:
			_check(results, "%s: .tres loads" % id, false, "")
			continue
		_check(results, "%s: arena validates clean" % id, cfg.validate().is_empty(), str(cfg.validate()))
		var theme := _load(THEME_DIR + id + ".tres") as ArenaThemeConfig
		_check(results, "%s: theme loads and validates clean" % id,
				theme != null and theme.validate().is_empty(),
				str(theme.validate()) if theme != null else "theme file missing")
		_check(results, "%s: the arena references its own theme by resource" % id,
				cfg.theme == theme, "hard reference, so a rename is an editor error, not a runtime miss")
		_check(results, "%s: landmark id matches the file it was loaded from" % id,
				cfg.landmark != null
				and String(cfg.landmark.landmark_id) == String(cfg.landmark.resource_path.get_file().get_basename()),
				str(cfg.landmark.landmark_id) if cfg.landmark != null else "null")


static func _shipped_theme_numbers(results: Array) -> void:
	for id in ARENA_IDS:
		var theme := _load(THEME_DIR + id + ".tres") as ArenaThemeConfig
		if theme == null:
			_check(results, "%s: theme file present for the number audit" % id, false, "")
			continue
		var expected: Dictionary = EXPECTED_THEMES[id]
		var ok := true
		var why := ""
		for field in expected.keys():
			var got: Variant = theme.get(field)
			var want: Variant = expected[field]
			if want is Color:
				if not (got as Color).is_equal_approx(want):
					ok = false
					why = "%s: %s != %s" % [String(field), str(got), str(want)]
			elif absf(float(got) - float(want)) > 0.0001:
				ok = false
				why = "%s: %s != %s" % [String(field), str(got), str(want)]
		_check(results, "%s: theme keeps its shipped look" % id, ok, why)


static func _shipped_landmark_numbers(results: Array) -> void:
	for id in ARENA_IDS:
		var cfg := _arena(id)
		if cfg == null or cfg.landmark == null:
			_check(results, "%s: landmark present" % id, false, "")
			continue
		var lm := cfg.landmark
		var expected: Dictionary = EXPECTED_LANDMARKS[id]
		_check(results, "%s: landmark is the authored silhouette" % id,
				lm.kind == expected["kind"] and lm.shape == expected["shape"]
				and lm.footprint_half.is_equal_approx(expected["half"])
				and absf(lm.emissive_energy - float(expected["emissive"])) < 0.0001
				and absf(lm.light_energy - float(expected["light_energy"])) < 0.0001
				and absf(lm.light_range - float(expected["light_range"])) < 0.0001,
				"%s / %s %s" % [String(lm.kind), String(lm.shape), str(lm.footprint_half)])
		var foot := lm.footprint()
		var want_half := lm.footprint_half * lm.scale
		_check(results, "%s: footprint is the authored half extents scaled, on the floor" % id,
				foot.position.distance_to(lm.position - want_half) < 0.0001
				and foot.size.distance_to(want_half * 2.0) < 0.0001, str(foot))


# ---------------------------------------------------------------- builder


static func _landmark_builder(results: Array) -> void:
	var meshed := 0
	var lit := 0
	for id in ARENA_IDS:
		var cfg := _arena(id)
		if cfg == null or cfg.landmark == null:
			continue
		var holder := ArenaLandmark.new()
		holder.build(cfg.landmark)
		var body := holder.get_node_or_null("Body") as StaticBody3D
		_check(results, "%s: landmark has a collision body on the world layer" % id,
				body != null and body.collision_layer == CollisionLayers.WORLD_BODY_LAYER
				and body.collision_mask == CollisionLayers.NO_LAYER,
				"children=%d" % holder.get_child_count())
		var visible_meshes := holder.get_child_count() - (1 if body != null else 0)
		if holder.get_child_count() > 2:
			meshed += 1
		var has_light := false
		for c in holder.get_children():
			if c is OmniLight3D:
				has_light = true
		if has_light:
			lit += 1
		_check(results, "%s: silhouette meshes are built alongside the body" % id,
				visible_meshes >= 2, "meshes=%d" % visible_meshes)
		# The builder reports the SAME box the config authored: this is the assertion that
		# physics and the AI's intent describe one object rather than two hand-kept numbers.
		_check(results, "%s: builder footprint equals the config footprint" % id,
				holder.footprint() == cfg.landmark.footprint(), str(holder.footprint()))
		holder.free()
	_check(results, "all three shipped silhouettes build meshes", meshed == 3, str(meshed))
	_check(results, "all three shipped landmarks carry their authored light", lit == 3, str(lit))


static func _refused_kind_builds_nothing(results: Array) -> void:
	# What replaces the old `_:` arm. An id with no builder is reported and builds NOTHING.
	# This case deliberately prints one "USER ERROR: ArenaLandmark: kind ..." line in the CI
	# log: the refusal is the behaviour under test, and the log noise is the point. Godot's
	# USER ERROR is not a SCRIPT ERROR, so neither CI grep treats it as a failure.
	# previously any unrecognised kind quietly became an obelisk, so a typo read as "this arena
	# has a pillar in it" and no line of code was wrong.
	var probe := ArenaLandmarkConfig.new()
	probe.landmark_id = &"probe"
	probe.kind = &"wishing_well"
	var holder := ArenaLandmark.new()
	holder.build(probe)
	_check(results, "an unbuildable kind creates no children",
			holder.get_child_count() == 0, "children=%d" % holder.get_child_count())
	_check(results, "an unbuildable kind blocks no cells",
			not ArenaObstacles.blocks_nav(holder.footprint()), str(holder.footprint()))
	holder.free()
	var no_cfg := ArenaLandmark.new()
	no_cfg.build(null)
	_check(results, "no landmark config means an empty holder, not a default object",
			no_cfg.get_child_count() == 0 and not ArenaObstacles.blocks_nav(no_cfg.footprint()))
	no_cfg.free()


static func _footprint_feeds_the_grid(results: Array) -> void:
	# The claim the whole rebuild stands on: the box the AI avoids IS the box the body has.
	var p := ArenaObstaclePlacement.new()
	p.position = Vector3(4.0, 0.0, 0.0)
	p.half_size_x = 1.0
	p.half_size_y = 1.5
	p.half_size_z = 1.0
	var blockers: Array[AABB] = [p.footprint()]
	var grid := ArenaNavGrid.new()
	grid.build(12.0, 0.5, blockers)
	_check(results, "the authored footprint blocks its own centre",
			not grid.is_walkable(Vector3(4.0, 0.0, 0.0)))
	_check(results, "and blocks only its own footprint (plus the agent margin)",
			grid.is_walkable(Vector3(6.8, 0.0, 0.0)) and grid.obstacle_count == 1,
			"count=%d" % grid.obstacle_count)
	var broken: Array[AABB] = [AABB(Vector3(INF, 0.0, 0.0), Vector3.ONE)]
	var grid2 := ArenaNavGrid.new()
	grid2.build(12.0, 0.5, broken)
	_check(results, "a non-finite blocker is skipped rather than poisoning the grid",
			grid2.is_built() and grid2.obstacle_count == 0 and grid2.is_walkable(Vector3.ZERO),
			"count=%d" % grid2.obstacle_count)
