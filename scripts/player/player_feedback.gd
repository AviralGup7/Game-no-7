extends Node
class_name PlayerFeedback

## Owns animation parameters, hit flash, camera-shake requests, vibration requests,
## and accessibility-safe feedback. It requests effects through the owning systems
## (camera rig via the active world, AudioManager, OS vibration) and respects the
## reduced-motion / vibration settings instead of acting directly on frames.

const CAMERA_RIG_GROUP := &"camera_rig"

var _visual: Node3D = null
var _base_modulate := Color.WHITE
var _flash_color := Color(1.0, 0.35, 0.3)
var _hit_flash_duration := 0.12


func _ready() -> void:
	_visual = _find_visual()


func _find_visual() -> Node3D:
	var owner := get_parent()
	if owner == null:
		return null
	var node := owner.get_node_or_null("VisualRoot")
	return node as Node3D


func play_hit_feedback(shake_amp: float = 0.4, duration: float = 0.25) -> void:
	_request_camera_shake(shake_amp, duration)
	_flash()
	_request_vibration(20, 80)


func play_attack_feedback(shake_amp: float = 0.15, duration: float = 0.12) -> void:
	if not _reduced_motion():
		_request_camera_shake(shake_amp, duration)


func play_dodge_feedback() -> void:
	if not _reduced_motion():
		_request_camera_shake(0.1, 0.1)


func set_visual_flash_enabled(enabled: bool) -> void:
	if enabled and _visual != null:
		_base_modulate = _visual.modulate


func _flash() -> void:
	if _visual == null:
		return
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", _flash_color, 0.03)
	tween.tween_property(_visual, "modulate", _base_modulate, _hit_flash_duration)


func _request_camera_shake(amplitude: float, duration: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cam := tree.get_first_node_in_group(String(CAMERA_RIG_GROUP))
	if cam != null and cam.has_method("add_shake"):
		cam.call("add_shake", amplitude, duration)


func _request_vibration(duration_msec: int, _amplitude: int) -> void:
	var settings := SaveManager.get_settings()
	if not settings.vibration_enabled:
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_HAPTICS):
		Input.vibrate_handheld(duration_msec)


func _reduced_motion() -> bool:
	return SaveManager.get_settings().reduced_motion


func get_debug_snapshot() -> Dictionary:
	return {
		"visual_found": _visual != null,
		"reduced_motion": _reduced_motion(),
	}
