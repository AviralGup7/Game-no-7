class_name ArenaDecorator
extends Node3D

## Deterministic cosmetic dressing built from the approved KayKit dungeon prop library
## (assets/environment/dungeon/**), giving each arena a distinct silhouette while
## keeping run-to-run placement identical (fair + testable). Decoration is visual-only
## EXCEPT structural pillars, which keep collision and double as line-of-sight
## blockers for ranged enemies (exactly as before).
##
## Every prop load is optional: if a source model is missing/unimported the decorator
## transparently falls back to a primitive so an arena is never left undecorated.
## Budgets are clamped for mobile; nothing here allocates particles or runs per frame.

const MAX_PILLARS := 8
const MAX_CLUTTER := 22
const MAX_WALL_PROPS := 8
const CENTER_CLEAR_RADIUS := 3.0
const PILLAR_CLEARANCE := 2.3

const DUNGEON := "res://assets/environment/dungeon/"
const SC_PILLAR := DUNGEON + "pillar.glb"
const SC_PILLAR_DECOR := DUNGEON + "pillar_decorated.glb"
const SC_COLUMN := DUNGEON + "column.glb"
const SC_BANNER := {
	&"red": DUNGEON + "banner_red.glb",
	&"blue": DUNGEON + "banner_blue.glb",
	&"green": DUNGEON + "banner_green.glb",
	&"yellow": DUNGEON + "banner_yellow.glb",
}
const SC_TORCH := DUNGEON + "torch_lit.glb"
const SC_BOX := DUNGEON + "box_large.glb"
const SC_CRATES := DUNGEON + "crates_stacked.glb"
const SC_BARREL := DUNGEON + "barrel_large.glb"
const SC_RUBBLE := DUNGEON + "rubble_large.glb"

var _spawned: Array[Node3D] = []
var _rng := RngService.new()


func decorate(arena_id: StringName, arena_half: float, seed: int) -> void:
	clear()
	_rng.reseed(seed + hash(String(arena_id)) * 3)
	match String(arena_id):
		"ember_crucible":
			_compose_ember(arena_half)
		"frost_hollow":
			_compose_frost(arena_half)
		_:
			_compose_default(arena_half)


func clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


func spawned_count() -> int:
	return _spawned.size()


# ---------------------- per-arena compositions ----------------------

func _compose_default(half: float) -> void:
	_place_structural(4, half, SC_PILLAR)
	_scatter(14, half, [SC_RUBBLE, SC_BOX, SC_BARREL, SC_CRATES])
	_wall_props(half, &"red", false)


func _compose_ember(half: float) -> void:
	_place_structural(6, half, SC_PILLAR_DECOR)
	_scatter(16, half, [SC_BARREL, SC_BOX, SC_CRATES, SC_RUBBLE])
	_wall_props(half, &"yellow", true)
	# Central fire braziers for the crucible identity (kept few for mobile).
	for _i in range(2):
		var at := _centerish(half, 3.5)
		_mount_prop(SC_TORCH, at, 1.6)


func _compose_frost(half: float) -> void:
	_place_structural(8, half, SC_COLUMN)
	_scatter(10, half, [SC_RUBBLE, SC_BOX])
	_wall_props(half, &"blue", false)


# ---------------------- builders ----------------------

## Structural pillars get collision (LOS blockers). Uses model when available, else the
## legacy primitive pillar of matching footprint.
func _place_structural(count: int, half: float, scene_path: String) -> void:
	for i in range(mini(count, MAX_PILLARS)):
		var at := _open_spot(half, 2.0)
		var body := StaticBody3D.new()
		body.position = at
		body.add_to_group("world_static")
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.4, 4.0, 1.4)
		shape.shape = box
		shape.position.y = 2.0
		body.add_child(shape)
		# Model visual (idempotent: falls back to primitives automatically).
		if not _mount_model(body, scene_path, 0.0, 1.0):
			_primitive_pillar(body)
		add_child(body)
		_spawned.append(body)


## Scattered low clutter props (no collision) for grounding + occlusion interest.
func _scatter(count: int, half: float, choices: Array) -> void:
	for i in range(mini(count, MAX_CLUTTER)):
		var at := _open_spot(half, 1.0)
		var path: String = choices[i % choices.size()]
		var s := _rng.randf_range(RngService.STREAM_ARENA, 0.85, 1.25)
		var yaw := _rng.randf_range(RngService.STREAM_COSMETIC, -PI, PI)
		var holder := Node3D.new()
		holder.position = at
		if not _mount_model(holder, path, 0.0, s):
			_primitive_rock(holder, s)
		holder.rotation.y = yaw
		add_child(holder)
		_spawned.append(holder)


