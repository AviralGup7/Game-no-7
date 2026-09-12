class_name SpawnPlacer
extends RefCounted

## Spawn-point selection, extracted from SpawnManager. Picks validated arena
## markers for an archetype (distance + bounds + marker-metadata rules) with a
## relaxed fallback so a player camping every marker cannot stall a wave.
## All-static; the arena is only ever touched through its documented methods.

const DEFAULT_MIN_SPAWN_DISTANCE := 6.0
const DEFAULT_INTERIOR_HALF := 12.0


static func min_spawn_distance(arena: Arena) -> float:
	if arena != null and is_instance_valid(arena):
		return arena.get_min_spawn_distance()
	return DEFAULT_MIN_SPAWN_DISTANCE


static func interior_half(arena: Arena) -> float:
	if arena != null and is_instance_valid(arena):
		return arena.get_interior_half()
	return DEFAULT_INTERIOR_HALF


## Pick a random valid marker for `archetype`, or null when every marker is
## rejected (caller falls back to fallback_point).
static func pick_point(arena: Arena, player_position: Vector3, archetype: StringName, rng: RandomNumberGenerator) -> Node3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var points: Array = arena.get_spawn_points()
	var half := interior_half(arena)
	points = filter_spawn_points(points, player_position, min_spawn_distance(arena), archetype, half)
	points = points.filter(func(point: Node3D) -> bool: return position_is_clear(arena, point.global_position))
	if points.is_empty():
		return null
	return points[rng.randi_range(0, points.size() - 1) if rng != null else 0] as Node3D


## Fallback point that ignores the min-distance rule but still keeps the spawn
## inside the arena interior.
static func fallback_point(arena: Arena, archetype: StringName = &"") -> Node3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var points: Array = arena.get_spawn_points()
	for p in points:
		var node := p as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if archetype != &"" and _point_allowed_for(node, archetype) == false:
			continue
		if not position_is_clear(arena, node.global_position):
			continue
		return node
	return null


## Pure, testable filtering. Keeps points that are markers in-tree, far enough from
## the player, inside the arena interior, and permitted for the archetype.
static func filter_spawn_points(points: Array, player_position: Vector3, min_distance: float, archetype: StringName, interior_half_value: float = 12.0) -> Array:
	var half := interior_half_value
	var out: Array = []
	if not player_position.is_finite() or not is_finite(half) or not is_finite(min_distance):
		return out
	for p in points:
		var node := p as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not node.is_inside_tree():
			continue
		if _point_allowed_for(node, archetype) == false:
			continue
		var pos := node.global_position
		if not pos.is_finite():
			continue
		var dist := Vector2(pos.x, pos.z).distance_to(Vector2(player_position.x, player_position.z))
		if dist < min_distance:
			continue
		if absf(pos.x) > half - 0.5 or absf(pos.z) > half - 0.5:
			continue
		out.append(node)
	return out


## Marker/jitter/burst geometry must agree with the collision-backed nav grid.
static func position_is_clear(arena: Arena, position: Vector3) -> bool:
	if not position.is_finite():
		return false
	var half := interior_half(arena) - 0.5
	if not is_finite(half) or half < 0.0 or absf(position.x) > half or absf(position.z) > half:
		return false
	var grid := arena.get_nav_grid() if is_instance_valid(arena) else null
	return grid == null or not grid.is_built() or grid.is_walkable(position)


## Read optional marker metadata. Malformed restrictions fail closed; the
## distance-relaxed fallback still respects these archetype restrictions.
static func _point_allowed_for(point: Node, archetype: StringName) -> Variant:
	if point.has_meta("allowed_archetypes"):
		var allowed: Variant = point.get_meta("allowed_archetypes")
		if not (allowed is Array or allowed is PackedStringArray):
			return false
		if allowed.size() > 0 and archetype not in allowed:
			return false
	if point.has_meta("blocked_archetypes"):
		var blocked: Variant = point.get_meta("blocked_archetypes")
		if not (blocked is Array or blocked is PackedStringArray):
			return false
		if archetype in blocked:
			return false
	return null
