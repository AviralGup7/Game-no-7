class_name PlayerEquipment
extends Node

## Local art mapping; weapon gameplay and saved IDs remain WeaponManager-owned.
@export var models: Dictionary[StringName, PackedScene] = {}
@export var lengths: Dictionary[StringName, float] = {}
@export var grip_offsets: Dictionary[StringName, Vector3] = {
	&"sentinel_spear": Vector3(0.0, -0.06, 0.02),
	&"stormhammer": Vector3(0.0, -0.05, 0.0),
	&"warreaxe": Vector3(0.0, -0.04, 0.02),
	&"moonlance": Vector3(0.0, -0.06, 0.02),
	&"gladius": Vector3(0.0, -0.02, 0.0),
	&"twinfangs": Vector3(0.0, -0.03, 0.01),
}
@export var preserve_source_grip: bool = true
@export var dual_wield_ids: Array[StringName] = [&"twinfangs"]
@export var two_hand_ids: Array[StringName] = [&"sentinel_spear", &"stormhammer", &"warreaxe", &"moonlance"]
@export var shaft_grip: Dictionary[StringName, Vector3] = {
	&"sentinel_spear": Vector3(0.0, 0.42, 0.0),
	&"stormhammer": Vector3(0.0, 0.28, 0.0),
	&"warreaxe": Vector3(0.0, 0.32, 0.0),
	&"moonlance": Vector3(0.0, 0.48, 0.0),
}
@export var grip_rotation_degrees := Vector3.ZERO
# The reviewed Quaternius bow has a different source axis from KayKit's sockets.
# Keep its centre grip fixed; orient its long axis vertically in the aiming pose.
@export var weapon_grip_rotations: Dictionary[StringName, Vector3] = {
	&"sunbow": Vector3(0, 90, 90),
}

var _manager: WeaponManager
var _socket: BoneAttachment3D
var _offhand: BoneAttachment3D
var _second_model: Node3D
var _model: Node3D
var _equipped: StringName = &""
var _muzzle: MeshInstance3D
var _flash_left := 0.0


var _wired := false
var _bus := EventBindings.new()
var _ik: Node = null
var _shaft_target: Marker3D = null
var _skeleton: Skeleton3D = null
var _string: MeshInstance3D = null
var _string_upper: MeshInstance3D = null
var _nock_top: Marker3D = null
var _nock_bot: Marker3D = null
var _string_drawn := 0.0
var _ik_target := 1.0


func _ready() -> void:
	_manager = get_parent().get_node_or_null("WeaponManager") as WeaponManager
	if _manager == null:
		set_process(false)
		return
	if not _bind_skeleton():
		# The mounted rig (VisualMount) normally precedes us; retry once after
		# every _ready so sibling order can never strand the weapon sockets.
		call_deferred("_bind_skeleton_deferred")
		return
	_finish_ready()


func _bind_skeleton_deferred() -> void:
	if _bind_skeleton():
		_finish_ready()


## Attach hand sockets + muzzle flash to the mounted rig. False when no rig yet.
func _bind_skeleton() -> bool:
	if _socket != null:
		return true
	var character := get_parent().get_node_or_null("VisualRoot/CharacterModel")
	if character == null:
		return false
	var skeleton := HeroRigContract.skeleton(character)
	if skeleton == null:
		return false
	# The source includes a full alternate loadout: hide weapons/shields, not armour.
	for node in character.find_children("*", "MeshInstance3D", true, false):
		if "Sword" in node.name or "Shield" in node.name:
			(node as MeshInstance3D).hide()
	_skeleton = skeleton
	_socket = BoneAttachment3D.new()
	_socket.bone_name = "handslot.r"
	skeleton.add_child(_socket)
	_offhand = BoneAttachment3D.new()
	_offhand.bone_name = "handslot.l"
	skeleton.add_child(_offhand)
	_muzzle = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 8
	sphere.rings = 4
	_muzzle.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.8, 0.25)
	_muzzle.material_override = material
	_muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_socket.add_child(_muzzle)
	_muzzle.position.y = 0.5
	_muzzle.hide()
	return true


## Wire equip signals exactly once, then mount the active weapon model.
func _finish_ready() -> void:
	if _socket == null or _manager == null:
		return
	if not _wired:
		_wired = true
		_manager.weapon_equipped_local.connect(_on_equipped)
		_manager.weapon_switched_local.connect(_on_switched)
		_bus.bind(EventBus.projectile_fired, _on_projectile)
		get_parent().died.connect(_clear_flash)
		get_parent().respawned.connect(_refresh)
		set_process(false)
	_refresh()


func _exit_tree() -> void:
	_teardown_ik()
	_bus.unbind_all()


func _on_equipped(_id: StringName, _slot: int) -> void:
	_refresh()


