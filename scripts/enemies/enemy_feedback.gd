extends Node
class_name EnemyFeedback

## Enemy damage/telegraph/death feedback: hit flash, telegraph flash, death handling.
## Purely presentational; never mutates health/state. Hit/crit juice is gated by
## the shared reduced-motion setting; the telegraph flash (gameplay readability)
## and the death sink (structural, hides the body before free) always play.
##
## Implementation notes:
##  - Node3D has no `modulate`, so color flashes use a per-enemy overlay material
##    (same pattern as PlayerFeedback) applied to the live mesh set. Meshes are
##    re-scanned per flash so GLB models mounted after _ready are included.
##  - Scale pops are relative to the visual's CURRENT scale, never absolute, so
##    archetype visual_scale and elite bumps survive being hit.
##  - At most two short tweens (flash + pop) run per enemy; a new flash kills the
##    previous one instead of piling up.

var _visual: Node3D = null
var _overlay: StandardMaterial3D = null
var _flash_color := Color(1.0, 0.9, 0.9)
var _crit_color := Color(1.0, 0.92, 0.35)
var _telegraph_color := Color(1.0, 0.55, 0.2)
var _hit_flash_duration := 0.1
var _telegraph_flash_duration := 0.18
var _flash_tween: Tween = null
var _pop_tween: Tween = null
## Scale the in-flight pop returns to. Restored when a pop is interrupted so
## rapid hits can never ratchet the visual larger.
var _pop_base := Vector3.ONE
var _pop_base_valid := false


func _ready() -> void:
	var owner := get_parent()
	_visual = owner.get_node_or_null("VisualRoot") as Node3D
	_overlay = StandardMaterial3D.new()
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.no_depth_test = false
	_overlay.albedo_color = Color(1, 1, 1, 0)


func play_damaged() -> void:
	if _visual == null or not is_inside_tree() or _reduced_motion():
		return
	_flash(_flash_color, 0.03, _hit_flash_duration)
	_pop(1.12, 0.06, 0.12)


func play_crit() -> void:
	if _visual == null or not is_inside_tree() or _reduced_motion():
		return
	_flash(_crit_color, 0.04, 0.18)
	_pop(1.22, 0.08, 0.18)


## Attack/dash/fuse telegraph: warm warning flash, slower return than the hit flash
## so the windup reads at a distance. Always plays (gameplay information).
func play_telegraph() -> void:
	if _visual == null or not is_inside_tree():
		return
	_flash(_telegraph_color, 0.05, _telegraph_flash_duration)


func play_died() -> void:
	# Sink + shrink timed to fill EnemyBase's 0.8 s free window (0.75 s total),
	# so the death reads fully instead of vanishing early into an empty wait.
	if _visual == null or not is_inside_tree():
		return
	_kill_tweens()
	var base_pos := _visual.position
	var base_scale := _visual.scale
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "position", base_pos + Vector3(0, -0.2, 0), 0.3)
	tween.tween_property(_visual, "scale", base_scale * 1.1, 0.3)
	tween.chain().tween_property(_visual, "scale", Vector3.ZERO, 0.45)


## Color flash through the shared overlay slot (never touches albedo/override).
func _flash(color: Color, hold: float, release: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	var meshes := _target_meshes()
	if meshes.is_empty():
		return
	_overlay.albedo_color = Color(color.r, color.g, color.b, 0.55)
	for mesh in meshes:
		mesh.material_overlay = _overlay
	var tween := create_tween()
	_flash_tween = tween
	tween.tween_interval(hold)
	tween.tween_property(_overlay, "albedo_color:a", 0.0, release)
	tween.tween_callback(_clear_overlay)


func _clear_overlay() -> void:
	_flash_tween = null
	if _visual == null or not is_instance_valid(_visual):
		return
	for mesh in _target_meshes():
		if is_instance_valid(mesh) and mesh.material_overlay == _overlay:
			mesh.material_overlay = null


## Scale pop relative to whatever scale the visual currently has.
func _pop(peak: float, up_time: float, down_time: float) -> void:
	_stop_pop()
	_pop_base = _visual.scale
	_pop_base_valid = true
	var tween := create_tween()
	_pop_tween = tween
	tween.tween_property(_visual, "scale", _pop_base * peak, up_time)
	tween.tween_property(_visual, "scale", _pop_base, down_time)


func _stop_pop() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
		if _pop_base_valid and _visual != null and is_instance_valid(_visual):
			_visual.scale = _pop_base
	_pop_tween = null


func _kill_tweens() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	_stop_pop()
	_clear_overlay()


## Live mesh set under the visual root (includes late-mounted GLB models).
## Skips the fake ground-shadow decal, which must stay dark.
func _target_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _visual == null or not is_instance_valid(_visual):
		return out
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.name != &"GroundShadow":
			out.append(mesh)
	return out


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


func _reduced_motion() -> bool:
	if SaveManager == null:
		return false
	return SaveManager.get_settings().reduced_motion


func get_debug_snapshot() -> Dictionary:
	return {"visual_present": _visual != null}

## Hardened: validate feedback triggers.
func _validated_feedback(kind: StringName) -> bool:
	if kind == &"":
		return false
	if not is_inside_tree():
		return false
	return true
