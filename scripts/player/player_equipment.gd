class_name PlayerEquipment
extends Node

## Local art mapping; weapon gameplay and saved IDs remain WeaponManager-owned.
@export var models: Dictionary[StringName, PackedScene] = {}
@export var lengths: Dictionary[StringName, float] = {}
@export var grip_offsets: Dictionary[StringName, Vector3] = {}
@export var preserve_source_grip: bool = true
@export var dual_wield_ids: Array[StringName] = [&"twinfangs"]
@export var grip_rotation_degrees := Vector3.ZERO

var _manager: WeaponManager
var _socket: BoneAttachment3D
var _offhand: BoneAttachment3D
var _second_model: Node3D
var _model: Node3D
var _equipped: StringName = &""
var _muzzle: MeshInstance3D
var _flash_left := 0.0


var _wired := false


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
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return false
	# The source includes a full alternate loadout: hide weapons/shields, not armour.
	for node in character.find_children("*", "MeshInstance3D", true, false):
		if "Sword" in node.name or "Shield" in node.name:
			(node as MeshInstance3D).hide()
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
		EventBus.projectile_fired.connect(_on_projectile)
		get_parent().died.connect(_clear_flash)
		get_parent().respawned.connect(_refresh)
		set_process(false)
	_refresh()


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
	if id == _equipped:
		return
	_equipped = id
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
		_model.rotation_degrees = grip_rotation_degrees
	if id in dual_wield_ids:
		_second_model = _make_model(id)
		if _second_model != null:
			_offhand.add_child(_second_model)
			_second_model.rotation_degrees = grip_rotation_degrees
	var inst := _manager.active_instance()
	_socket.bone_name = "handslot.l" if inst != null and inst.config.is_ranged() and not inst.config.is_melee() else "handslot.r"


func _on_projectile(source: Node, _id: StringName) -> void:
	if source != get_parent() or _muzzle == null:
		return
	_flash_left = 0.06
	_muzzle.show()
	set_process(true)


func _process(delta: float) -> void:
	_flash_left -= delta
	if _flash_left <= 0.0:
		_clear_flash()


func _clear_flash() -> void:
	_flash_left = 0.0
	if _muzzle != null:
		_muzzle.hide()
	set_process(false)


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

## Hardened: validate equipment slot.
func _validated_slot(slot: StringName) -> bool:
	return slot != &""

