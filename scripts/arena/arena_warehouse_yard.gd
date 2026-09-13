class_name ArenaWarehouseYard
extends RefCounted

## The authored warehouse yard north of the Pit square: the Nicholas-3D shell
## (PackedScene when imported, `GLTFDocument` when headless), the compound walls with
## their gated south face, the loading dock and the aisle columns.
##
## Each wall/column is solid by construction: it registers a collider and a nav
## footprint through the shared DecoratorProps ledger, so the nav grid blocks exactly
## the cells physics blocks.

const MAT_METAL := "res://assets/materials/arena_metal.tres"
const MAT_BRICK := "res://assets/materials/arena_wall_brick.tres"
const MAT_WOOD := "res://assets/materials/arena_wood.tres"
const WAREHOUSE_SCENE := "res://data/models/warehouse/scene.gltf"
## Outside the Pit square, north of the wall. South face (docks) meets the gate.
const WAREHOUSE_TARGET := Vector3(30.4, 5.0, 11.4)
const WAREHOUSE_CENTER := Vector3(0.0, 0.0, -25.5)
const WAREHOUSE_GATE_WIDTH := 6.0

var _props: DecoratorProps


func _init(props: DecoratorProps) -> void:
	_props = props


func _structure_mat(path: String) -> Material:
	var res := load(path)
	if res is Material:
		return res
	return _props._mat(Color(0.42, 0.38, 0.34))


## Authored architecture: a floor-standing box with its own collider and nav footprint.
## Sized from the call, not from MAX_PROP_HALF_XZ — a warehouse wall is not clutter.
## `with_mesh` is false when the Nicholas-3D glTF is already drawing the shell.


## Warehouse north of the Pit square. South face is gated (6 m) to match the
## open section of Wall_N. Collision is always the authored compound.
func _build_warehouse_compound(host: Node3D) -> void:
	var brick := _structure_mat(MAT_BRICK)
	var metal := _structure_mat(MAT_METAL)
	var wood := _structure_mat(MAT_WOOD)
	var show_shell := not _mount_warehouse_model(host)
	var half_x := WAREHOUSE_TARGET.x * 0.5
	var half_z := WAREHOUSE_TARGET.z * 0.5
	var back_z := WAREHOUSE_CENTER.z - half_z
	var south_z := WAREHOUSE_CENTER.z + half_z
	_place_structure(host, Vector3(0.0, 2.5, back_z), Vector3(WAREHOUSE_TARGET.x, 5.0, 0.5), brick, show_shell)
	_place_structure(host, Vector3(-half_x, 2.5, WAREHOUSE_CENTER.z), Vector3(0.5, 5.0, WAREHOUSE_TARGET.z), brick, show_shell)
	_place_structure(host, Vector3(half_x, 2.5, WAREHOUSE_CENTER.z), Vector3(0.5, 5.0, WAREHOUSE_TARGET.z), brick, show_shell)
	var wing := (WAREHOUSE_TARGET.x - WAREHOUSE_GATE_WIDTH) * 0.5
	var wing_x := WAREHOUSE_GATE_WIDTH * 0.5 + wing * 0.5
	_place_structure(host, Vector3(-wing_x, 2.2, south_z), Vector3(wing, 4.4, 0.45), metal, show_shell)
	_place_structure(host, Vector3(wing_x, 2.2, south_z), Vector3(wing, 4.4, 0.45), metal, show_shell)
	_place_structure(host, Vector3(0.0, 0.22, south_z + 0.6), Vector3(5.5, 0.44, 1.8), wood, true)
	_place_structure(host, Vector3(-13.2, 0.35, WAREHOUSE_CENTER.z), Vector3(3.2, 0.7, 3.0), wood, true)


func _place_structure(host: Node3D, at: Vector3, size: Vector3, mat: Material, with_mesh: bool = true) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.add_to_group("world_static")
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if with_mesh:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		if mat != null:
			mesh.material_override = mat
		body.add_child(mesh)
	host.add_child(body)
	_props.adopt(body)
	var foot_half := size * 0.5
	_props.add_blocker(AABB(at - foot_half, size))


## Nicholas-3D warehouse (CC-BY 4.0). PackedScene after editor import, otherwise
## `GLTFDocument.append_from_file` so the mesh still loads headless. Fitted to
## `WAREHOUSE_TARGET` from the imported AABB — not a guessed scale.


func _mount_warehouse_model(host: Node3D) -> bool:
	var visual := _instantiate_warehouse()
	if visual == null:
		return false
	var holder := Node3D.new()
	holder.name = "Warehouse"
	holder.add_child(visual)
	var bounds := _props._combined_local_aabb(holder)
	if bounds.size.x < 0.5 and bounds.size.z < 0.5:
		holder.free()
		return false
	_fit_warehouse_to_compound(holder, visual)
	host.add_child(holder)
	_props.adopt(holder)
	return true


func _instantiate_warehouse() -> Node3D:
	if ResourceLoader.exists(WAREHOUSE_SCENE):
		var packed := load(WAREHOUSE_SCENE)
		if packed is PackedScene:
			var scene: PackedScene = packed
			var inst := scene.instantiate()
			if inst is Node3D:
				return inst
			if inst != null:
				inst.free()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(WAREHOUSE_SCENE, state) != OK:
		return null
	var generated := doc.generate_scene(state)
	if generated is Node3D:
		return generated
	if generated != null:
		generated.free()
	return null


## Rotate the long axis onto X, uniform-scale into the north compound, sit on the floor.


func _fit_warehouse_to_compound(holder: Node3D, visual: Node3D) -> void:
	var bounds := _props._combined_local_aabb(holder)
	if bounds.size.x < 0.5 and bounds.size.z < 0.5:
		return
	if bounds.size.z > bounds.size.x + 0.5:
		visual.rotation.y += PI * 0.5
		bounds = _props._combined_local_aabb(holder)
	var sx := WAREHOUSE_TARGET.x / maxf(bounds.size.x, 0.01)
	var sz := WAREHOUSE_TARGET.z / maxf(bounds.size.z, 0.01)
	var sy := WAREHOUSE_TARGET.y / maxf(bounds.size.y, 0.01)
	visual.scale *= minf(sx, minf(sz, sy))
	bounds = _props._combined_local_aabb(holder)
	var center := bounds.position + bounds.size * 0.5
	holder.position = Vector3(
		WAREHOUSE_CENTER.x - center.x,
		-bounds.position.y,
		WAREHOUSE_CENTER.z - center.z)


## One structural column at an authored point (same collider contract as `_place_structural`).


func _place_column_at(host: Node3D, at: Vector3, scene_path: String) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.add_to_group("world_static")
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 4.0, 1.4)
	shape.shape = box
	shape.position.y = 2.0
	body.add_child(shape)
	if not _props._mount_model(body, scene_path, 0.0, 1.0):
		_props._primitive_pillar(body)
	host.add_child(body)
	_props.adopt(body)
	var foot_half := Vector3(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5)
	_props.add_blocker(AABB(at + Vector3(0.0, shape.position.y, 0.0) - foot_half, foot_half * 2.0))


## Structural pillars get collision (LOS blockers). Uses model when available, else the
## legacy primitive pillar of matching footprint. Their footprint also joins the nav
## grid: previously only ArenaObstacles + the landmark were registered, so the AI's
## INTENT walked straight through these pillars even though physics stopped the body
## (the enemy then leaned on the pillar until the stuck-nudge freed it).
