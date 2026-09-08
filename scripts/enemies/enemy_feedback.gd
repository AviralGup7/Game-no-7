extends Node
class_name EnemyFeedback

## Enemy damage/telegraph/death feedback: hit flash, telegraph flash, death handling.
## Purely presentational; never mutates health/state. Disabled details are gated by
## the shared settings (reduced motion / low graphics) where relevant.

var _visual: Node3D = null
var _base_modulate := Color.WHITE
var _flash_color := Color(1.0, 0.9, 0.9)
var _telegraph_color := Color(1.0, 0.55, 0.2)
var _hit_flash_duration := 0.1
var _telegraph_flash_duration := 0.18


func _ready() -> void:
	var owner := get_parent()
	_visual = owner.get_node_or_null("VisualRoot") as Node3D
	if _visual != null:
		_base_modulate = _visual.modulate


func play_damaged() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "modulate", _flash_color, 0.03)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.12, 0.06)
	tween.chain().tween_property(_visual, "modulate", _base_modulate, _hit_flash_duration)
	tween.parallel().tween_property(_visual, "scale", Vector3.ONE, 0.12)


func play_crit() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "modulate", Color(1.0, 0.92, 0.35), 0.04)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.22, 0.08)
	tween.chain().tween_property(_visual, "modulate", _base_modulate, 0.18)
	tween.parallel().tween_property(_visual, "scale", Vector3.ONE, 0.18)


## Attack/dash/fuse telegraph: warm warning flash, slower return than the hit flash
## so the windup reads at a distance.
func play_telegraph() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", _telegraph_color, 0.05)
	tween.tween_property(_visual, "modulate", _base_modulate, _telegraph_flash_duration)


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
	var is_elite := color.r > 0.85 and color.g < 0.35
	for mesh in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for idx in mi.get_surface_override_material_count():
			mi.set_surface_override_material(idx, null)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.62
		if is_elite:
			mat.emission_enabled = true
			mat.emission = color * 0.7
			mat.emission_energy_multiplier = 0.9
		mi.material_override = mat
	_base_modulate = color
	if is_elite:
		_add_elite_aura()


func _add_elite_aura() -> void:
	if _visual == null or _visual.get_node_or_null("EliteAura") != null:
		return
	var aura := Node3D.new()
	aura.name = "EliteAura"
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	ring.mesh = quad
	ring.rotation_degrees.x = -90.0
	ring.position.y = 0.02
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.28, 0.12, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.12)
	mat.emission_energy_multiplier = 0.6
	ring.material_override = mat
	aura.add_child(ring)
	var light := OmniLight3D.new()
	light.omni_range = 2.2
	light.light_energy = 0.85
	light.light_color = Color(1.0, 0.32, 0.15)
	light.position.y = 1.0
	aura.add_child(light)
	_visual.add_child(aura)
	# Gentle pulse
	var tween := aura.create_tween()
	tween.set_loops()
	tween.tween_property(ring, "scale", Vector3(1.15, 1.15, 1.15), 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ring, "scale", Vector3.ONE, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func get_debug_snapshot() -> Dictionary:
	return {"visual_present": _visual != null}

## Hardened: validate feedback triggers.
func _validated_feedback(kind: StringName) -> bool:
	if kind == &"":
		return false
	if not is_inside_tree():
		return false
	return true

