extends Node3D
class_name Arena

## Composes the static environment + markers for one arena. Contains NO wave or score
## logic. Exposes metadata and marker lookup so GameRoot / SpawnManager (later) can
## drive gameplay without scene-specific knowledge. Additional arenas = a new scene
## following this contract + an ArenaConfig resource.

const SPAWN_POINT_GROUP := &"enemy_spawn_point"

@export var arena_id: StringName = &"default_arena"
@export var config_path: String = &"res://data/arenas/default_arena.tres"


func get_arena_id() -> StringName:
	return arena_id


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
