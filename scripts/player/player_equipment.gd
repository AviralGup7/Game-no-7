class_name PlayerEquipment
extends Node

## Cosmetic firearm mount. The robot authors gun-ready hands; no bow string,
## sword loadout, per-frame IK or animation-driven damage is needed.
@export var models: Dictionary[StringName, PackedScene] = {}

var _manager: WeaponManager
var _socket: BoneAttachment3D
var _model: Node3D
var _muzzle: MeshInstance3D
var _equipped: StringName = &""
var _flash_left := 0.0
var _bus := EventBindings.new()


func _ready() -> void:
	_manager = get_parent().get_node_or_null("WeaponManager") as WeaponManager
	if _manager == null:
		return
	_manager.weapon_equipped_local.connect(_on_equipped)
	_manager.weapon_switched_local.connect(_on_switched)
	_bus.bind(EventBus.projectile_fired, _on_projectile)
	var player := get_parent() as Player
	if player != null:
		player.died.connect(_clear_flash)
	_bind_skeleton()
	if _socket == null:
		call_deferred("_bind_skeleton")


func _bind_skeleton() -> void:
	if _socket != null:
		return
	var character := get_parent().get_node_or_null("VisualRoot/CharacterModel")
	var rig := HeroRigContract.skeleton(character)
	if rig == null:
		push_warning("Firearm mount: robot hand socket unavailable")
		return
	_socket = BoneAttachment3D.new()
	_socket.bone_name = "handslot.r"
	rig.add_child(_socket)
	_refresh()


func _on_equipped(_id: StringName, _slot: int) -> void:
	_refresh()


func _on_switched(_old: StringName, _new: StringName) -> void:
	_refresh()


func _refresh() -> void:
	if _socket == null or _manager == null:
		return
	var id := _manager.active_weapon_id()
	if id == _equipped and _model != null:
		return
	_clear_flash()
	_equipped = id
	if _model != null:
		_model.free()
		_model = null
	_muzzle = null
	if not models.has(id):
		return
	_model = models[id].instantiate() as Node3D
	if _model == null:
		return
	_socket.add_child(_model)
	# The muzzle is an authored marker on each generated weapon scene (GLB node).
	var marker := _model.find_child("Muzzle", true, false) as Node3D
	_muzzle = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 8
	mesh.rings = 4
	_muzzle.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.85, 1.0)
	_muzzle.material_override = material
	_muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if marker != null:
		marker.add_child(_muzzle)
	else:
		_model.add_child(_muzzle)
		_muzzle.position = Vector3(0, 0.095, 0.55)
	_muzzle.hide()
	set_process(false)


func _on_projectile(source: Node, _id: StringName) -> void:
	if source != get_parent() or _muzzle == null:
		return
	_flash_left = 0.055
	_muzzle.show()
	if _model != null:
		_model.position.z = -0.045
	set_process(true)


func _process(delta: float) -> void:
	_flash_left -= delta
	if _model != null:
		_model.position.z = move_toward(_model.position.z, 0.0, delta * 0.8)
	if _flash_left <= 0.0:
		_clear_flash()


func _clear_flash() -> void:
	_flash_left = 0.0
	if _model != null:
		_model.position = Vector3.ZERO
	if _muzzle != null:
		_muzzle.hide()
	set_process(false)


func _exit_tree() -> void:
	_bus.unbind_all()
