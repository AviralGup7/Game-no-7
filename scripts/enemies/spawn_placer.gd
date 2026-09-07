class_name SpawnPlacer
extends RefCounted

## Spawn-point selection, extracted from SpawnManager. Picks validated arena
## markers for an archetype (distance + bounds + marker-metadata rules) with a
## relaxed fallback so a player camping every marker cannot stall a wave.
## All-static; the arena is only ever touched through its documented methods.

const DEFAULT_MIN_SPAWN_DISTANCE := 6.0
const DEFAULT_INTERIOR_HALF := 12.0


static func min_spawn_distance(arena: Node) -> float:
	if arena != null and arena.has_method("get_min_spawn_distance"):
		return float(arena.call("get_min_spawn_distance"))
	return DEFAULT_MIN_SPAWN_DISTANCE


static func interior_half(arena: Node) -> float:
	if arena != null and arena.has_method("get_interior_half"):
		return float(arena.call("get_interior_half"))
	return DEFAULT_INTERIOR_HALF


## Pick a random valid marker for `archetype`, or null when every marker is
## rejected (caller falls back to fallback_point).
static func pick_point(arena: Node, player_position: Vector3, archetype: StringName, rng: RandomNumberGenerator) -> Node3D:
	if arena == null:
		return null
	var points: Array = arena.call("get_spawn_points")
	points = filter_spawn_points(points, player_position, min_spawn_distance(arena), archetype)
	if points.is_empty():
		return null
	return points[rng.randi_range(0, points.size() - 1)] as Node3D


## Fallback point that ignores the min-distance rule but still keeps the spawn
## inside the arena interior.
static func fallback_point(arena: Node) -> Node3D:
	if arena == null:
		return null
	var half := interior_half(arena)
	var points: Array = arena.call("get_spawn_points")
	for p in points:
		var node := p as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var pos := node.global_position
		if absf(pos.x) > half - 0.5 or absf(pos.z) > half - 0.5:
			continue
		return node
	return null


## Pure, testable filtering. Keeps points that are markers in-tree, far enough from
## the player, inside the arena interior, and permitted for the archetype.
static func filter_spawn_points(points: Array, player_position: Vector3, min_distance: float, archetype: StringName) -> Array:
	var half := 12.0
	var out: Array = []
	for p in points:
		var node := p as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not node.is_inside_tree():
			continue
		if _point_allowed_for(node, archetype) == false:
			continue
		var pos := node.global_position
		var dist := Vector2(pos.x, pos.z).distance_to(Vector2(player_position.x, player_position.z))
		if dist < min_distance:
			continue
		if absf(pos.x) > half - 0.5 or absf(pos.z) > half - 0.5:
			continue
		out.append(node)
	return out


## Read optional spawn marker metadata. Returns null when the marker imposes no rule.
static func _point_allowed_for(point: Node, archetype: StringName) -> Variant:
	if point.has_meta("allowed_archetypes"):
		var allowed: Array = point.get_meta("allowed_archetypes")
		if allowed.size() > 0 and archetype not in allowed:
			return false
	if point.has_meta("blocked_archetypes"):
		var blocked: Array = point.get_meta("blocked_archetypes")
		if archetype in blocked:
			return false
	return null
