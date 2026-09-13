class_name DecoratorProps
extends RefCounted

## Prop-building kit for ArenaDecorator: the scene cache, the HD material pass on every
## mounted model, the primitive fallbacks, the collider sized from a prop's OWN imported
## AABB, and the two ledgers the decorator publishes (spawned nodes + nav-grid footprints).
##
## ArenaDecorator keeps the per-arena compositions and the spot picking; everything that
## turns a model path into a solid, polished prop lives here.

## Sanity clamps for a prop collider derived from imported art. A corrupt/huge
## import must never produce a room-sized invisible wall.
const MIN_PROP_HALF := 0.18
const MAX_PROP_HALF_XZ := 1.4
const MAX_PROP_HALF_Y := 2.2

var _spawned: Array[Node3D] = []
## Arena-local XZ footprints of every solid prop, published to the Arena so the
## shared nav grid blocks the same cells the colliders occupy.
var _blockers: Array[AABB] = []
var _scene_cache := {}


## Nodes this decorator added to the tree (clear() drops them all).
func spawned() -> Array[Node3D]:
	return _spawned


## Arena-local footprints of every solid prop, for `Arena.register_decoration_blockers`.
func blockers() -> Array[AABB]:
	return _blockers


## Track a node the decorator added so `clear()` can free it with the rest.
func adopt(node: Node3D) -> void:
	_spawned.append(node)


## Register a prop footprint with the shared nav grid.
func add_blocker(foot: AABB) -> void:
	_blockers.append(foot)


func clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	_blockers.clear()


# ---------------------- model mounting (optional) ----------------------


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
	# HD material pass so KayKit dungeon props share the same anisotropic, physically
	# tuned shading as the arena shell and actors.
	HdMaterials.polish(inst as Node3D)
	return true


# ---------------------- primitive fallbacks ----------------------


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


# ---------------------- prestige cosmetics (banners) ----------------------

## Hang the player's prestige-unlocked banners (Cosmetics KIND_BANNER) on the
## arena walls in their unlock colours. Called by Main after decorate(); a no-op
## when no banners are unlocked, so it's always safe to invoke. These are the
## in-world payoff for banner_survivor / banner_last_stand, which previously
## unlocked in save and never appeared anywhere.


# ---------------------- prop collision (solid decoration) ----------------------


## Give a floor-standing prop a real collider + a nav-grid footprint, sized from the
## model's OWN imported AABB so the invisible wall always matches the visible mesh
## (KayKit props vary in footprint, and a hardcoded box would clip or float).
func _add_prop_collision(holder: Node3D) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var bounds := _combined_local_aabb(holder)
	var center := bounds.position + bounds.size * 0.5
	var half := Vector3(
		clampf(bounds.size.x * 0.5, MIN_PROP_HALF, MAX_PROP_HALF_XZ),
		clampf(bounds.size.y * 0.5, MIN_PROP_HALF, MAX_PROP_HALF_Y),
		clampf(bounds.size.z * 0.5, MIN_PROP_HALF, MAX_PROP_HALF_XZ))
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	# The world layer is what the player and every enemy are masked against, and a static
	# prop queries nothing itself. Named, not written as bits: `collision_layer = 1` reads as a
	# constant to keep and stops meaning anything the moment a layer is renumbered, which is the bug
	# class `tool/validate_guards.py` and `tests/python/test_regress_collision_contract.py` refuse.
	body.collision_layer = CollisionLayers.WORLD_BODY_LAYER
	body.collision_mask = CollisionLayers.NO_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	holder.add_child(body)
	# Nav footprint, expanded to the axis-aligned bounds of the YAW-ROTATED box (the
	# collider inherits the holder's rotation; the nav grid is axis-aligned). The
	# centre offset is rotated by the same yaw so an off-centre model's footprint
	# lands where the mesh actually is.
	var yaw := holder.rotation.y
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	var foot := Vector3(half.x * cs + half.z * sn, half.y, half.x * sn + half.z * cs)
	var local_center := holder.transform.basis * center
	_blockers.append(AABB(holder.position + local_center - foot, foot * 2.0))


## Combined AABB of every mesh under `root`, in `root`-local space. Walks the child
## transforms explicitly: at decoration time the holder is not in the tree yet, so
## global_transform is not valid and MeshInstance3D.get_aabb() alone would ignore the
## model's own node offsets. Returns a zero AABB when nothing drawable is mounted.
func _combined_local_aabb(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node := pair[0] as Node3D
		if node == null:
			continue
		var xform: Transform3D = pair[1]
		if node != root:
			xform = xform * node.transform
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var local: AABB = xform * mi.get_aabb()
				bounds = local if not found else bounds.merge(local)
				found = true
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xform])
	if not found:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return bounds


# ---------------------- prestige banners ----------------------


## Emissive prestige banner: a tall pole with a glowing coloured cloth.
func _prestige_banner_cloth(holder: Node, color: Color) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.07
	pm.height = 4.8
	pole.mesh = pm
	pole.position.y = 2.4
	pole.material_override = _mat(Color(0.22, 0.18, 0.15))
	holder.add_child(pole)
	var cloth := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 2.4)
	cloth.mesh = quad
	cloth.position = Vector3(0, 3.0, 0.06)
	var mat := _mat(color, 1.4)
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = mat
	holder.add_child(cloth)