func _on_switched(_old: StringName, _new: StringName) -> void:
	_refresh()


func _refresh() -> void:
	if _socket == null and _bind_skeleton():
		# Late-bound rig (see _ready): wire signals exactly once, then mount.
		_finish_ready()
		return
	if _socket == null:
		return
	_clear_flash()
	var id := _manager.active_weapon_id()
	# The corrected bow aims along -socket Y; other ranged assets use +Y.
	if _muzzle != null:
		_muzzle.position = Vector3(0, -0.12 if id == &"sunbow" else 0.5, 0)
	if id == _equipped:
		return
	_equipped = id
	_teardown_ik()
	if _second_model != null:
		_second_model.free()
		_second_model = null
	if _model != null:
		_model.free()
		_model = null
	if not models.has(id):
		return
	_model = _make_model(id)
	if _model != null:
		_socket.add_child(_model)
		if id == &"gladius":
			HdMaterials.polish(_model, &"player", true)
		_model.rotation_degrees = weapon_grip_rotations.get(id, grip_rotation_degrees)
	if id in dual_wield_ids:
		_second_model = _make_model(id)
		if _second_model != null:
			_offhand.add_child(_second_model)
			_second_model.rotation_degrees = weapon_grip_rotations.get(id, grip_rotation_degrees)
	var inst := _manager.active_instance()
	_socket.bone_name = "handslot.l" if inst != null and inst.config.is_ranged() and not inst.config.is_melee() else "handslot.r"
	_setup_two_hand_ik(id)
	_setup_bow_string(id)


func _on_projectile(source: Node, _id: StringName) -> void:
	if source != get_parent() or _muzzle == null:
		return
	_flash_left = 0.06
	_muzzle.show()
	_string_drawn = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_flash_left -= delta
	_place_bow_string(delta)
	_tick_ik(delta)
	if _flash_left <= 0.0 and _string == null and (_ik == null or absf(_ik_value() - _ik_target) < 0.01):
		_clear_flash()
		if _string == null:
			set_process(false)


func _place_bow_string(delta: float) -> void:
	if _string == null or _nock_top == null or _nock_bot == null:
		return
	var shown := _model != null and _model.is_visible_in_tree()
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null and _model != null and cam.is_position_behind(_model.global_position):
		shown = false
	_string.visible = shown
	if _string_upper != null:
		_string_upper.visible = shown
	if not shown:
		return
	var drawing := _equipped == &"sunbow" and _flash_left <= 0.0
	_string_drawn = move_toward(_string_drawn, 1.0 if drawing else 0.0, delta * 8.0)
	var a := _nock_top.global_position
	var b := _nock_bot.global_position
	var grip := _model.global_position if _model != null else (a + b) * 0.5
	var mid := (a + b) * 0.5
	mid = mid.lerp(grip, 0.55 * _string_drawn)
	_orient_segment(_string, a, mid)
	if _string_upper != null:
		_orient_segment(_string_upper, mid, b)


func _orient_segment(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.01:
		mesh.visible = false
		return
	mesh.visible = true
	mesh.global_position = from.lerp(to, 0.5)
	var y_axis := along / length
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var thick := 1.0
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		var dist := cam.global_position.distance_to(mesh.global_position)
		var fov := deg_to_rad(clampf(cam.fov, 30.0, 90.0))
		thick = clampf(dist * 0.012 * tan(fov * 0.5) / tan(deg_to_rad(35.0)), 0.7, 2.0)
	mesh.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis).scaled(Vector3(thick, length, thick)), mesh.global_position)


func _clear_flash() -> void:
	_flash_left = 0.0
	if _muzzle != null:
		_muzzle.hide()
	if _string == null and _ik == null:
		set_process(false)
		set_physics_process(false)


func _make_model(id: StringName) -> Node3D:
	var fitted := ModelVisual.create(models[id], lengths.get(id, 1.0))
	if fitted != null:
		# Reviewed weapons use identity scene roots with their grip at the source
		# origin. Keep ModelVisual's scale, but undo its floor/centre repositioning:
		# a sword is held by its hilt and a bow by its centre, not its bottom edge.
		if preserve_source_grip and fitted.get_child_count() > 0 and fitted.get_child(0) is Node3D:
			(fitted.get_child(0) as Node3D).position = Vector3.ZERO
		fitted.position = grip_offsets.get(id, Vector3.ZERO)
	return fitted


