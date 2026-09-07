class_name ArenaDecorator
extends Node3D

## Deterministic cosmetic dressing: pillars, rubble, banners and braziers placed
## by seed so every run in an arena looks identical (fair + testable), while
## different arenas read distinctly. Decoration is visual-only EXCEPT pillars,
## which get collision and double as line-of-sight blockers for ranged enemies.
## Budgets instance counts for mobile; everything is code-built primitives.

const MAX_PILLARS := 8
const MAX_RUBBLE := 24
const MAX_BANNERS := 6
const MAX_BRAZIERS := 4
const CENTER_CLEAR_RADIUS := 3.0

var _spawned: Array[Node3D] = []
var _rng := RngService.new()


func decorate(arena_id: StringName, arena_half: float, seed: int) -> void:
	clear()
	_rng.reseed(seed + hash(String(arena_id)) * 3)
	match String(arena_id):
		"ember_crucible":
			_place_pillars(6, arena_half, Color(0.35, 0.2, 0.18))
			_place_rubble(18, arena_half, Color(0.4, 0.25, 0.2))
			_place_braziers(4, arena_half)
		"frost_hollow":
			_place_pillars(8, arena_half, Color(0.6, 0.7, 0.85))
			_place_rubble(12, arena_half, Color(0.7, 0.8, 0.9))
			_place_banners(6, arena_half, Color(0.5, 0.7, 1.0))
		_:
			_place_pillars(4, arena_half, Color(0.5, 0.45, 0.4))
			_place_rubble(16, arena_half, Color(0.45, 0.42, 0.38))
			_place_banners(4, arena_half, Color(0.8, 0.3, 0.25))


func clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


func _open_spot(arena_half: float, margin: float) -> Vector3:
	for attempt in range(24):
		var p := _rng.point_in_disc(RngService.STREAM_ARENA, arena_half - margin)
		if Vector2(p.x, p.z).length() < CENTER_CLEAR_RADIUS:
			continue
		var blocked := false
		for n in _spawned:
			if n.global_position.distance_to(p) < 2.2:
				blocked = true
				break
		if not blocked:
			return p
	return Vector3(arena_half - margin, 0, arena_half - margin)


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


func _place_pillars(count: int, arena_half: float, color: Color) -> void:
	for i in range(mini(count, MAX_PILLARS)):
		var at := _open_spot(arena_half, 2.0)
		var body := StaticBody3D.new()
		body.position = at
		body.add_to_group("world_static")
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 4.0, 1.2)
		shape.shape = box
		shape.position.y = 2.0
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(1.2, 4.0, 1.2)
		mesh.mesh = box_mesh
		mesh.position.y = 2.0
		mesh.material_override = _mat(color)
		body.add_child(mesh)
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(1.6, 0.4, 1.6)
		cap.mesh = cap_mesh
		cap.position.y = 4.1
		cap.material_override = _mat(color.darkened(0.2))
		body.add_child(cap)
		add_child(body)
		_spawned.append(body)


func _place_rubble(count: int, arena_half: float, color: Color) -> void:
	for i in range(mini(count, MAX_RUBBLE)):
		var at := _open_spot(arena_half, 1.0)
		var mesh := MeshInstance3D.new()
		var rock := BoxMesh.new()
		var s := _rng.randf_range(RngService.STREAM_ARENA, 0.25, 0.7)
		rock.size = Vector3(s, s * 0.7, s)
		mesh.mesh = rock
		mesh.position = at + Vector3(0, s * 0.3, 0)
		mesh.rotation.y = _rng.randf_range(RngService.STREAM_ARENA, -PI, PI)
		mesh.material_override = _mat(color.lightened(_rng.randf_range(RngService.STREAM_COSMETIC, -0.08, 0.08)))
		add_child(mesh)
		_spawned.append(mesh)


func _place_banners(count: int, arena_half: float, color: Color) -> void:
	for i in range(mini(count, MAX_BANNERS)):
		var angle := TAU * float(i) / float(maxi(count, 1))
		var at := Vector3(cos(angle) * (arena_half - 0.6), 0, sin(angle) * (arena_half - 0.6))
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.08
		pole_mesh.bottom_radius = 0.08
		pole_mesh.height = 4.5
		pole.mesh = pole_mesh
		pole.position = at + Vector3(0, 2.25, 0)
		pole.material_override = _mat(Color(0.3, 0.25, 0.2))
		add_child(pole)
		_spawned.append(pole)
		var cloth := MeshInstance3D.new()
		var cloth_mesh := BoxMesh.new()
		cloth_mesh.size = Vector3(0.9, 1.6, 0.06)
		cloth.mesh = cloth_mesh
		cloth.position = at + Vector3(0, 3.4, 0)
		cloth.material_override = _mat(color, 0.15)
		add_child(cloth)
		_spawned.append(cloth)


func _place_braziers(count: int, arena_half: float) -> void:
	for i in range(mini(count, MAX_BRAZIERS)):
		var angle := TAU * float(i) / float(maxi(count, 1)) + PI / 4.0
		var at := Vector3(cos(angle) * (arena_half - 1.5), 0, sin(angle) * (arena_half - 1.5))
		var bowl := MeshInstance3D.new()
		var bowl_mesh := CylinderMesh.new()
		bowl_mesh.top_radius = 0.5
		bowl_mesh.bottom_radius = 0.3
		bowl_mesh.height = 0.5
		bowl.mesh = bowl_mesh
		bowl.position = at + Vector3(0, 0.9, 0)
		bowl.material_override = _mat(Color(0.2, 0.18, 0.18))
		add_child(bowl)
		_spawned.append(bowl)
		var flame := MeshInstance3D.new()
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.28
		flame_mesh.height = 0.7
		flame.mesh = flame_mesh
		flame.position = at + Vector3(0, 1.35, 0)
		flame.material_override = _mat(Color(1.0, 0.55, 0.15), 1.5)
		add_child(flame)
		_spawned.append(flame)


func spawned_count() -> int:
	return _spawned.size()
