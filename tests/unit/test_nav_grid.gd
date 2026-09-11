extends RefCounted

## Headless unit tests for the shared navigation grid (ArenaNavGrid: flow
## field + A* + line of sight) and the deterministic obstacle layouts
## (ArenaObstacles). Pure RefCounted, no nodes, no physics — mirrors the
## repo's deterministic-test principle.

static func suite() -> Array:
	var results: Array = []
	_build_and_bounds(results)
	_line_of_sight(results)
	_flow_field_routes_around(results)
	_astar_routes_around(results)
	_determinism(results)
	_obstacle_layouts(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


## A wall slab across the middle of the arena: x in [4,8], z in [-1,1].
static func _wall_grid() -> ArenaNavGrid:
	var g := ArenaNavGrid.new()
	var blockers: Array[AABB] = [AABB(Vector3(4.0, -3.0, -1.0), Vector3(4.0, 6.0, 2.0))]
	g.build(12.0, 0.5, blockers)
	return g


static func _build_and_bounds(results: Array) -> void:
	var g := ArenaNavGrid.new()
	var open_ground: Array[AABB] = []
	g.build(12.0, 0.5, open_ground)
	_check(results, "grid builds and reports cell count", g.is_built() and g.width == 48 and g.depth == 48,
			"w=%d d=%d" % [g.width, g.depth])
	_check(results, "center is walkable", g.is_walkable(Vector3(0.0, 0.0, 0.0)))
	_check(results, "boundary ring is blocked (paths stay inside the walls)",
			not g.is_walkable(Vector3(11.9, 0.0, 0.0)) and not g.is_walkable(Vector3(0.0, 0.0, 11.9)))
	_check(results, "to_cell / cell_center round-trip", g.cell_center(g.to_cell(Vector3(3.25, 0.0, -4.5))).distance_to(Vector3(3.25, 0.0, -4.5)) < 0.5,
			str(g.cell_center(g.to_cell(Vector3(3.25, 0.0, -4.5)))))


static func _line_of_sight(results: Array) -> void:
	var g := _wall_grid()
	_check(results, "LOS blocked through the wall",
			not g.has_line_of_sight(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)))
	_check(results, "LOS open over the wall",
			g.has_line_of_sight(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 5.0)))
	_check(results, "LOS open without any obstacle", _wall_free_los())


static func _wall_free_los() -> bool:
	var g := ArenaNavGrid.new()
	var open_ground: Array[AABB] = []
	g.build(12.0, 0.5, open_ground)
	return g.has_line_of_sight(Vector3(-10.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0))


static func _flow_field_routes_around(results: Array) -> void:
	var g := _wall_grid()
	g.rebuild_flow_field(Vector3(11.0, 0.0, 0.0))
	# The start lane (cell row 24, center z=+0.25) sits below the wall's
	# blocked rows (21..26), so the cheaper detour is SOUTH: the field leaves
	# the start on a forward + south diagonal (exact value 0.707, 0, 0.707),
	# then runs straight south once it reaches the wall edge.
	var d := g.flow_field_direction(Vector3(0.0, 0.0, 0.0))
	_check(results, "flow field gives a direction at the start", d != Vector3.ZERO, str(d))
	_check(results, "flow field leaves the start on the cheap (south) detour diagonal",
			d.x > 0.4 and d.z > 0.4, str(d))
	var dn := g.flow_field_direction(Vector3(3.0, 0.0, 0.0))
	_check(results, "flow field runs the detour straight at the wall edge",
			absf(dn.z) > 0.9 and absf(dn.x) < 0.1, str(dn))
	var at_target := g.flow_field_direction(Vector3(11.0, 0.0, 0.0))
	_check(results, "flow field is zero at the target", at_target.length() < 0.001, str(at_target))
	var inside_wall := g.flow_field_direction(Vector3(6.0, 0.0, 0.0))
	_check(results, "blocked cell still resolves a direction (nearest walkable)",
			inside_wall != Vector3.ZERO, str(inside_wall))
	var before := g.flow_field_direction(Vector3(0.0, 0.0, 0.0))
	g.rebuild_flow_field(Vector3(11.0, 0.0, 0.2))  # same cell (46,24) -> no-op
	_check(results, "flow field rebuild is a no-op on the same target cell",
			before == g.flow_field_direction(Vector3(0.0, 0.0, 0.0)))


