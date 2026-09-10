extends RefCounted

## Node-level test for the "nothing walks through objects" guarantee on DECORATION.
##
## The interior obstacles and the landmark were already covered by
## test_arena_obstacles_node.gd, but the KayKit clutter the decorator scatters
## (barrels, crates, boxes, rubble, braziers, ice shards) used to be visual-only,
## so the hero and every enemy walked straight through them. This suite
## instantiates the REAL arena scene + a real ArenaDecorator headless and asserts
## that every floor-standing prop now
##
##   * carries a "PropCollision" StaticBody3D on the world layer (`CollisionLayers.
##     WORLD_BODY_LAYER`, the layer the player and every enemy are masked against) with a
##     finite, non-degenerate box shape;
##   * published a matching footprint (a typed `AABB`, not a key-bag) through
##     `ArenaDecorator.get_nav_blockers()` so the
##     shared nav grid blocks the same cells physics blocks (AI routes around);
##   * stays clear of the player start and the enemy spawn markers, so a new
##     collider can never sit on a spawn or trap the hero at run start;
##   * leaves the player start walkable in the rebuilt nav grid.
##
## Registered in run_tests.gd's NODE_SUITES (deferred phase, live tree).

const ARENA_SCENE := "res://scenes/arena/arena.tscn"
const COLLIDER_NAME := "PropCollision"
## Props are kept SPAWN_MARKER_CLEAR_RADIUS (1.7) from a marker by holder position;
## allow for the footprint centre being offset from the holder by the model's own
## AABB centre before flagging a spawn as blocked.
const MIN_MARKER_CLEARANCE := 1.0
const MIN_PLAYER_START_CLEARANCE := 1.5


static func suite() -> Array:
	var results: Array = []
	var scene: PackedScene = load(ARENA_SCENE)
	if scene == null:
		results.append({"name": "decorator: arena scene loads", "passed": false, "why": "load failed"})
		return results
	var arena := scene.instantiate() as Arena
	if arena == null:
		results.append({"name": "decorator: arena instantiates", "passed": false, "why": "instantiate failed"})
		return results
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(arena)
	var decorator := ArenaDecorator.new()
	decorator.name = "ArenaDecorator"
	arena.add_child(decorator)
	decorator.decorate(arena.get_arena_id(), arena.interior_half, 1234)
	_run_checks(results, arena, decorator)
	# Immediate (not queued) teardown: the arena's spawn markers are grouped
	# "enemy_spawn_point" and would leak into the later integration stages.
	tree.root.remove_child(arena)
	arena.free()
	return results


static func _run_checks(results: Array, arena: Arena, decorator: ArenaDecorator) -> void:
	var colliders := _find_colliders(decorator)
	var pillars := _find_structural_pillars(decorator)
	var solids := colliders.size() + pillars.size()
	var blockers: Array[AABB] = decorator.get_nav_blockers()

	results.append({
		"name": "decorator: floor props are solid (%d clutter + %d pillars)" % [colliders.size(), pillars.size()],
		"passed": colliders.size() >= 15 and pillars.size() >= 5,
		"why": "clutter=%d pillars=%d" % [colliders.size(), pillars.size()],
	})
	results.append({
		"name": "decorator: one nav footprint per solid body",
		"passed": blockers.size() == solids,
		"why": "blockers=%d solids=%d" % [blockers.size(), solids],
	})

	var bad_layer := 0
	var bad_shape := 0
	for body in colliders:
		var b := body as StaticBody3D
		if b.collision_layer != 1 or b.collision_mask != 0:
			bad_layer += 1
		if _box_shape(b) == null:
			bad_shape += 1
	results.append({
		"name": "decorator: colliders sit on world layer 1 (mask 0)",
		"passed": bad_layer == 0,
		"why": "offending=%d" % bad_layer,
	})
	results.append({
		"name": "decorator: colliders carry a finite non-degenerate box",
		"passed": bad_shape == 0,
		"why": "offending=%d" % bad_shape,
	})

	var bad_foot := 0
	for foot in blockers:
		var pos := foot.get_center()
		var hs := foot.size * 0.5
		if not (is_finite(pos.x) and is_finite(pos.z) and is_finite(hs.x) and is_finite(hs.z)):
			bad_foot += 1
		elif hs.x <= 0.0 or hs.z <= 0.0:
			bad_foot += 1
	results.append({
		"name": "decorator: nav footprints are finite and non-empty",
		"passed": bad_foot == 0,
		"why": "offending=%d" % bad_foot,
	})

	# The nav grid must actually block what the colliders block.
	var nav := arena.get_nav_grid()
	var unblocked := 0
	if nav != null:
		for blocker in blockers:
			if nav.is_walkable(blocker.get_center()):
				unblocked += 1
	results.append({
		"name": "decorator: nav grid is rebuilt and blocks every prop footprint",
		"passed": nav != null and unblocked == 0,
		"why": "unblocked=%d built=%s" % [unblocked, str(nav != null and nav.is_built())],
	})

	var start := arena.get_player_start()
	results.append({
		"name": "decorator: player start stays walkable",
		"passed": start != null and nav != null and nav.is_walkable(start.position),
		"why": "start=%s" % str(start.position if start != null else Vector3.ZERO),
	})

	# No collider may sit on the hero's spawn or on an enemy spawn marker.
	var near_start := 0
	var near_marker := 0
	var markers := arena.get_spawn_points()
	for foot in blockers:
		var pos := foot.get_center()
		if start != null and Vector2(pos.x - start.position.x, pos.z - start.position.z).length() < MIN_PLAYER_START_CLEARANCE:
			near_start += 1
		for marker in markers:
			var m := (marker as Node3D).position
			if Vector2(pos.x - m.x, pos.z - m.z).length() < MIN_MARKER_CLEARANCE:
				near_marker += 1
				break
	results.append({
		"name": "decorator: no solid prop on the player start",
		"passed": near_start == 0,
		"why": "offending=%d" % near_start,
	})
	results.append({
		"name": "decorator: no solid prop on an enemy spawn marker",
		"passed": near_marker == 0,
		"why": "offending=%d of %d markers" % [near_marker, markers.size()],
	})


## The structural pillars are the StaticBody3D holders themselves (grouped
## "world_static"); the clutter props carry a child body named PropCollision.
static func _find_structural_pillars(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is StaticBody3D and child.is_in_group("world_static"):
			out.append(child)
	return out


static func _find_colliders(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is StaticBody3D and String(node.name) == COLLIDER_NAME:
			out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


static func _box_shape(body: StaticBody3D) -> BoxShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape as BoxShape3D
			if shape == null:
				return null
			var s := shape.size
			if not (is_finite(s.x) and is_finite(s.y) and is_finite(s.z)):
				return null
			if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
				return null
			return shape
	return null