func _setup_two_hand_ik(id: StringName) -> void:
	_teardown_ik()
	if _model == null or _skeleton == null or id not in two_hand_ids:
		return
	if not ClassDB.class_exists("SkeletonIK3D"):
		return
	_shaft_target = Marker3D.new()
	_shaft_target.name = "OffhandShaft"
	_model.add_child(_shaft_target)
	_shaft_target.position = shaft_grip.get(id, Vector3(0.0, 0.35, 0.0))
	var ik := ClassDB.instantiate("SkeletonIK3D") as SkeletonIK3D
	if ik == null:
		return
	var root_bone := _first_bone(["upperarm.l", "UpperArm.L", "mixamorig:LeftArm", "LeftArm"])
	var tip_bone := _first_bone(["handslot.l", "Hand.L", "mixamorig:LeftHand", "LeftHand"])
	if root_bone.is_empty() or tip_bone.is_empty():
		ik.free()
		return
	ik.set("root_bone", root_bone)
	ik.set("tip_bone", tip_bone)
	ik.set("target_node", _shaft_target.get_path())
	ik.set("override_tip_basis", false)
	_skeleton.add_child(ik)
	_ik = ik
	if ik.get("magnet") != null:
		ik.set("magnet", 0.08)
	_apply_ik(0.0)
	_ik_target = 1.0
	ik.start()
	set_process(true)


func _first_bone(names: Array) -> String:
	if _skeleton == null:
		return ""
	for n in names:
		if _skeleton.find_bone(String(n)) >= 0:
			return String(n)
	return ""


func set_slope_ik_dampen(dampen: bool) -> void:
	_ik_target = 0.35 if dampen else 1.0
	set_process(true)
	_tick_ik(0.016)


func reset_ik_dampen() -> void:
	_ik_target = 1.0
	set_process(true)
	_apply_ik(1.0)


func _tick_ik(delta: float) -> void:
	if _ik == null or not is_instance_valid(_ik):
		return
	var dt := clampf(delta if is_finite(delta) else 0.016, 0.008, 0.033)
	var cur := _ik_value()
	if absf(cur - _ik_target) < 0.01:
		_apply_ik(_ik_target)
		return
	_apply_ik(move_toward(cur, _ik_target, dt * 18.0))


func _ik_value() -> float:
	if _ik == null:
		return 1.0
	var v: Variant = _ik.get("interpolation")
	if v == null:
		v = _ik.get("influence")
	return float(v) if v != null else 1.0


func _apply_ik(value: float) -> void:
	if _ik == null or not is_instance_valid(_ik):
		return
	if _ik.get("interpolation") != null:
		_ik.set("interpolation", value)
	if _ik.get("influence") != null:
		_ik.set("influence", value)


func _setup_bow_string(id: StringName) -> void:
	if _string != null and is_instance_valid(_string):
		_string.queue_free()
	if _string_upper != null and is_instance_valid(_string_upper):
		_string_upper.queue_free()
	_string = null
	_string_upper = null
	_nock_top = null
	_nock_bot = null
	if id != &"sunbow" or _model == null:
		return
	_nock_top = Marker3D.new()
	_nock_top.name = "NockTop"
	_nock_bot = Marker3D.new()
	_nock_bot.name = "NockBot"
	_model.add_child(_nock_top)
	_model.add_child(_nock_bot)
	var aabb := _model_aabb(_model)
	# After the 90° grip rotation, the limb runs along local Y; nocks sit on the far X of the AABB.
	var limb := aabb.position.x + aabb.size.x * 0.92
	_nock_top.position = Vector3(limb, aabb.position.y + aabb.size.y * 0.92, aabb.get_center().z)
	_nock_bot.position = Vector3(limb, aabb.position.y + aabb.size.y * 0.08, aabb.get_center().z)
	_string = _make_string_mesh("BowStringLower")
	_string_upper = _make_string_mesh("BowStringUpper")
	_string.top_level = true
	_string_upper.top_level = true
	_model.add_child(_string)
	_model.add_child(_string_upper)
	set_process(true)
	set_physics_process(false)


func _model_aabb(root: Node3D) -> AABB:
	var box := AABB(Vector3(-0.02, -0.42, 0.0), Vector3(0.04, 0.84, 0.04))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null:
			continue
		var local := mesh_i.mesh.get_aabb()
		var xf := mesh_i.global_transform * root.global_transform.affine_inverse()
		var world := xf * local
		box = box.merge(world)
	return box


func _make_string_mesh(mesh_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = mesh_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.008
	mesh.bottom_radius = 0.008
	mesh.height = 1.0
	mesh.radial_segments = 6
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.12, 0.08, 0.05)
	node.material_override = mat
	node.top_level = true
	return node


func _teardown_ik() -> void:
	if _ik != null and is_instance_valid(_ik):
		if _ik is SkeletonIK3D:
			(_ik as SkeletonIK3D).stop()
		_ik.queue_free()
	_ik = null
	if _shaft_target != null and is_instance_valid(_shaft_target):
		_shaft_target.queue_free()
	_shaft_target = null