static func _in_wall_slab(p: Vector3) -> bool:
	# Wall x in [4,8], z in [-1,1] plus the grid's 0.5 agent margin.
	return p.x > 3.4 and p.x < 8.6 and absf(p.z) < 1.6


static func _astar_routes_around(results: Array) -> void:
	var g := _wall_grid()
	var path := g.find_path(Vector3(0.0, 0.0, 0.0), Vector3(11.0, 0.0, 0.0))
	_check(results, "A* finds a path around the wall", path.size() > 0, "size=%d" % path.size())
	if path.size() == 0:
		_check(results, "A* waypoints avoid the wall", false, "no path")
		_check(results, "A* reaches the target", false, "no path")
		_check(results, "A* detours laterally", false, "no path")
		return
	var all_clear := true
	var max_z := 0.0
	for wp in path:
		if not g.is_walkable(wp):
			all_clear = false
		if _in_wall_slab(wp):
			all_clear = false
		max_z = maxf(max_z, absf(wp.z))
	_check(results, "A* waypoints avoid the wall", all_clear, str(path))
	_check(results, "A* detours laterally around the slab", max_z > 1.0, "max_z=%.2f" % max_z)
	_check(results, "A* reaches the target", path[path.size() - 1].distance_to(Vector3(11.0, 0.0, 0.0)) < 1.0,
			str(path[path.size() - 1]))


static func _determinism(results: Array) -> void:
	var g1 := _wall_grid()
	var g2 := _wall_grid()
	g1.rebuild_flow_field(Vector3(11.0, 0.0, 0.0))
	g2.rebuild_flow_field(Vector3(11.0, 0.0, 0.0))
	var p1 := g1.find_path(Vector3(0.0, 0.0, 0.0), Vector3(-10.0, 0.0, 8.0))
	var p2 := g2.find_path(Vector3(0.0, 0.0, 0.0), Vector3(-10.0, 0.0, 8.0))
	_check(results, "identical grids produce identical paths", _paths_equal(p1, p2),
			"%d vs %d pts" % [p1.size(), p2.size()])
	_check(results, "flow field is deterministic across rebuilds",
			g1.flow_field_direction(Vector3(0.0, 0.0, 0.0)) == g2.flow_field_direction(Vector3(0.0, 0.0, 0.0)))