## Banners / torches set along the arena walls (visual only).
func _wall_props(half: float, banner: StringName, add_torches: bool) -> void:
	var banner_scene: String = SC_BANNER.get(banner, SC_BANNER[&"red"])
	var count := mini(MAX_WALL_PROPS, 8)
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var at := Vector3(cos(angle) * (half - 0.4), 0, sin(angle) * (half - 0.4))
		var holder := Node3D.new()
		holder.position = at
		holder.rotation.y = -angle
		var path := banner_scene if not add_torches or i % 2 == 0 else SC_TORCH
		if not _mount_model(holder, path, 0.0, 1.0):
			if add_torches and i % 2 == 1:
				_primitive_brazier(holder)
			else:
				_primitive_banner(holder)
		add_child(holder)
		_spawned.append(holder)


func _centerish(half: float, radius: float) -> Vector3:
	for _attempt in range(12):
		var p := _rng.point_in_disc(RngService.STREAM_ARENA, radius)
		if p.length() > CENTER_CLEAR_RADIUS * 0.9:
			return p
	return Vector3(radius * 0.7, 0, 0)


## An open spot away from centre and previously-placed structural props.
func _open_spot(half: float, margin: float) -> Vector3:
	for _attempt in range(24):
		var p := _rng.point_in_disc(RngService.STREAM_ARENA, half - margin)
		if Vector2(p.x, p.z).length() < CENTER_CLEAR_RADIUS:
			continue
		var blocked := false
		for n in _spawned:
			if n.global_position.distance_to(p) < PILLAR_CLEARANCE:
				blocked = true
				break
		if not blocked:
			return p
	return Vector3(half - margin, 0, half - margin)


## Stand-alone decorative prop (no collision) placed at a world position.
func _mount_prop(path: String, at: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	if not _mount_model(holder, path, 0.0, scale_factor):
		_primitive_brazier(holder)
	add_child(holder)
	_spawned.append(holder)


# ---------------------- model mounting (optional) ----------------------

var _scene_cache := {}


## Instantiate a cached PackedScene under `host`. Returns true when the model was
## actually added (falls back silently on missing/unimported art).
func _mount_model(host: Node, path: String, y_offset: float, scale_factor: float) -> bool:
	if not _scene_cache.has(path):
		var res := load(path)
		_scene_cache[path] = res if res is PackedScene else null
	var scene: PackedScene = _scene_cache.get(path)
	if scene == null:
		return false
	var inst := scene.instantiate()
	if inst == null or not inst is Node3D:
		if inst != null:
			inst.free()
		return false
	(inst as Node3D).position = Vector3(0, y_offset, 0)
	(inst as Node3D).scale = Vector3.ONE * scale_factor
	host.add_child(inst)
	return true


# ---------------------- primitive fallbacks ----------------------

func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


func _primitive_pillar(body: Node) -> void:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.2, 4.0, 1.2)
	mesh.mesh = box_mesh
	mesh.position.y = 2.0
	mesh.material_override = _mat(Color(0.5, 0.45, 0.4))
	body.add_child(mesh)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(1.6, 0.4, 1.6)
	cap.mesh = cap_mesh
	cap.position.y = 4.1
	cap.material_override = _mat(Color(0.4, 0.36, 0.32))
	body.add_child(cap)


func _primitive_rock(holder: Node, s: float) -> void:
	var mesh := MeshInstance3D.new()
	var rock := BoxMesh.new()
	rock.size = Vector3(s, s * 0.7, s)
	mesh.mesh = rock
	mesh.position = Vector3(0, s * 0.3, 0)
	mesh.material_override = _mat(Color(0.45, 0.42, 0.38))
	holder.add_child(mesh)


func _primitive_brazier(holder: Node) -> void:
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.3
	bm.height = 0.5
	bowl.mesh = bm
	bowl.position.y = 0.6
	bowl.material_override = _mat(Color(0.2, 0.18, 0.18))
	holder.add_child(bowl)


func _primitive_banner(holder: Node) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.08
	pm.height = 4.5
	pole.mesh = pm
	pole.position.y = 2.25
	pole.material_override = _mat(Color(0.3, 0.25, 0.2))
	holder.add_child(pole)
