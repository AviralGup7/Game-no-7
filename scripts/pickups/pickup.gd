class_name Pickup
extends Area3D

## Pooled ground pickup: bobs idly, expires on lifetime, magnet-flies toward
## the player inside magnet_radius, and applies its effect on collection.
## Returned to the PickupManager via `release_requested` (collected, expired
## or purged) — never freed directly so drop bursts never allocate.

signal release_requested(pickup: Pickup)
signal collected(pickup: Pickup, collector: Node)

const PICKUP_GROUP := "pickups"

var config: PickupConfig = null
var level: int = 1
var _age := 0.0
var _active := false
var _base_y := 0.0
var _bob_phase := 0.0
var _player: Node3D = null
var _visual: Node3D = null
var _mesh: MeshInstance3D = null
# Lazily cache each visual per pooled pickup; subsequent drops reuse instances.
var _models: Dictionary = {}


func _ready() -> void:
	add_to_group(PICKUP_GROUP)
	_visual = get_node_or_null("Visual") as Node3D
	_mesh = get_node_or_null("Visual/Mesh") as MeshInstance3D
	monitoring = true


## Configure + drop at a position. `player` is cached for magnet/collection.
func drop(cfg: PickupConfig, at: Vector3, player: Node3D, pickup_level: int = 1) -> void:
	config = cfg
	level = maxi(pickup_level, 1)
	_player = player
	_age = 0.0
	_bob_phase = 0.0
	_active = true
	visible = true
	set_physics_process(true)
	global_position = at
	_base_y = at.y
	_apply_model()
	_apply_tint()


func _physics_process(delta: float) -> void:
	if not _active or config == null:
		return
	_age += delta
	if config.lifetime > 0.0 and _age >= config.lifetime:
		_expire()
		return
	_tick_magnet(delta)
	_tick_bob(delta)
	_tick_collect()


func _tick_magnet(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if config.magnet_radius <= 0.0:
		return
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > config.magnet_radius or dist < 0.001:
		return
	# Accelerating pull: faster when close, so pickups visibly snap in.
	var speed := config.magnet_speed * (1.0 + (1.0 - dist / config.magnet_radius))
	global_position += to.normalized() * speed * delta
	_base_y = global_position.y


func _tick_bob(delta: float) -> void:
	_bob_phase += delta * config.bob_speed
	if _visual != null:
		_visual.position.y = sin(_bob_phase) * config.bob_amplitude
		_visual.rotation.y += delta * 1.5


func _tick_collect() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var flat := Vector2(global_position.x - _player.global_position.x, global_position.z - _player.global_position.z)
	if flat.length() <= config.collect_radius:
		_collect(_player)


func _collect(collector: Node) -> void:
	if not _active:
		return
	_active = false
	collected.emit(self, collector)
	if EventBus != null:
		EventBus.pickup_collected.emit(config.pickup_id if config != null else &"", int(round(config.scaled_amount(level))) if config != null else 0, collector)
	release_requested.emit(self)


func _expire() -> void:
	_active = false
	release_requested.emit(self)


func _apply_model() -> void:
	if _visual == null or config == null:
		return
	for model in _models.values():
		(model as Node3D).visible = false
	var selected: Node3D = null
	if config.visual_scene != null:
		var key := config.visual_scene.resource_path + ":" + str(config.visual_extent)
		if not _models.has(key):
			var model := ModelVisual.create(config.visual_scene, config.visual_extent)
			if model != null:
				_visual.add_child(model)
				model.position.y = 0.2
				_models[key] = model
		selected = _models.get(key) as Node3D
	if selected != null:
		selected.visible = true
	if _mesh != null:
		_mesh.visible = selected == null
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO


func _apply_tint() -> void:
	if _mesh == null or config == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = config.tint
	mat.emission_enabled = true
	mat.emission = config.tint
	mat.emission_energy_multiplier = 0.6
	_mesh.material_override = mat


func pool_reset() -> void:
	_active = false
	config = null
	_player = null
	visible = false
	set_physics_process(false)
	global_position = Vector3(0, -100, 0)


func is_active() -> bool:
	return _active


func age() -> float:
	return _age


func get_debug_snapshot() -> Dictionary:
	return {
		"pickup": String(config.pickup_id) if config != null else "none",
		"active": _active,
		"age": _age,
		"level": level,
	}
