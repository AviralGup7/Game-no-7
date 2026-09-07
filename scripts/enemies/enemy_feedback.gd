extends Node
class_name EnemyFeedback

## Enemy damage/death feedback: hit flash, death handling, and optional effects.
## Purely presentational; never mutates health/state. Disabled details are gated by
## the shared settings (reduced motion / low graphics) where relevant.

var _visual: Node3D = null
var _base_modulate := Color.WHITE
var _flash_color := Color(1.0, 0.9, 0.9)
var _hit_flash_duration := 0.1


func _ready() -> void:
	var owner := get_parent()
	_visual = owner.get_node_or_null("VisualRoot") as Node3D
	if _visual != null:
		_base_modulate = _visual.modulate


func play_damaged() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", _flash_color, 0.03)
	tween.tween_property(_visual, "modulate", _base_modulate, _hit_flash_duration)


func play_died() -> void:
	# A quick sink + fade before the enemy is freed.
	if _visual == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "position", _visual.position + Vector3(0, -0.2, 0), 0.25)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.15, 0.25)
	tween.chain().tween_property(_visual, "scale", Vector3.ZERO, 0.15)


func recolor(color: Color) -> void:
	if _visual == null:
		return
	for mesh in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for idx in mi.get_surface_override_material_count():
			mi.set_surface_override_material(idx, null)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.65
		mi.material_override = mat
	_base_modulate = color


func get_debug_snapshot() -> Dictionary:
	return {"visual_present": _visual != null}
