extends Node3D
class_name Arena

## Composes the static environment + markers for one arena. Contains NO wave or score
## logic. Exposes metadata and marker lookup so GameRoot / SpawnManager (later) can
## drive gameplay without scene-specific knowledge. Additional arenas = a new scene
## following this contract + an ArenaConfig resource.

const SPAWN_POINT_GROUP := &"enemy_spawn_point"

@export var arena_id: StringName = &"default_arena"
@export var config_path: String = &"res://data/arenas/default_arena.tres"
## Interior half-extent used to keep actors in-bounds and build the nav floor.
@export var interior_half: float = 12.0
@export var min_spawn_distance: float = 6.0


func _ready() -> void:
	_build_navigation_floor()


## Deterministic, precomputed navigation floor (no runtime baking). Builds a flat
## convex NavigationMesh covering the walkable interior so NavigationAgent3D enemies
## get reliable paths on mobile without the cost/fragility of runtime baking.
func _build_navigation_floor() -> void:
	var region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null:
		return
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.4
	nm.agent_max_climb = 0.4
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	var h := maxf(interior_half - 0.75, 3.0)
	var verts := PackedVector3Array([
		Vector3(-h, 0.0, -h),
		Vector3(h, 0.0, -h),
		Vector3(h, 0.0, h),
		Vector3(-h, 0.0, h),
	])
	nm.vertices = verts
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = nm


func get_arena_id() -> StringName:
	return arena_id


func get_interior_half() -> float:
	return interior_half


func get_min_spawn_distance() -> float:
	return min_spawn_distance


func get_player_start() -> Node3D:
	return get_node_or_null("PlayerStart") as Node3D


func get_spawn_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in get_tree().get_nodes_in_group(String(SPAWN_POINT_GROUP)):
		if is_instance_valid(child) and self.is_ancestor_of(child):
			out.append(child as Node3D)
	# Fall back to direct children if not grouped in a headless context.
	if out.is_empty():
		var spawns := get_node_or_null("SpawnPoints")
		if spawns != null:
			for c in spawns.get_children():
				if c is Marker3D:
					out.append(c as Marker3D)
	return out


func get_pickup_spawn_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var node := get_node_or_null("PickupSpawnPoints")
	if node != null:
		for c in node.get_children():
			if c is Marker3D:
				out.append(c as Marker3D)
	return out


func get_debug_snapshot() -> Dictionary:
	return {
		"arena_id": String(arena_id),
		"spawn_point_count": get_spawn_points().size(),
		"player_start": _vec_string(get_player_start()),
	}


func _vec_string(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return node.global_position
