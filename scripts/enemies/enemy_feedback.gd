extends Node
class_name EnemyFeedback

## Enemy damage/telegraph/death feedback: hit flash, telegraph flash, death handling.
## Purely presentational; never mutates health/state. Disabled details are gated by
## the shared settings (reduced motion / low graphics) where relevant.

var _visual: Node3D = null
var _flash_material: StandardMaterial3D = null
var _flash_meshes: Array[MeshInstance3D] = []
var _flash_visible := false
var _feedback_tween: Tween = null
var _scaling_feedback := false
var _flash_color := Color(1.0, 0.9, 0.9)
var _telegraph_color := Color(1.0, 0.55, 0.2)
var _hit_flash_duration := 0.1
var _telegraph_flash_duration := 0.18


func _ready() -> void:
	var owner := get_parent()
	_visual = owner.get_node_or_null("VisualRoot") as Node3D
	# Node3D has no modulate property. A private, reusable material overlay
	# provides the existing flash without runtime errors on every spawn/hit.
	_flash_material = StandardMaterial3D.new()
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func play_damaged() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := _begin_feedback(true)
	tween.set_parallel(true)
	tween.tween_method(_set_flash_color, Color.TRANSPARENT, _flash_color, 0.03)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.12, 0.06)
	tween.chain().tween_method(_set_flash_color, _flash_color, Color.TRANSPARENT, _hit_flash_duration)
	tween.parallel().tween_property(_visual, "scale", Vector3.ONE, 0.12)


func play_crit() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := _begin_feedback(true)
	tween.set_parallel(true)
	tween.tween_method(_set_flash_color, Color.TRANSPARENT, Color(1.0, 0.92, 0.35), 0.04)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.22, 0.08)
	tween.chain().tween_method(_set_flash_color, Color(1.0, 0.92, 0.35), Color.TRANSPARENT, 0.18)
	tween.parallel().tween_property(_visual, "scale", Vector3.ONE, 0.18)


## Attack/dash/fuse telegraph: warm warning flash, slower return than the hit flash
## so the windup reads at a distance.
func play_telegraph() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := _begin_feedback()
	tween.tween_method(_set_flash_color, Color.TRANSPARENT, _telegraph_color, 0.05)
	tween.tween_method(_set_flash_color, _telegraph_color, Color.TRANSPARENT, _telegraph_flash_duration)


func play_died() -> void:
	# A quick sink + fade before the enemy is freed.
	if _visual == null or not is_inside_tree():
		return
	var tween := _begin_feedback(true)
	tween.set_parallel(true)
	tween.tween_property(_visual, "position", _visual.position + Vector3(0, -0.2, 0), 0.25)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.15, 0.25)
	tween.chain().tween_property(_visual, "scale", Vector3.ZERO, 0.15)


func _begin_feedback(scales: bool = false) -> Tween:
	# New feedback replaces the previous transient instead of stacking writers
	# on the same transform/material during rapid multi-hit attacks.
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
		if _scaling_feedback:
			# Complete the cancelled pulse's existing return target; a telegraph
			# must not strand the model at a partially expanded scale.
			_visual.scale = Vector3.ONE
	_scaling_feedback = scales
	_set_flash_color(Color.TRANSPARENT)
	_feedback_tween = create_tween()
	return _feedback_tween


func _set_flash_color(color: Color) -> void:
	if _flash_material == null or _visual == null:
		return
	if _flash_meshes.is_empty():
		# First use is after EnemyAnimator mounted the rig, not in _ready().
		for node in _visual.find_children("*", "MeshInstance3D", true, false):
			_flash_meshes.append(node as MeshInstance3D)
	_flash_material.albedo_color = color
	var show_flash := color.a > 0.0
	if show_flash == _flash_visible:
		return
	_flash_visible = show_flash
	for mesh in _flash_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material if color.a > 0.0 else null


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
