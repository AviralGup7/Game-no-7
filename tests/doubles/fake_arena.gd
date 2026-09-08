class_name FakeArena
extends Arena

## Test double extending the REAL Arena type: SpawnPlacer/SpawnManager hold typed
## Arena references (see docs/ARCHITECTURE.md), so the fixture must be an Arena,
## not a duck-typed lookalike. It inherits the interior_half/min_spawn_distance
## exports and overrides only get_spawn_points() (its markers are hand-fed, not
## scene-grouped). _ready skips the navigation-floor/theme build the fake does
## not need.

var _markers: Array[Node3D] = []


func _ready() -> void:
	pass  # pure geometry fixture: no nav floor, no theme


func get_spawn_points() -> Array[Node3D]:
	return _markers


func add_marker(pos: Vector3) -> Node3D:
	var marker := Marker3D.new()
	marker.position = pos
	add_child(marker)
	_markers.append(marker)
	return marker


func set_interior_half(half: float) -> void:
	interior_half = half


func set_min_spawn_distance(distance: float) -> void:
	min_spawn_distance = distance