static func _paths_equal(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


## The authored ArenaConfig for a shipped arena, straight off disk: the same resource the
## game resolves in Arena._resolve_config, so this suite cannot pass against a copy.
static func _arena_config(arena_id: String) -> ArenaConfig:
	var path := "res://data/arenas/%s.tres" % arena_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ArenaConfig


## Expands an arena's authored placements exactly as ArenaHazards does at build time.
static func _hazard_centers(arena_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var arena := _arena_config(arena_id)
	if arena == null:
		return out
	for placement in arena.hazard_layout:
		if placement == null:
			continue
		for at in placement.mirrored_positions():
			out.append(at)
	return out


static func _obstacle_layouts(results: Array) -> void:
	var ids := ["default_arena"]
	# The merged dungeon's four axis spawn markers (scenes/arena/arena.tscn), not the old
	# per-arena ±11 the separate arenas used.
	var spawn_points := [Vector3(16, 0, 0), Vector3(-16, 0, 0), Vector3(0, 16, 0), Vector3(0, -16, 0)]
	# Hazard CENTERS come from the arena's authored layout — the same .tres ArenaHazards
	# builds from, mirrors expanded. This list used to be hand-copied out of
	# ArenaHazards._layout_defaults, which meant it silently stopped testing anything the
	# moment a layout moved; the layouts themselves are pinned against the OLD hand-tuned
	# coordinates in tests/unit/test_hazards.gd, so the data cannot drift unnoticed either.
	# Hazards are allowed to sit beside obstacles by design (a vent on the lane next to a
	# pillar); the constraint is that no hazard CENTER is buried inside a solid obstacle
	# box, which would mask the hazard's effect area.
	var half := 18.0
	for id in ids:
		_check(results, "%s: hazard layout is authored data the game can read" % id,
			_hazard_centers(id).size() >= 9, "centers=%d" % _hazard_centers(id).size())
		var layout := ArenaObstacles.layout_for(_arena_config(id), half)
		_check(results, "%s: layout is non-empty" % id, layout.size() > 0, "size=%d" % layout.size())
		if layout.is_empty():
			continue
		var in_bounds := true
		var spawn_clear := true
		var hazard_buried := false
		for obstacle in layout:
			var pos := obstacle.position
			var hs := obstacle.half_extents()
			var foot := maxf(hs.x, hs.z)
			if absf(pos.x) + foot > half - 1.0 or absf(pos.z) + foot > half - 1.0:
				in_bounds = false
			for sp in spawn_points:
				if pos.distance_to(sp) < foot + 1.2 + 0.5:
					spawn_clear = false  # jitter 1.2 + 0.5 safety
			for hz in _hazard_centers(id):
				var hp: Vector3 = hz
				if absf(hp.x - pos.x) < hs.x and absf(hp.z - pos.z) < hs.z:
					hazard_buried = true  # hazard center inside the solid box
		_check(results, "%s: obstacles inside the arena" % id, in_bounds)
		_check(results, "%s: spawn markers stay clear (jitter-proof)" % id, spawn_clear)
		_check(results, "%s: no hazard center buried in an obstacle" % id, not hazard_buried)
	# The Pit keeps a passable gate between its twin towers.
	var pit := ArenaObstacles.layout_for(_arena_config("default_arena"), half)
	var gap := 999.0
	for ob in pit:
		var pos := ob.position
		var hs := ob.half_extents()
		if absf(pos.z) < 0.01 and absf(pos.x) < 5.0:
			gap = minf(gap, absf(pos.x) - hs.x)
	_check(results, "default arena gate is passable", gap > 1.5, "inner=%.2f" % gap)
	# An authored layout is in THAT arena's metres and is never rescaled — the old table
	# silently rescaled whichever arena id it fell through to, which is exactly the surprise
	# that moved layouts into data. The fallback, which exists precisely to serve an arena of
	# unknown shape, is the one that scales.
	var authored := ArenaObstacles.layout_for(_arena_config("default_arena"), 24.0)
	var authored_small := ArenaObstacles.layout_for(_arena_config("default_arena"), 12.0)
	var absolute_ok := authored.size() == authored_small.size()
	if absolute_ok:
		for i in range(authored.size()):
			if authored[i].position.distance_to(authored_small[i].position) > 0.001:
				absolute_ok = false
	_check(results, "authored layouts are absolute, not scaled by the floor size", absolute_ok)
	var big := ArenaObstacles.fallback_layout(24.0)
	var small := ArenaObstacles.fallback_layout(12.0)
	var scales_ok := big.size() == small.size()
	if scales_ok:
		for i in range(big.size()):
			if big[i].position.distance_to(small[i].position * 2.0) > 0.01:
				scales_ok = false
	_check(results, "the fallback layout scales with arena half-extent", scales_ok)
	# The merged dungeon authors its own layout — the fallback only serves an arena that
	# authors nothing, and a dungeon that deliberately ships 13 obstacles must not be
	# mistaken for the 6-obstacle fallback (the old Pit WAS the fallback; the dungeon is not).
	var pit_cfg: ArenaConfig = _arena_config("default_arena")
	var pit_authored: Array[ArenaObstaclePlacement] = pit_cfg.obstacle_layout
	var distinct := not pit_authored.is_empty() and pit_authored.size() != small.size()
	_check(results, "the merged dungeon authors its own layout, not the fallback's", distinct,
		"authored=%d fallback=%d" % [pit_authored.size(), small.size()])
