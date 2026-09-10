extends Node
class_name PlayerFeedback

## Player-local mesh overlay, delegated camera/hitstop, accessibility-safe haptics.
## No Node3D.modulate, shared material mutation, per-hit tweens, or Engine writes.
const CAMERA_RIG_GROUP := &"camera_rig"

@export var hit_flash_duration: float = 0.14
@export var low_health_threshold: float = 0.25
var _player: Player
var _visual: Node3D
var _health: HealthComponent
var _meshes: Array[MeshInstance3D] = []
var _overlay: StandardMaterial3D
var _flash_left := 0.0
var _flash_enabled := true
var _last_color := Color.TRANSPARENT
var _last_impact_frame := -1


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		return
	_visual = _player.get_node_or_null("VisualRoot") as Node3D
	# Direct node lookup, NOT _player.get_health_component(): children _ready()
	# before their parent, so the Player has not resolved its component refs yet.
	_health = _player.get_node_or_null("HealthComponent") as HealthComponent
	_collect_meshes()
	_overlay = StandardMaterial3D.new()
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.no_depth_test = false
	_player.respawned.connect(reset)


## Cache every rendered mesh for the hit-flash overlay. Re-run on respawn so
## late-mounted weapon models join the set (they attach after _ready).
func _collect_meshes() -> void:
	_meshes.clear()
	if _visual != null:
		for node in _visual.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(node as MeshInstance3D)


func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	var color := Color.TRANSPARENT
	if _health != null and not _health.is_dead():
		if _health.get_health_ratio() <= low_health_threshold:
			color = Color(0.9, 0.12, 0.06, 0.18)
		if _health.is_invulnerable():
			color = Color(0.2, 0.85, 1.0, 0.3)
	if _flash_enabled and _flash_left > 0.0:
		color = Color(1.0, 0.25, 0.15, 0.55 * _flash_left / maxf(hit_flash_duration, 0.01))
	_set_overlay(color)


func _set_overlay(color: Color) -> void:
	if color == _last_color:
		return
	_last_color = color
	_overlay.albedo_color = color
	for mesh in _meshes:
		mesh.material_overlay = _overlay if color.a > 0.0 else null


func reset() -> void:
	_flash_left = 0.0
	_collect_meshes()
	_set_overlay(Color.TRANSPARENT)


func play_hit_feedback(shake_amp: float = 0.4, duration: float = 0.25) -> void:
	_request_camera_shake(shake_amp, duration)
	if not _reduced_motion():
		_flash_left = hit_flash_duration
	_request_vibration(20, 80)


## `_shake_amp` / `_duration`: a swung-and-missed attack deliberately gets no
## camera shake (contact supplies it). The parameters mirror play_hit_feedback()
## so both feedback entry points share one call shape.
func play_attack_feedback(_shake_amp: float = 0.15, _duration: float = 0.12) -> void:
	# Contact supplies the shake; a missed swing must not feel like a landed hit.
	_request_vibration(6, 30)


func play_impact_feedback(critical: bool = false) -> void:
	if _last_impact_frame == Engine.get_physics_frames():
		return
	_last_impact_frame = Engine.get_physics_frames()
	_request_vibration(40 if critical else 18, 140 if critical else 70)
	if AudioManager != null:
		AudioManager.duck_music(0.18 if critical else 0.1, 6.0 if critical else 3.5)
	if _reduced_motion():
		return
	if get_tree() == null:
		return
	var juice := get_tree().get_first_node_in_group("hitstop_manager") as HitstopManager
	if juice != null:
		juice.request_hitstop(0.035 if critical else 0.018)
		juice.add_trauma(0.14 if critical else 0.06)
	else:
		_request_camera_shake(0.16 if critical else 0.08, 0.1)


func play_dodge_feedback() -> void:
	_request_vibration(12, 50)
	if AudioManager != null:
		AudioManager.duck_music(0.08, 2.5)
	_request_camera_shake(0.08, 0.1)


func set_visual_flash_enabled(enabled: bool) -> void:
	_flash_enabled = enabled
	if not enabled:
		_flash_left = 0.0


func _request_camera_shake(amplitude: float, duration: float) -> void:
	if _reduced_motion():
		return
	if get_tree() == null:
		return
	var cam := get_tree().get_first_node_in_group(String(CAMERA_RIG_GROUP)) as CameraRig
	if cam != null:
		cam.add_shake(amplitude, duration)


func _request_vibration(duration_msec: int, _amplitude: int) -> void:
	if SaveManager.get_settings().vibration_enabled:
		Input.vibrate_handheld(duration_msec)


func _reduced_motion() -> bool:
	return SaveManager.get_settings().reduced_motion


func get_debug_snapshot() -> Dictionary:
	return {"visual_found": _visual != null, "reduced_motion": _reduced_motion()}
