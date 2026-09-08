class_name FakeArena
extends Node3D

## Test double implementing the documented arena duck-typing surface consumed by
## SpawnPlacer (get_spawn_points / get_interior_half / get_min_spawn_distance).
## Markers are plain Marker3D children so they pass the in-tree filter.

var _markers: Array[Node3D] = []
var _interior_half := 12.0
var _min_spawn_distance := 2.0


func get_spawn_points() -> Array[Node3D]:
	return _markers


func get_interior_half() -> float:
	return _interior_half


func get_min_spawn_distance() -> float:
	return _min_spawn_distance


func add_marker(pos: Vector3) -> Node3D:
	var marker := Marker3D.new()
	marker.position = pos
	add_child(marker)
	_markers.append(marker)
	return marker


func set_interior_half(half: float) -> void:
	_interior_half = half


func set_min_spawn_distance(distance: float) -> void:
	_min_spawn_distance = distance
